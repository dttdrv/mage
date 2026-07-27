/*
 * mage steamwebhelper wrapper — fix black Steam UI on Wine/macOS.
 *
 * SteamUI forces chromium's chrome-runtime, which always composites in a
 * separate gpu-process; presenting one process's frame into another
 * process's window is unimplemented in mainline Wine (root cause:
 * mage/docs/research/cef-crossprocess-present.md). Forcing CEF into
 * --single-process removes the cross-process present entirely.
 *
 * Install: rename Valve's steamwebhelper.exe to steamwebhelper_real.exe in
 * the same directory, drop this binary in as steamwebhelper.exe.
 * Concept proven by github.com/ramiabih/play-windows-steam-on-mac (same
 * flags); this is an independent minimal implementation.
 *
 * Build: x86_64-w64-mingw32-clang -O2 -mwindows -municode -o steamwebhelper.exe steamwebhelper-wrapper.c
 * (-mwindows so Wine does not open a stray console window for the wrapper;
 *  wWinMain below just forwards to wmain.)
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

/* Appended after Steam's own args so they override --valve-enable-site-isolation. */
#define EXTRA_FLAGS \
    L"--disable-gpu --single-process " \
    L"--disable-features=IsolateOrigins,site-per-process,SpareRendererForSitePerProcess"
#define REAL_BINARY L"steamwebhelper_real.exe"

/* Embedded marker so mage (and this wrapper itself) can tell wrapper builds
 * apart from Valve's binary. NEVER back up a file containing this marker as
 * steamwebhelper_real.exe — that creates a fork loop (wrapper execs wrapper,
 * each generation appending EXTRA_FLAGS; incident 2026-07-28). */
#define MARKER "MAGE-STEAMWEBHELPER-WRAPPER-v1"
static volatile const char marker[] = MARKER;

/* True if the file at path contains MARKER (i.e. it is a wrapper build). */
static int file_is_wrapper(const wchar_t *path)
{
    FILE *f = _wfopen(path, L"rb");
    if (!f) return 0;
    static char buf[1 << 20];
    size_t n, off = 0;
    const size_t mlen = sizeof(MARKER) - 1;
    int found = 0;
    char carry[sizeof(MARKER)] = {0};
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) {
        /* scan carry+buf for MARKER */
        size_t total = mlen + n;
        char *hay = malloc(total);
        if (!hay) break;
        memcpy(hay, carry, mlen);
        memcpy(hay + mlen, buf, n);
        for (size_t i = 0; i + mlen <= total; i++) {
            if (memcmp(hay + i, MARKER, mlen) == 0) { found = 1; break; }
        }
        memcpy(carry, hay + total - mlen, mlen);
        free(hay);
        if (found) break;
        off += n;
    }
    fclose(f);
    (void)off;
    return found;
}

int wmain(void)
{
    if (marker[0] != 'M') return 3;  /* keep the marker referenced in the binary */

    wchar_t self[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return 1;
    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) return 1;
    slash[1] = L'\0';

    const wchar_t *tail = GetCommandLineW();
    int in_quotes = 0;
    while (*tail) {
        if (*tail == L'"') in_quotes = !in_quotes;
        else if (*tail == L' ' && !in_quotes) break;
        ++tail;
    }
    while (*tail == L' ') ++tail;

    wchar_t real[MAX_PATH];
    _snwprintf(real, MAX_PATH, L"%ls%ls", self, REAL_BINARY);

    /* Refuse to exec a wrapper as the "real" binary — that is the fork
     * loop described above. Exit loudly instead of multiplying. */
    if (file_is_wrapper(real)) {
        fwprintf(stderr, L"mage wrapper: %ls is itself a wrapper build — "
                 L"refusing to exec (restore Valve's steamwebhelper_real.exe)\n", real);
        return 2;
    }

    size_t cap = wcslen(real) + wcslen(EXTRA_FLAGS) + wcslen(tail) + 8;
    wchar_t *cmdline = calloc(cap, sizeof(wchar_t));
    if (!cmdline) return 1;
    _snwprintf(cmdline, cap, L"\"%ls\" %ls %ls", real, tail, EXTRA_FLAGS);

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));
    if (!CreateProcessW(NULL, cmdline, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        free(cmdline);
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    free(cmdline);
    return (int)code;
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, LPWSTR lpCmd, int nShow)
{
    (void)hInst; (void)hPrev; (void)lpCmd; (void)nShow;
    return wmain();
}
