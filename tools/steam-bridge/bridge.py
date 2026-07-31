#!/usr/bin/env python3
"""Steam bridge for Mage — standard library only (no venv, no deps).

The session is a browser sign-in: the app's WKWebView sheet captures Steam's
steamLoginSecure cookie (<steamID64>%7C%7C<JWT>) and stores it at
auth/steam-session.json next to this script (mode 0600). The JWT doubles as
a web API access token — but ONLY for IPlayerService endpoints (ISteamUser /
ISteamUserStats require publisher keys; never call them with the web JWT).

Prints exactly one JSON object on stdout per invocation; nothing else goes
to stdout.
"""
import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
AUTH_DIR = os.path.join(HERE, 'auth')
SESSION_FILE = os.path.join(AUTH_DIR, 'steam-session.json')
CACHE_FILE = os.path.join(AUTH_DIR, 'owned-cache.json')
CACHE_TTL_SECONDS = 24 * 3600

API = 'https://api.steampowered.com'
USER_AGENT = 'Mage/0.3'
# Steam account ids are steamID64 minus this base.
STEAMID_BASE = 76561197960265728

EXPIRED_MESSAGE = 'Steam session expired — sign in again'
NETWORK_MESSAGE = 'Could not reach Steam — check your connection'


def emit(payload):
    print(json.dumps(payload))
    sys.exit(0)


def emit_error(message):
    emit({'status': 'error', 'message': str(message)})


def read_json(path):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except (IOError, ValueError):
        return None


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        json.dump(obj, f)


def request(url, params=None, post=False):
    """GET (query string) or form POST; returns parsed JSON or raw text."""
    data = None
    if params and post:
        data = urllib.parse.urlencode(params).encode('utf-8')
    elif params:
        url += '?' + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, data=data,
                                 headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode('utf-8')
    return body


def api_get(path, params):
    return json.loads(request(API + path, params))


def api_post(path, params):
    return json.loads(request(API + path, params, post=True))


def load_session():
    session = read_json(SESSION_FILE)
    if session and session.get('steamid') and session.get('token'):
        return session
    return None


def token_expired(token):
    """Client-side exp pre-check: the JWT payload carries exp (~iat+24h)."""
    try:
        payload = token.split('.')[1]
        payload += '=' * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        return time.time() >= float(claims.get('exp', 0))
    except (IndexError, ValueError):
        return False  # can't tell — let the API decide


def fetch_owned(session, include_appinfo):
    """GetOwnedGames — also serves as the session validity check."""
    return api_get('/IPlayerService/GetOwnedGames/v1/', {
        'access_token': session['token'],
        'steamid': session['steamid'],
        'include_appinfo': '1' if include_appinfo else '0',
        'format': 'json',
    })


def persona_name(steamid):
    """Persona without any API key: the miniprofile page embeds it, either as
    a "persona_name" JSON blob or a <span class="persona …"> element."""
    accountid = int(steamid) - STEAMID_BASE
    html = request('https://steamcommunity.com/miniprofile/%d' % accountid)
    match = re.search(r'"persona_name"\s*:\s*"((?:[^"\\]|\\.)*)"', html)
    if match:
        try:
            return json.loads('"%s"' % match.group(1))
        except ValueError:
            return match.group(1)
    match = re.search(r'<span class="persona[^"]*">([^<]+)</span>', html)
    if match:
        return match.group(1).strip()
    return 'Steam user'


def cmd_status(_args):
    """Offline only: session file + JWT exp. No network — a transient outage
    must never flip a signed-in user to signed-out. Online validity is
    proven lazily by 'owned'/'progress' calls."""
    session = load_session()
    if not session:
        emit({'status': 'ok', 'logged_in': False})
    if token_expired(session['token']):
        emit({'status': 'ok', 'logged_in': False, 'message': EXPIRED_MESSAGE})
    account = session.get('account') or 'Steam user'
    emit({'status': 'ok', 'logged_in': True,
          'account': account,
          'steam_id': session['steamid']})


def cmd_owned(args):
    session = load_session()
    if not session:
        emit({'status': 'need_login'})
    if token_expired(session['token']):
        emit({'status': 'need_login', 'message': EXPIRED_MESSAGE})

    if not args.refresh:
        cache = read_json(CACHE_FILE)
        # Keyed by account: a different sign-in must never see the
        # previous user's library.
        if (cache and cache.get('steamid') == session['steamid']
                and time.time() - cache.get('timestamp', 0) < CACHE_TTL_SECONDS):
            emit({'status': 'ok', 'games': cache.get('games', [])})

    try:
        data = fetch_owned(session, include_appinfo=True)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            emit({'status': 'need_login', 'message': EXPIRED_MESSAGE})
        emit_error('Steam returned HTTP %d' % e.code)
    except (urllib.error.URLError, OSError, ValueError):
        emit_error(NETWORK_MESSAGE)

    response = data.get('response') or {}
    if response.get('error'):
        emit_error('Steam: %s' % response['error'])

    games = [{'appid': str(g['appid']),
              'name': g['name'],
              'playtime_forever': int(g.get('playtime_forever') or 0)}
             for g in response.get('games') or []
             if g.get('appid') and g.get('name')]
    games.sort(key=lambda g: g['name'].lower())
    write_json(CACHE_FILE, {'timestamp': time.time(),
                            'steamid': session['steamid'], 'games': games})
    # Remember the persona name for offline 'status' reads.
    if not session.get('account'):
        try:
            session['account'] = persona_name(session['steamid'])
            write_json(SESSION_FILE, session)
        except Exception:
            pass
    emit({'status': 'ok', 'games': games})


def cmd_progress(args):
    """Achievement progress for one app. POST only — GET is a 405."""
    session = load_session()
    if not session:
        emit({'status': 'need_login'})
    if token_expired(session['token']):
        emit({'status': 'need_login', 'message': EXPIRED_MESSAGE})
    try:
        data = api_post('/IPlayerService/GetAchievementsProgress/v1/', {
            'access_token': session['token'],
            'steamid': session['steamid'],
            'appids[0]': args.appid,
        })
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            emit({'status': 'need_login', 'message': EXPIRED_MESSAGE})
        emit_error('Steam returned HTTP %d' % e.code)
    except (urllib.error.URLError, OSError, ValueError):
        emit_error(NETWORK_MESSAGE)

    response = data.get('response') or {}
    if response.get('error'):
        emit_error('Steam: %s' % response['error'])
    progress = (response.get('achievement_progress') or [{}])[0]
    emit({'status': 'ok',
          'appid': int(args.appid),
          'unlocked': int(progress.get('unlocked') or 0),
          'total': int(progress.get('total') or 0),
          'percentage': float(progress.get('percentage') or 0.0)})


def cmd_logout(_args):
    try:
        os.remove(SESSION_FILE)
    except OSError:
        pass
    emit({'status': 'ok'})


def main():
    parser = argparse.ArgumentParser(prog='bridge.py')
    sub = parser.add_subparsers(dest='command', required=True)

    p = sub.add_parser('owned')
    p.add_argument('--refresh', action='store_true')

    p = sub.add_parser('progress')
    p.add_argument('appid')

    sub.add_parser('status')
    sub.add_parser('logout')

    args = parser.parse_args()
    handler = {'owned': cmd_owned, 'progress': cmd_progress,
               'status': cmd_status, 'logout': cmd_logout}[args.command]
    try:
        handler(args)
    except SystemExit:
        raise
    except Exception as e:
        emit_error('%s: %s' % (type(e).__name__, e))


if __name__ == '__main__':
    main()
