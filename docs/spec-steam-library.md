# Spec: Steam library in Mage (owned games + in-app installs)

Status: v1 implemented 2026-07-27. Mage shows the user's full Steam library
(owned, not just installed) and installs games without the Steam UI sitting
on screen. Steam.exe remains the download engine for now; Mage becomes the
launcher/browser.

## What exists today

- Library grid = bottles + Steam-installed games found by scanning
  `steamapps/appmanifest_*.acf` inside each bottle prefix (MageCore.buildLibrary),
  merged with owned-but-not-installed games from the owned-games feed
  (badged "Not installed"; one grid, not a separate section — simpler than
  the original two-section draft).
- Add game = paste store URL/AppID → `steam://install/<appid>` through the
  bottle's Steam client (MageStore.openInSteam). Steam UI is usable since
  2026-07-27 (single-process wrapper + fontconfig). Owned-game detail pages
  get an "Install in Steam" button that fires the same URL.
- Artwork: prefix `appcache/librarycache/<appid>/` for installed games;
  Steam CDN (`cdn.cloudflare.steamstatic.com/steam/apps/<appid>/library_600x900.jpg`,
  `library_hero.jpg`) for owned-only entries, fetched async and disk-cached
  under `~/Library/Caches/Mage/artwork` (FileImage in MageApp.swift).

## v1: owned games — two auth paths

Settings → "Steam account" offers both; bridge login wins when both exist.

### (a) Steam account sign-in (browser cookie, stdlib bridge)

Sign-in is Heroic-style: a WKWebView sheet (`SteamSignInSheet` in
MageApp.swift) loads `steamcommunity.com/login/home/`; password, Steam Guard
and QR are all handled by Valve's page. The app polls
`WKWebsiteDataStore.default().httpCookieStore` (1 s timer + every `didFinish`)
for the `steamLoginSecure` cookie on `.steamcommunity.com`, whose value is
`<steamID64>%7C%7C<JWT>` — the JWT is a web API access token.
`MageStore.saveSteamSession(steamid:token:)` persists it to
`tools/steam-bridge/auth/steam-session.json` (mode 0600). Sign-out deletes
the session file AND Steam's web cookies (else the sheet would instantly
re-capture the still-logged-in web session).

`mage/tools/steam-bridge/bridge.py` runs under `/usr/bin/python3`, standard
library only (no venv, no deps). One JSON object on stdout per invocation:

- `status` — validates the token via `ISteamUser/GetPlayerSummaries/v2`
  (persona name = account label, "Steam user" fallback). Prints
  `{"status":"ok","logged_in":true,"account":"…","steam_id":"…"}` or
  `logged_in:false` with a `message` on 401/403/network failure.
- `owned [--refresh]` — `IPlayerService/GetOwnedGames/v1` with
  `access_token=<JWT>`. Prints `{"status":"ok","games":[{"appid","name"},…]}`
  sorted by name, `{"status":"need_login"}` on missing/expired session, or
  `{"status":"error","message":"Steam: …"}` when Steam returns an error
  payload. Result cached to `auth/owned-cache.json` (24 h TTL unless
  `--refresh`).
- `logout` — deletes `auth/steam-session.json`, prints `{"status":"ok"}`.

All failures are JSON (`status:"error"`), never a traceback.
**The password is never seen or stored** — only Steam's revocable JWT.

### (b) Steam Web API key (read-only, no login)

User pastes a key (steamcommunity.com/dev/apikey) into Settings; stored in
UserDefaults (`SteamAPIKey`), never in recipes. steamID64 is auto-read from
`<steamCapablePrefix>/drive_c/Program Files (x86)/Steam/config/loginusers.vdf`
(`MostRecent` = `"1"` user). Fetch:
`IPlayerService/GetOwnedGames/v1/?key=…&steamid=…&include_appinfo=1&include_played_free_games=1&format=json`.
Profile must be public, else the list is empty — surfaced as a hint in Settings.

### Merging rules (both paths)

- Owned games merge into the library as `LibraryEntry(ownedOnly: true)`,
  deduped against bottles and installed Steam games by appid, grid re-sorted.
- Merging requires a `steamCapablePrefix` (install target + loginusers.vdf
  source); without a Steam prefix the owned feed is skipped entirely.
- Refetch triggers: app load (after `bridge.py status`), successful sign-in,
  and closing the Settings sheet. Sign-out removes owned-only entries.

## v2 (later, bigger): download without steam.exe

- DepotDownloader-style OSS client (SteamKit protocol): true headless
  depot downloads. The bridge already authenticates headlessly (login_key +
  guard flow), so this is now mostly depot/CDN work — either embed
  DepotDownloader (.NET runtime dependency — heavy) or extend the Python
  bridge with CDN fetch (steam.client.cdn). Defer until v1 proves the UX.
- Alternative middle step: `steam.exe -console` + `download_depot` / URL
  scheme scripting to avoid the UI; still Valve's client, still fragile.
- Also deferred: install progress display (poll `steamapps/downloading/<appid>`
  + appmanifest appearance); currently install just opens the Steam installer.

## Constraints / rules

- Universal tuning only in code, per-game in recipes (unchanged).
- steam.exe sessions must be shut down gracefully (`steam.exe -shutdown`),
  never `wineserver -k` first — hard kills corrupt client state (2026-07-26
  incident) and trigger binary self-heal that fights the webhelper wrapper.
- The steamwebhelper wrapper is auto-ensured by `bin/mage run` and by
  openInSteam (`bin/mage steam-wrapper <prefix>`); after a Steam client
  update it reinstalls itself on the next launch — no user action.
