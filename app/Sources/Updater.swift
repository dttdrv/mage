import AppKit
import Foundation

/// One GitHub release, reduced to what the update UI needs.
struct MageRelease {
    let version: String
    let notes: String
    let zipURL: URL?
}

enum UpdateCheckOutcome {
    case updateAvailable(MageRelease)
    case upToDate
    case failed(String)
}

/// GitHub-releases update checker and applier. Silent checks happen on
/// launch; explicit checks (Settings button) report every outcome.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    @Published var checking = false
    @Published var pendingRelease: MageRelease?
    /// Feedback line for the Settings row (empty until an explicit check).
    @Published var statusLine = ""
    @Published var installing = false
    @Published var installError: String?

    private static let releasesURL =
        URL(string: "https://api.github.com/repos/dttdrv/mage/releases/latest")!

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Silent on failure when `silent` (launch path); sets `pendingRelease`
    /// when a newer version exists, which ContentView turns into a sheet.
    func check(silent: Bool) async {
        guard !checking, !installing else { return }
        checking = true
        defer { checking = false }
        if !silent { statusLine = "Checking…" }
        switch await Self.fetchLatest() {
        case .updateAvailable(let release):
            pendingRelease = release
            statusLine = "Mage \(release.version) is available"
        case .upToDate:
            if !silent { statusLine = "Mage \(currentVersion) is up to date" }
        case .failed(let message):
            if !silent { statusLine = message }
        }
    }

    /// Numeric component-wise compare; "1.10.0" > "1.9.9", missing = 0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated private static func fetchLatest() async -> UpdateCheckOutcome {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Mage", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String
        else { return .failed("Update check failed — no connection to GitHub") }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let current = await MainActor.run { shared.currentVersion }
        guard isNewer(version, than: current) else { return .upToDate }
        let notes = obj["body"] as? String ?? ""
        let zip = (obj["assets"] as? [[String: Any]] ?? [])
            .first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        return .updateAvailable(MageRelease(version: version, notes: notes, zipURL: zip))
    }

    // MARK: - Apply update

    /// Download, swap /Applications/Mage.app, relaunch. On any failure after
    /// the old app was trashed, restore it from the Trash so /Applications
    /// is never left without a Mage.app.
    func install(_ release: MageRelease) async {
        guard let zipURL = release.zipURL else {
            installError = "This release has no download — get it from github.com/dttdrv/mage/releases."
            return
        }
        installing = true
        installError = nil
        defer { installing = false }
        do {
            try await Self.downloadAndSwap(zipURL: zipURL)
            // Relaunched by downloadAndSwap; nothing left to do here.
        } catch {
            installError = error.localizedDescription
        }
    }

    nonisolated private static func downloadAndSwap(zipURL: URL) async throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("MageUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let zipFile = workDir.appendingPathComponent("Mage.zip")
        let (tmp, response) = try await URLSession.shared.download(from: zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.step("Download failed (server error)")
        }
        try fm.moveItem(at: tmp, to: zipFile)

        guard Self.run("/usr/bin/ditto", ["-x", "-k", zipFile.path, workDir.path]) == 0 else {
            throw UpdateError.step("Could not unpack the download")
        }
        let newApp = workDir.appendingPathComponent("Mage.app")
        guard fm.fileExists(atPath: newApp
            .appendingPathComponent("Contents/MacOS/Mage").path) else {
            throw UpdateError.step("The download did not contain Mage.app")
        }

        let installed = URL(fileURLWithPath: "/Applications/Mage.app")
        var trashed: URL?
        if fm.fileExists(atPath: installed.path) {
            var resulting: NSURL?
            try fm.trashItem(at: installed, resultingItemURL: &resulting)
            trashed = resulting as URL?
        }
        do {
            try fm.moveItem(at: newApp, to: installed)
        } catch {
            if let trashed { try? fm.moveItem(at: trashed, to: installed) }
            throw UpdateError.step("Could not place the new Mage.app in /Applications "
                                   + "(old version restored)")
        }
        _ = Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", installed.path])
        _ = Self.run("/usr/bin/open", ["-n", installed.path])
        await MainActor.run { NSApp.terminate(nil) }
    }

    @discardableResult
    nonisolated private static func run(_ path: String, _ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    enum UpdateError: LocalizedError {
        case step(String)
        var errorDescription: String? {
            switch self { case .step(let message): return message }
        }
    }
}
