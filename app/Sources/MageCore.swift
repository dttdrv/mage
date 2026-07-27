import AppKit
import Foundation
import WebKit

// MARK: - Data model (same declarative JSON the CLI uses; recipes are also
// written back by the Advanced editor — tuning lives in recipe data, per spec)

struct FileCheck: Codable, Hashable {
    var path: String
    var hint: String?
}

struct LaunchStep: Codable, Hashable {
    var program: String
    var args: [String]?
    var background: Bool?
    var thenWait: Int?

    enum CodingKeys: String, CodingKey {
        case program, args, background
        case thenWait = "then_wait"
    }
}

struct Recipe: Codable, Identifiable, Hashable {
    var id: String
    var title: String?
    var steamAppid: String?
    var runtime: String
    var env: [String: String]?
    var fileChecks: [FileCheck]?
    var launch: [LaunchStep]?

    enum CodingKeys: String, CodingKey {
        case id, title, runtime, env, launch
        case steamAppid = "steam_appid"
        case fileChecks = "file_checks"
    }
}

struct RuntimeManifest: Codable, Identifiable, Hashable {
    var id: String
    var root: String
    var wine: String
    var wineserver: String?
    var notes: String?
}

struct Bottle: Identifiable, Hashable {
    let name: String
    let recipe: String
    let prefix: URL
    let imported: Bool
    var id: String { name }
}

struct Artwork: Hashable {
    var capsule: URL?
    var hero: URL?
    var logo: URL?
    var header: URL?
}

/// A game installed in a bottle's Steam library (from steamapps/appmanifest_*.acf).
struct SteamGame: Identifiable, Hashable {
    let appid: String
    let name: String
    let installDir: String
    let prefix: URL
    let steamExeWin: String
    var id: String { appid }
}

/// One card in the library: a mage bottle, or a Steam-installed game that
/// has no bottle yet.
struct LibraryEntry: Identifiable, Hashable {
    let title: String
    let appid: String?
    let prefix: URL
    var bottle: Bottle?
    var steam: SteamGame?
    /// Owned on Steam but not installed anywhere (from the owned-games feed).
    var ownedOnly = false
    var id: String { bottle?.name ?? "steam-\(appid ?? title)" }
    var isSetup: Bool { bottle != nil }
}

// MARK: - Mage root resolution

enum MageRoot {
    static let overrideKey = "MageRootOverride"

    static func isValid(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(
            atPath: url.appendingPathComponent("bin/mage").path)
    }

    /// UserDefaults override → $MAGE_ROOT → bundle-relative (mage/app/.build/Mage.app).
    static func resolve() -> URL? {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: overrideKey) {
            let url = URL(fileURLWithPath: path)
            if isValid(url) { return url }
        }
        if let env = ProcessInfo.processInfo.environment["MAGE_ROOT"] {
            let url = URL(fileURLWithPath: env)
            if isValid(url) { return url }
        }
        let bundleRelative = Bundle.main.bundleURL
            .deletingLastPathComponent()  // .build
            .deletingLastPathComponent()  // app
            .deletingLastPathComponent()  // mage
        if isValid(bundleRelative) { return bundleRelative }
        return nil
    }

    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Locate the mage directory (the one containing bin/mage)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, isValid(url) else { return nil }
        UserDefaults.standard.set(url.path, forKey: overrideKey)
        return url
    }

    /// Ordered auto-detect candidates for first-run onboarding
    /// ($MAGE_ROOT → bundle-relative → ~/Projects/macgaming/mage), validated.
    static func candidates() -> [URL] {
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["MAGE_ROOT"] {
            urls.append(URL(fileURLWithPath: env))
        }
        urls.append(Bundle.main.bundleURL
            .deletingLastPathComponent()  // .build
            .deletingLastPathComponent()  // app
            .deletingLastPathComponent()) // mage
        urls.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/macgaming/mage"))
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted && isValid($0) }
    }
}

// MARK: - Store

@MainActor
final class MageStore: ObservableObject {
    @Published var root: URL?
    @Published var recipes: [Recipe] = []
    @Published var runtimes: [RuntimeManifest] = []
    @Published var bottles: [Bottle] = []
    @Published var library: [LibraryEntry] = []
    @Published var logText = ""
    @Published var busy = false
    @Published var statusLine = ""
    @Published var wineVersion = ""
    @Published var runningBottles: Set<String> = []
    @Published var prefixSizes: [String: String] = [:]

    // MARK: Steam account state

    struct SteamAuth: Equatable {
        var loggedIn = false
        var account = ""
        var steamID = ""
    }

    @Published var steamAuth = SteamAuth()
    @Published var steamAuthMessage = ""
    @Published var steamAPIKey: String {
        didSet { UserDefaults.standard.set(steamAPIKey, forKey: "SteamAPIKey") }
    }

    init() {
        _steamAPIKey = Published(
            initialValue: UserDefaults.standard.string(forKey: "SteamAPIKey") ?? "")
    }

    private var logTimer: Timer?
    private var runningTimer: Timer?

    /// The universal launch environment — the A/B-verified set, shared by all
    /// recipes (hard rule: universal only, tuning lives in recipe data).
    static let universalEnv: [String: String] = [
        "WINEMSYNC": "1",
        "WINEESYNC": "0",
        "WINEDEBUG": "-all",
        "WINEDLLOVERRIDES": "mscoree=d;mshtml=d",
        "ROSETTA_ADVERTISE_AVX": "1",
        "MTL_HUD_ENABLED": "1",
    ]

    func load() {
        if root == nil { root = MageRoot.resolve() }
        guard let root else { return }
        recipes = Self.loadJSONFiles(from: root.appendingPathComponent("recipes"))
        runtimes = Self.loadJSONFiles(from: root.appendingPathComponent("runtimes"))
        bottles = Self.loadBottles(root: root)
        library = buildLibrary()
        Task { await loadWineVersion() }
        for bottle in bottles { loadPrefixSize(for: bottle) }
        refreshRunning()
        Task {
            await refreshSteamAuth()
            fetchOwnedGames()
        }
        if runningTimer == nil {
            runningTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                Task { @MainActor in self.refreshRunning() }
            }
        }
    }

    func pickRoot() {
        if let url = MageRoot.pick() {
            root = url
            prefixSizes = [:]
            load()
        }
    }

    /// Adopt a detected mage root (onboarding), persisting it like pick() does.
    func useRoot(_ url: URL) {
        guard MageRoot.isValid(url) else { return }
        UserDefaults.standard.set(url.path, forKey: MageRoot.overrideKey)
        root = url
        prefixSizes = [:]
        load()
    }

    // MARK: Lookup helpers

    func recipe(for bottle: Bottle) -> Recipe? {
        recipes.first { $0.id == bottle.recipe }
    }

    func recipe(for entry: LibraryEntry) -> Recipe? {
        guard let bottle = entry.bottle else { return nil }
        return recipe(for: bottle)
    }

    var defaultRuntimeID: String {
        runtimes.first?.id ?? "mage-wine-11.13"
    }

    func runtimeManifest(_ id: String) -> RuntimeManifest? {
        runtimes.first { $0.id == id }
    }

    func runtimeWineURL(_ id: String) -> URL? {
        guard let root, let manifest = runtimeManifest(id) else { return nil }
        if manifest.root.hasPrefix("/") {
            return URL(fileURLWithPath: manifest.root).appendingPathComponent(manifest.wine)
        }
        return root.appendingPathComponent(manifest.root).standardizedFileURL
            .appendingPathComponent(manifest.wine)
    }

    /// Same policy as the CLI's file_checks: report what is missing, with hints.
    func fileCheckWarnings(for bottle: Bottle) -> [String] {
        guard let recipe = recipe(for: bottle) else { return [] }
        return (recipe.fileChecks ?? []).compactMap { check in
            FileManager.default.fileExists(atPath: bottle.prefix.appendingPathComponent(check.path).path)
                ? nil
                : "missing \(check.path) — \(check.hint ?? "")"
        }
    }

    func bottleLogURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mage-\(name).log")
    }

    // MARK: Artwork (Steam's local library cache inside the prefix)

    func artwork(appid: String?, prefix: URL) -> Artwork {
        guard let appid else { return Artwork() }
        let dir = prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/appcache/librarycache/\(appid)")
        func file(_ name: String) -> URL? {
            let url = dir.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return Artwork(capsule: file("library_600x900.jpg"),
                       hero: file("library_hero.jpg"),
                       logo: file("logo.png"),
                       header: file("header.jpg"))
    }

    func artwork(for entry: LibraryEntry) -> Artwork {
        // Owned-but-not-installed games have no prefix cache; use Steam's CDN.
        if entry.ownedOnly, let appid = entry.appid {
            let base = "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appid)"
            return Artwork(capsule: URL(string: "\(base)/library_600x900.jpg"),
                           hero: URL(string: "\(base)/library_hero.jpg"))
        }
        return artwork(appid: entry.appid, prefix: entry.prefix)
    }

    // MARK: Steam library scanning (ACF manifests)

    /// Installed Steam games inside a bottle prefix, if it has Steam.
    func steamGames(in prefix: URL) -> [SteamGame] {
        let steamDir = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let steamapps = steamDir.appendingPathComponent("steamapps")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: steamapps, includingPropertiesForKeys: nil)) ?? []
        let exe = "C:\\Program Files (x86)\\Steam\\steam.exe"
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") }
            .compactMap { Self.parseACF($0) }
            .filter { !Self.hiddenAppIDs.contains($0.appid) }
            .map { SteamGame(appid: $0.appid, name: $0.name, installDir: $0.dir,
                             prefix: prefix, steamExeWin: exe) }
            .sorted { $0.name < $1.name }
    }

    /// Steam redistributables that ship an appmanifest but are not games.
    private static let hiddenAppIDs: Set<String> = ["228980"] // Steamworks Common Redistributables

    /// Minimal KeyValues reader: first occurrence of each top-level pair.
    nonisolated static func parseACF(_ url: URL) -> (appid: String, name: String, dir: String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var appid: String?, name: String?, dir: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            // lines look like: \t"appid"\t\t"379720"
            guard parts.count >= 4 else { continue }
            let key = String(parts[1]), value = String(parts[3])
            switch key {
            case "appid" where appid == nil: appid = value
            case "name" where name == nil: name = value
            case "installdir" where dir == nil: dir = value
            default: break
            }
        }
        guard let appid, let name else { return nil }
        return (appid, name, dir ?? name)
    }

    private func buildLibrary() -> [LibraryEntry] {
        var claimedAppIDs = Set<String>()
        var entries: [LibraryEntry] = []
        for bottle in bottles {
            let appid = recipe(for: bottle)?.steamAppid
            if let appid { claimedAppIDs.insert(appid) }
            let steam = steamGames(in: bottle.prefix).first { $0.appid == appid }
            entries.append(LibraryEntry(
                title: recipe(for: bottle)?.title ?? bottle.name,
                appid: appid, prefix: bottle.prefix, bottle: bottle, steam: steam))
        }
        var seenPrefixes = Set<URL>()
        for bottle in bottles where seenPrefixes.insert(bottle.prefix).inserted {
            for game in steamGames(in: bottle.prefix) where !claimedAppIDs.contains(game.appid) {
                entries.append(LibraryEntry(title: game.name, appid: game.appid,
                                            prefix: game.prefix, bottle: nil, steam: game))
            }
        }
        return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Running-state detection (exe names from recipe launch steps)

    func refreshRunning() {
        let checks: [(String, [String])] = bottles.map { bottle in
            let exes = (recipe(for: bottle)?.launch ?? [])
                .map { ($0.program as NSString).lastPathComponent }
                .filter { !$0.isEmpty }
            return (bottle.name, exes)
        }
        Task.detached {
            var running = Set<String>()
            for (name, exes) in checks {
                for exe in exes where Self.pgrepRunning(exe) {
                    running.insert(name)
                    break
                }
            }
            await MainActor.run { self.runningBottles = running }
        }
    }

    nonisolated private static func pgrepRunning(_ exe: String) -> Bool {
        let escaped = exe.replacingOccurrences(of: ".", with: "\\.")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fi", escaped]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: Prefix size (background, cached)

    func loadPrefixSize(for bottle: Bottle) {
        guard prefixSizes[bottle.name] == nil else { return }
        prefixSizes[bottle.name] = "…"
        let path = bottle.prefix.path
        Task.detached {
            let (out, code) = await Self.exec(URL(fileURLWithPath: "/usr/bin/du"), ["-sk", path])
            guard code == 0,
                  let field = out.split(separator: "\t").first,
                  let kb = Double(field.trimmingCharacters(in: .whitespaces))
            else { return }
            let text = kb >= 1_048_576
                ? String(format: "%.1f GB", kb / 1_048_576)
                : String(format: "%.0f MB", kb / 1024)
            await MainActor.run { self.prefixSizes[bottle.name] = text }
        }
    }

    // MARK: CLI actions (launches/install/doctor go through bin/mage)

    func runCLI(_ args: [String], thenReload: Bool = false) {
        guard let root, !busy else { return }
        stopLogTail()
        busy = true
        statusLine = "mage \(args.joined(separator: " "))"
        logText = "$ mage \(args.joined(separator: " "))\n"
        let cli = root.appendingPathComponent("bin/mage")
        Task {
            let (_, code) = await Self.exec(cli, args) { [weak self] chunk in
                Task { @MainActor in
                    guard let self else { return }
                    self.logText += chunk
                    if self.logText.count > 300_000 {
                        self.logText = String(self.logText.suffix(200_000))
                    }
                }
            }
            busy = false
            statusLine = code == 0 ? "done (exit 0)" : "failed (exit \(code))"
            if thenReload { load() }
            refreshRunning()
        }
    }

    func install(recipe: String, name: String?, importPrefix: URL?) {
        var args = ["install", recipe]
        if let name, !name.isEmpty { args += ["--name", name] }
        if let importPrefix { args += ["--import-prefix", importPrefix.path] }
        runCLI(args, thenReload: true)
    }

    /// Kill every wineserver we know about (one per runtime). This is the
    /// only reliable way to reap a whole Wine session — pkill misses
    /// service processes whose command lines don't contain "wine".
    func killAllWine() {
        guard let root else { return }
        statusLine = "Stopping all Wine sessions…"
        let servers: [URL] = runtimes.map { rt in
            let rtRoot = rt.root.hasPrefix("/")
                ? URL(fileURLWithPath: rt.root)
                : root.appendingPathComponent(rt.root)
            let rel = rt.wineserver
                ?? (rt.wine as NSString).deletingLastPathComponent + "/wineserver"
            return rtRoot.appendingPathComponent(rel)
        }
        Task {
            for server in servers where FileManager.default.fileExists(atPath: server.path) {
                _ = await Self.exec(server, ["-k"]) { _ in }
            }
            Task { @MainActor in
                self.statusLine = "All Wine sessions stopped"
                self.refreshRunning()
            }
        }
    }

    // MARK: Env switches (known settings shown as toggles, not key=value rows)

    /// A well-known env var surfaced as a toggle. When off the key is
    /// removed from the recipe (runtime default applies).
    struct EnvSwitch: Identifiable {
        let id: String      // env key
        let title: String
        let hint: String
        let onValue: String // value written while enabled
    }

    static let envSwitches: [EnvSwitch] = [
        EnvSwitch(id: "MTL_HUD_ENABLED", title: "Metal HUD",
                  hint: "FPS and frame-time overlay in game", onValue: "1"),
        EnvSwitch(id: "WINEMSYNC", title: "msync",
                  hint: "Faster sync in the Wine runtime; a few games misbehave with it on",
                  onValue: "1"),
        EnvSwitch(id: "ROSETTA_ADVERTISE_AVX", title: "Advertise AVX",
                  hint: "Expose AVX/AVX2 to games; translated, so per-game win varies",
                  onValue: "1"),
        EnvSwitch(id: "WINEDEBUG", title: "Silence Wine logging",
                  hint: "Sets WINEDEBUG=-all", onValue: "-all"),
    ]

    /// Framerate cap: presentation throttle implemented in the vendored
    /// MoltenVK branch. Value is an FPS integer as string; absent = uncapped.
    static let frameRateCapKey = "MVK_CONFIG_FRAME_RATE_CAP"
    static let frameRateCapOptions = [0, 30, 60, 90, 120, 144] // 0 = uncapped

    /// Flip one env key in a bottle's recipe and save immediately.
    func setEnv(_ key: String, value: String?, for bottle: Bottle) {
        guard var recipe = recipe(for: bottle) else { return }
        var env = recipe.env ?? [:]
        env[key] = value
        recipe.env = env.isEmpty ? nil : env
        saveRecipe(recipe)
    }

    // MARK: Recipe authoring (Advanced editor, Set up with Mage)

    func saveRecipe(_ recipe: Recipe) {
        guard let root else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(recipe) else {
            statusLine = "failed to encode recipe"
            return
        }
        do {
            try data.write(to: root.appendingPathComponent("recipes/\(recipe.id).json"))
            load()
            statusLine = "recipe \(recipe.id) saved"
        } catch {
            statusLine = "save failed: \(error.localizedDescription)"
        }
    }

    /// Point an imported bottle at a different prefix (rewrites imported.json).
    func setBottlePrefix(_ bottle: Bottle, to newPrefix: URL) {
        guard let root, bottle.imported else { return }
        struct Entry: Codable { var name, recipe, prefix: String }
        let regURL = root.appendingPathComponent("prefixes/imported.json")
        guard var entries: [Entry] = Self.loadJSON(regURL) else { return }
        for i in entries.indices where entries[i].name == bottle.name {
            entries[i].prefix = newPrefix.path
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: regURL)
        prefixSizes[bottle.name] = nil
        load()
    }

    /// Create a recipe for a Steam-installed game and register its bottle.
    func setupWithMage(_ entry: LibraryEntry) {
        guard let appid = entry.appid, let steam = entry.steam else { return }
        let id = entry.title.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let recipe = Recipe(
            id: id,
            title: entry.title,
            steamAppid: appid,
            runtime: defaultRuntimeID,
            env: Self.universalEnv,
            fileChecks: nil,
            launch: [
                LaunchStep(program: steam.steamExeWin, args: [],
                           background: true, thenWait: 20),
                LaunchStep(program: steam.steamExeWin,
                           args: ["-applaunch", appid],
                           background: true, thenWait: nil),
            ])
        saveRecipe(recipe)
        install(recipe: id, name: nil, importPrefix: entry.prefix)
    }

    // MARK: Steam actions (install/run URLs inside the bottle's Steam)

    /// First prefix that actually has a Steam installation.
    var steamCapablePrefix: URL? {
        bottles.map(\.prefix).first {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent(
                    "drive_c/Program Files (x86)/Steam/steam.exe").path)
        }
    }

    /// Fire a steam:// URL (install, run) through the bottle's Steam client.
    /// Fire-and-forget: forwards to the running client or starts it.
    func openInSteam(_ urlString: String, prefix: URL) {
        guard let wine = runtimeWineURL(defaultRuntimeID) else {
            statusLine = "no runtime available"
            return
        }
        stopLogTail()
        logText = "→ \(urlString) via Steam\n"
        statusLine = urlString
        var env: [String: String] = [:]
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        env["WINEDLLOVERRIDES"] = "mscoree=d;mshtml=d"
        env["DYLD_FALLBACK_LIBRARY_PATH"] = wine.deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("lib").path
        Task {
            // self-heal the single-process steamwebhelper wrapper first —
            // without it the Steam UI renders black (Steam updates restore
            // Valve's binary; this reinstalls + relocks as needed)
            if let root {
                _ = await Self.exec(root.appendingPathComponent("bin/mage"),
                                    ["steam-wrapper", prefix.path])
            }
            await Self.exec(wine,
                            ["C:\\Program Files (x86)\\Steam\\steam.exe", urlString],
                            env: env) { [weak self] chunk in
                Task { @MainActor in self?.logText += chunk }
            }
        }
    }

    // MARK: Steam account + owned games (stdlib Python bridge in tools/steam-bridge)

    /// Run bridge.py with the system python and parse the single JSON object
    /// it prints (log noise on other lines is ignored). Never throws.
    nonisolated private static func runBridge(
        root: URL, _ args: [String], env: [String: String] = [:]
    ) async -> [String: Any] {
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let script = root.appendingPathComponent("tools/steam-bridge/bridge.py")
        let (out, code) = await exec(python, [script.path] + args, env: env)
        for line in out.split(separator: "\n").reversed() {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return ["status": "error", "message": "steam bridge failed (exit \(code))"]
    }

    /// Offline: reads the bridge's stored session, no network.
    func refreshSteamAuth() async {
        guard let root else { return }
        let obj = await Self.runBridge(root: root, ["status"])
        if (obj["status"] as? String) == "ok" {
            steamAuth = SteamAuth(loggedIn: obj["logged_in"] as? Bool ?? false,
                                  account: obj["account"] as? String ?? "",
                                  steamID: obj["steam_id"] as? String ?? "")
        }
    }

    /// Persist a browser-captured Steam session (steamLoginSecure cookie:
    /// steamid + JWT access token) where bridge.py reads it, then revalidate.
    /// The raw cookie value is kept for future community endpoints.
    func saveSteamSession(steamid: String, token: String, cookie: String) {
        guard let root else { return }
        let dir = root.appendingPathComponent("tools/steam-bridge/auth")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("steam-session.json")
        let session: [String: Any] = ["steamid": steamid, "token": token, "cookie": cookie,
                                      "saved_at": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: session) {
            try? data.write(to: file)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: file.path)
        }
        Task {
            await refreshSteamAuth()
            fetchOwnedGames(refresh: true)
        }
    }

    func signOut() {
        guard let root else { return }
        Task {
            _ = await Self.runBridge(root: root, ["logout"])
            steamAuth = SteamAuth()
            steamAuthMessage = ""
            library.removeAll { $0.ownedOnly }
        }
        // Also drop Steam's web cookies, or the sign-in sheet would instantly
        // re-capture the still-logged-in web session.
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            for cookie in cookies
            where cookie.domain.contains("steamcommunity.com")
                || cookie.domain.contains("steampowered.com") {
                cookieStore.delete(cookie)
            }
        }
    }

    /// Merge owned games into the library. Bridge login takes priority; the
    /// Web API key is the read-only fallback. Needs a Steam-capable prefix to
    /// attach the entries to (install target + steamID64 source).
    func fetchOwnedGames(refresh: Bool = false) {
        guard let root, steamCapablePrefix != nil else { return }
        if steamAuth.loggedIn {
            Task {
                let obj = await Self.runBridge(root: root,
                                               refresh ? ["owned", "--refresh"] : ["owned"])
                switch obj["status"] as? String ?? "error" {
                case "ok":
                    mergeOwned(Self.parseBridgeGames(obj["games"]))
                case "need_login":
                    steamAuth = SteamAuth()
                    steamAuthMessage = "Steam session expired — sign in again, or use an API key."
                default:
                    statusLine = obj["message"] as? String ?? "steam library fetch failed"
                }
            }
        } else if !steamAPIKey.isEmpty {
            Task { await fetchOwnedGamesViaWebAPI() }
        }
    }

    nonisolated private static func parseBridgeGames(_ raw: Any?) -> [(appid: String, name: String, playtime: Int)] {
        (raw as? [[String: Any]] ?? []).compactMap { game in
            guard let appid = game["appid"] as? String,
                  let name = game["name"] as? String else { return nil }
            return (appid, name, game["playtime_forever"] as? Int ?? 0)
        }
    }

    // MARK: Game progress (playtime from the owned feed, achievements lazily)

    /// appid → minutes played, from the owned-games feed (both auth paths).
    @Published var playtimes: [String: Int] = [:]

    struct AchievementProgress: Equatable {
        var unlocked: Int
        var total: Int
        var percentage: Double
    }

    @Published private(set) var achievementProgress: [String: AchievementProgress] = [:]
    @Published private(set) var achievementFailed: Set<String> = []
    private var achievementInFlight: Set<String> = []

    /// Lazily load achievement counts for one app via the bridge; cached per
    /// appid so re-opening a detail page is instant. Failures stay hidden.
    func fetchAchievementProgress(appid: String) {
        guard let root, steamAuth.loggedIn,
              achievementProgress[appid] == nil,
              !achievementFailed.contains(appid),
              !achievementInFlight.contains(appid) else { return }
        achievementInFlight.insert(appid)
        Task {
            let obj = await Self.runBridge(root: root, ["progress", appid])
            achievementInFlight.remove(appid)
            if (obj["status"] as? String) == "ok",
               let unlocked = obj["unlocked"] as? Int,
               let total = obj["total"] as? Int {
                achievementProgress[appid] = AchievementProgress(
                    unlocked: unlocked, total: total,
                    percentage: obj["percentage"] as? Double ?? 0)
            } else {
                achievementFailed.insert(appid)
            }
        }
    }

    /// steamID64 of the most-recent Steam user in a prefix's loginusers.vdf.
    nonisolated static func steamID64(in prefix: URL) -> String? {
        let url = prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/config/loginusers.vdf")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var currentID: String?, recentID: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let first = String(parts[1])
            if parts.count >= 4 {
                if first == "MostRecent", parts[3] == "1" { recentID = currentID }
            } else if first.count >= 16, first.allSatisfy(\.isNumber) {
                currentID = first
            }
        }
        return recentID
    }

    private func fetchOwnedGamesViaWebAPI() async {
        guard let prefix = steamCapablePrefix,
              let steamID = Self.steamID64(in: prefix) else {
            steamAuthMessage = "No Steam user found in the prefix — sign in to Steam once, or use account sign-in above."
            return
        }
        var comps = URLComponents(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/")
        comps?.queryItems = [URLQueryItem(name: "key", value: steamAPIKey),
                             URLQueryItem(name: "steamid", value: steamID),
                             URLQueryItem(name: "include_appinfo", value: "1"),
                             URLQueryItem(name: "include_played_free_games", value: "1"),
                             URLQueryItem(name: "format", value: "json")]
        guard let url = comps?.url else { return }
        struct Response: Decodable {
            struct Body: Decodable {
                struct Game: Decodable { let appid: Int; let name: String?; let playtime_forever: Int? }
                let games: [Game]?
            }
            let response: Body
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let games = (decoded.response.games ?? []).compactMap { game in
                game.name.map { (String(game.appid), $0, game.playtime_forever ?? 0) }
            }
            if games.isEmpty {
                steamAuthMessage = "No games returned — is the Steam profile public and the API key valid?"
            }
            mergeOwned(games)
        } catch {
            statusLine = "Steam Web API fetch failed"
        }
    }

    /// Merge owned games into the grid as "Not installed" entries, deduped
    /// against bottles and Steam-installed games by appid. Playtimes feed the
    /// detail-page progress block for every entry with a matching appid.
    private func mergeOwned(_ games: [(appid: String, name: String, playtime: Int)]) {
        guard let prefix = steamCapablePrefix else { return }
        for game in games { playtimes[game.appid] = game.playtime }
        let claimed = Set(library.compactMap { $0.ownedOnly ? nil : $0.appid })
        library.removeAll { $0.ownedOnly }
        for game in games where !claimed.contains(game.appid) {
            library.append(LibraryEntry(title: game.name, appid: game.appid,
                                        prefix: prefix, ownedOnly: true))
        }
        library.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Headless Steam install (bin/mage steam-install)

    /// Per-app install progress, fed by the CLI's JSON progress lines.
    struct InstallState: Equatable {
        var bytesDownloaded: Int64 = 0
        var stateFlags: Int?
        var active = true
        var message: String?
    }

    @Published var installStates: [String: InstallState] = [:] // keyed by appid

    /// Line accumulator for parsing streamed JSON across chunk boundaries.
    private actor LineBuffer {
        private var text = ""
        func append(_ chunk: String) -> [String] {
            text += chunk
            var lines: [String] = []
            while let nl = text.firstIndex(of: "\n") {
                lines.append(String(text[text.startIndex..<nl]))
                text = String(text[text.index(after: nl)...])
            }
            return lines
        }
    }

    /// Install an owned game without opening a Steam window. The CLI keeps a
    /// -silent client in the bottle's prefix and forwards +app_install.
    func installGame(_ entry: LibraryEntry) {
        guard let root, let appid = entry.appid,
              installStates[appid] == nil,
              let bottle = bottles.first(where: { $0.prefix == entry.prefix })
        else { return }
        installStates[appid] = InstallState()
        statusLine = "Installing \(entry.title)…"
        let cli = root.appendingPathComponent("bin/mage")
        let buffer = LineBuffer()
        Task {
            let (_, code) = await Self.exec(
                cli, ["steam-install", bottle.name, appid]) { chunk in
                    Task {
                        for line in await buffer.append(chunk) {
                            await self.applyInstallLine(line, appid: appid)
                        }
                    }
                }
            if code == 0 {
                installStates.removeValue(forKey: appid)
                statusLine = "\(entry.title) installed"
                load()
            } else {
                var state = installStates[appid] ?? InstallState()
                state.active = false
                state.message = code == 2
                    ? "Still downloading in Steam — it finishes in the background."
                    : "Install failed (exit \(code)) — see the Steam client for details."
                installStates[appid] = state
                statusLine = state.message ?? ""
            }
        }
    }

    private func applyInstallLine(_ line: String, appid: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        var state = installStates[appid] ?? InstallState()
        state.bytesDownloaded = obj["bytes_downloaded"] as? Int64 ?? state.bytesDownloaded
        state.stateFlags = obj["state_flags"] as? Int ?? state.stateFlags
        installStates[appid] = state
    }

    /// Short progress line for the detail page ("Downloading 3.4 GB…").
    func installLabel(for appid: String) -> String {
        guard let state = installStates[appid] else { return "" }
        if !state.active, let message = state.message { return message }
        if state.bytesDownloaded > 0 {
            let gb = Double(state.bytesDownloaded) / 1_073_741_824
            return gb >= 1
                ? String(format: "Downloading %.1f GB…", gb)
                : String(format: "Downloading %.0f MB…", gb * 1024)
        }
        return state.stateFlags == nil ? "Preparing install…" : "Installing…"
    }

    // MARK: Bottle log tail

    func startLogTail(_ name: String) {
        stopLogTail()
        let url = bottleLogURL(name)
        let refresh = {
            guard let data = try? Data(contentsOf: url) else {
                self.logText = "(no log yet at \(url.path))"
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            self.logText = String(text.suffix(200_000))
        }
        refresh()
        logTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in refresh() }
        }
    }

    func stopLogTail() {
        logTimer?.invalidate()
        logTimer = nil
    }

    // MARK: Internals

    private func loadWineVersion() async {
        guard let wine = runtimeWineURL(defaultRuntimeID) else { return }
        let (out, code) = await Self.exec(wine, ["--version"])
        wineVersion = code == 0 ? out.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private static func loadJSON<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func loadJSONFiles<T: Decodable>(from dir: URL) -> [T] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(loadJSON)
    }

    private static func loadBottles(root: URL) -> [Bottle] {
        struct Marker: Decodable { let name, recipe, prefix: String }
        var result: [Bottle] = []
        let prefixesDir = root.appendingPathComponent("prefixes")
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: prefixesDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for dir in dirs where dir.hasDirectoryPath {
            let marker = dir.appendingPathComponent(".mage-bottle.json")
            if let m: Marker = loadJSON(marker) {
                result.append(Bottle(name: m.name, recipe: m.recipe,
                                     prefix: URL(fileURLWithPath: m.prefix), imported: false))
            }
        }
        if let imported: [Marker] = loadJSON(prefixesDir.appendingPathComponent("imported.json")) {
            result += imported.map {
                Bottle(name: $0.name, recipe: $0.recipe,
                       prefix: URL(fileURLWithPath: $0.prefix), imported: true)
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Async process exec with merged stdout/stderr capture and optional live
    /// chunk streaming. Never throws.
    nonisolated private static func exec(
        _ executable: URL,
        _ args: [String],
        env: [String: String]? = nil,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async -> (String, Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let collected = NSMutableData()
            let lock = NSLock()
            process.executableURL = executable
            process.arguments = args
            if let env {
                var merged = ProcessInfo.processInfo.environment
                merged.merge(env) { _, new in new }
                process.environment = merged
            }
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                lock.lock()
                if collected.length < 1_048_576 { collected.append(chunk) }
                lock.unlock()
                onChunk?(String(decoding: chunk, as: UTF8.self))
            }
            process.terminationHandler = { proc in
                lock.lock()
                collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
                lock.unlock()
                continuation.resume(returning: (
                    String(decoding: collected as Data, as: UTF8.self),
                    proc.terminationStatus))
            }
            do {
                try process.run()
                try pipe.fileHandleForWriting.close()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: ("mage: \(error.localizedDescription)\n", 1))
            }
        }
    }
}
