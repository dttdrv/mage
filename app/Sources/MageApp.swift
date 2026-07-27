import AppKit
import SwiftUI
import WebKit

@main
struct MageApp: App {
    @StateObject private var store = MageStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    store.load()
                    Task { await Updater.shared.check(silent: true) }
                }
                .frame(minWidth: 1080, minHeight: 680)
        }
        .defaultSize(width: 1240, height: 820)
    }
}

// MARK: - Root

enum SidebarItem: String, Identifiable, CaseIterable {
    case library
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: MageStore
    @ObservedObject private var updater = Updater.shared
    @State private var sidebar: SidebarItem? = .library
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var showUpdatePrompt = false

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
                    .transition(.opacity)
            } else if store.root == nil {
                missingRoot
                    .transition(.opacity)
            } else {
                splitView
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: showOnboarding)
        .animation(.smooth(duration: 0.3), value: store.root == nil)
        .onAppear { showOnboarding = store.root == nil }
        .sheet(isPresented: $showSettings, onDismiss: { store.fetchOwnedGames() }) {
            SettingsView()
        }
        .sheet(isPresented: $showUpdatePrompt) {
            if let release = updater.pendingRelease {
                UpdatePromptSheet(release: release)
            }
        }
        .onChange(of: updater.pendingRelease != nil) { _, available in
            if available { showUpdatePrompt = true }
        }
    }

    /// Reached only when onboarding was skipped without a mage root — offers
    /// a way back into setup (no dead ends).
    private var missingRoot: some View {
        ContentUnavailableView {
            Label("Mage directory not found", systemImage: "questionmark.folder")
        } description: {
            Text("Point Mage at the directory containing bin/mage.")
        } actions: {
            Button("Run setup…") { showOnboarding = true }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
            Button("Locate mage directory…") { store.pickRoot() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Label("Library", systemImage: "gamecontroller.fill")
                    .tag(SidebarItem.library)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Settings")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } detail: {
            LibraryView()
        }
    }
}

// MARK: - Library (game grid)

struct LibraryView: View {
    @EnvironmentObject private var store: MageStore
    @State private var navPath = NavigationPath()
    @State private var showAddGame = false
    @State private var filter = LibraryFilter.all

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case installed = "Installed"
        case notInstalled = "Not installed"
        var id: String { rawValue }

        func includes(_ entry: LibraryEntry) -> Bool {
            switch self {
            case .all: return true
            case .installed: return !entry.ownedOnly
            case .notInstalled: return entry.ownedOnly
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20)]

    private var entries: [LibraryEntry] {
        store.library.filter(filter.includes)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                if store.library.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "gamecontroller")
                    } description: {
                        Text("Install a game with Steam and it shows up here.")
                    } actions: {
                        Button("Install game…") { showAddGame = true }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                } else if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No games here", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No games match the “\(filter.rawValue)” filter.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            NavigationLink(value: entry) {
                                GameCard(entry: entry,
                                         appearDelay: Double(min(index, 10)) * 0.045)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: LibraryEntry.self) { entry in
                GameDetailView(entry: entry)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .animation(.snappy(duration: 0.25), value: filter)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddGame = true } label: {
                        Label("Install game", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button { store.load() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showAddGame) { AddGameSheet() }
        }
    }
}

/// Card press feedback: quick shrink, springs back on release.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct GameCard: View {
    @EnvironmentObject private var store: MageStore
    let entry: LibraryEntry
    var appearDelay: Double = 0
    @State private var hovered = false
    @State private var appeared = false

    private var running: Bool {
        guard let bottle = entry.bottle else { return false }
        return store.runningBottles.contains(bottle.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                FileImage(url: store.artwork(for: entry).capsule, contentMode: .fill) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "gamecontroller")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(hovered ? 0.35 : 0.2),
                        radius: hovered ? 12 : 6, y: hovered ? 6 : 3)

                if running {
                    HStack(spacing: 5) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                            .symbolEffect(.pulse)
                        Text("Running")
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                if hovered {
                    Image(systemName: entry.isSetup ? "play.fill" : "arrow.down.circle.fill")
                        .font(.title2)
                        .padding(10)
                        .glassEffect(.regular, in: .circle)
                        .padding(8)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            Text(entry.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(entry.isSetup ? "Ready to play"
                 : entry.ownedOnly ? "Not installed" : "In Steam library")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .scaleEffect(hovered ? 1.03 : 1)
        .animation(.snappy(duration: 0.18), value: hovered)
        .onHover { hovered = $0 }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.smooth(duration: 0.35).delay(appearDelay)) {
                appeared = true
            }
        }
    }
}

// MARK: - Game detail

struct GameDetailView: View {
    @EnvironmentObject private var store: MageStore
    let entry: LibraryEntry
    @State private var showAdvanced = false
    @State private var showConsole = false
    @State private var appeared = false

    private var bottle: Bottle? { entry.bottle }

    var body: some View {
        let artwork = store.artwork(for: entry)
        let running = bottle.map { store.runningBottles.contains($0.name) } ?? false

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HeroHeader(
                        title: entry.title, artwork: artwork, running: running,
                        onPlay: bottle.map { b in { store.runCLI(["run", b.name]) } },
                        playDisabled: store.busy,
                        playBusy: store.busy
                    )
                    // Zoom-ish entrance: navigationTransition(.zoom) is iOS-only,
                    // so the hero scales in on push instead.
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
                    .onAppear { withAnimation(.smooth(duration: 0.3)) { appeared = true } }

                    HStack(spacing: 10) {
                        if let bottle {
                            Button("Advanced…") { showAdvanced = true }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)

                            Menu {
                                Button("Dry run") {
                                    store.runCLI(["run", bottle.name, "--dry-run"])
                                }
                                Button("Doctor…") { store.runCLI(["doctor", bottle.name]) }
                                Divider()
                                Button("Show launch log") { store.startLogTail(bottle.name) }
                                Button("Reveal prefix in Finder") {
                                    NSWorkspace.shared.selectFile(
                                        nil, inFileViewerRootedAtPath: entry.prefix.path)
                                }
                                if let appid = entry.appid {
                                    Divider()
                                    Button("Open in Steam") {
                                        store.openInSteam("steam://run/\(appid)",
                                                          prefix: entry.prefix)
                                    }
                                }
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .disabled(store.busy)
                        } else if entry.ownedOnly, let appid = entry.appid {
                            if store.installStates[appid] != nil {
                                HStack(spacing: 10) {
                                    if store.installStates[appid]?.active == true {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(store.installLabel(for: appid))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            } else {
                                Button { store.installGame(entry) } label: {
                                    Label("Install", systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.capsule)
                                .controlSize(.large)
                                .disabled(store.steamCapablePrefix == nil)
                            }
                        } else if let appid = entry.appid {
                            Button { store.setupWithMage(entry) } label: {
                                Label("Set up with Mage", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .disabled(store.busy)

                            Button {
                                store.openInSteam("steam://run/\(appid)", prefix: entry.prefix)
                            } label: {
                                Label("Play via Steam", systemImage: "play.fill")
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                        Spacer()
                    }

                    progressBlock

                    if let bottle {
                        let warnings = store.fileCheckWarnings(for: bottle)
                        if !warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                chip(store.wineVersion.isEmpty ? "mage-wine" : store.wineVersion,
                                     icon: "cpu")
                                if let bottle {
                                    chip(store.prefixSizes[bottle.name] ?? "…",
                                         icon: "internaldrive")
                                    if bottle.imported {
                                        chip("imported", icon: "square.and.arrow.down")
                                    }
                                }
                                if let appid = entry.appid {
                                    chip("AppID \(appid)", icon: "number")
                                }
                                Spacer()
                            }
                        }

                        Text(entry.prefix.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if showConsole || store.busy {
                        ConsoleView()
                            .frame(height: 240)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(20)
                .animation(.smooth(duration: 0.3), value: showConsole || store.busy)
            }

            Divider()

            HStack(spacing: 10) {
                if store.busy {
                    ProgressView().controlSize(.small)
                        .transition(.opacity)
                }
                Button { showConsole.toggle() } label: {
                    Label("Console", systemImage: showConsole ? "terminal.fill" : "terminal")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .foregroundStyle(showConsole ? Color.accentColor : .primary)
                .help("Show or hide the console")
                Text(store.statusLine)
                    .lineLimit(1)
                Spacer()
                Text(store.root?.path ?? "")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .animation(.smooth(duration: 0.3), value: store.busy)
        }
        .navigationTitle(entry.title)
        .sheet(isPresented: $showAdvanced) {
            if let bottle, let recipe = store.recipe(for: bottle) {
                AdvancedView(bottle: bottle, recipe: recipe)
            }
        }
    }

    private func chip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }

    /// Steam-style progress: playtime from the owned feed + achievement
    /// counts from the bridge. Hidden unless signed in with data (or loading).
    @ViewBuilder
    private var progressBlock: some View {
        if let appid = entry.appid, store.steamAuth.loggedIn {
            let minutes = store.playtimes[appid] ?? 0
            let achievements = store.achievementProgress[appid]
            let pending = achievements == nil && !store.achievementFailed.contains(appid)
            if minutes > 0 || (achievements?.total ?? 0) > 0 || pending {
                HStack(spacing: 18) {
                    if minutes > 0 {
                        Label(Self.formatPlaytime(minutes), systemImage: "clock")
                    }
                    if let achievements, achievements.total > 0 {
                        HStack(spacing: 8) {
                            Text("\(achievements.unlocked) of \(achievements.total) achievements")
                            ProgressView(value: Double(achievements.unlocked),
                                         total: Double(achievements.total))
                                .frame(width: 90)
                        }
                    } else if pending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Fetching achievements…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .transition(.opacity)
            }
        }
    }

    private static func formatPlaytime(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        return hours < 1
            ? "\(minutes) min played"
            : String(format: "%.1f hrs played", hours)
    }
}

struct HeroHeader: View {
    let title: String
    let artwork: Artwork
    let running: Bool
    var onPlay: (() -> Void)? = nil
    var playDisabled = false
    var playBusy = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FileImage(url: artwork.hero, contentMode: .fill) {
                LinearGradient(colors: [.indigo.opacity(0.55), .black.opacity(0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)

            HStack(alignment: .bottom) {
                if artwork.logo != nil {
                    FileImage(url: artwork.logo, contentMode: .fit) { Color.clear }
                        .frame(maxWidth: 300, maxHeight: 88, alignment: .bottomLeading)
                        .shadow(radius: 8)
                } else {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                }
                Spacer()
                if let onPlay {
                    Button(action: onPlay) {
                        if playBusy {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 52)
                        } else {
                            Label("Play", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .disabled(playDisabled)
                    .animation(.snappy(duration: 0.2), value: playBusy)
                }
            }
            .padding(18)
        }
        .overlay(alignment: .topTrailing) {
            if running {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse)
                    Text("Running")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
                .padding(14)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(.snappy(duration: 0.25), value: running)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Onboarding (first run, skippable, re-enterable via missing-root view)

struct OnboardingView: View {
    @EnvironmentObject private var store: MageStore
    @Binding var isPresented: Bool

    @State private var page = 0
    @State private var showAPIKey = false
    @State private var showSteamSignIn = false

    private let candidates = MageRoot.candidates()

    private var steamLinked: Bool {
        store.steamAuth.loggedIn || !store.steamAPIKey.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Group {
                switch page {
                case 0: welcome
                case 1: locate
                case 2: steam
                default: done
                }
            }
            .frame(maxWidth: 520)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            Spacer()
            bottomBar
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: page)
        .animation(.smooth(duration: 0.25), value: showAPIKey)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .padding(26)
                .glassEffect(.regular, in: .circle)
            Text("Welcome to Mage")
                .font(.largeTitle.bold())
            Text("Play your Windows games on this Mac.\nMage sets up Wine and graphics for you — let's get going.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var locate: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            Text("Find the Mage directory")
                .font(.title.bold())
            Text("Mage needs its tools directory — the one containing bin/mage.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(candidates, id: \.path) { url in
                    Button {
                        store.useRoot(url)
                        withAnimation { page = 2 }
                    } label: {
                        Label("Use detected: \(url.path)", systemImage: "checkmark.folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
                Button {
                    store.pickRoot()
                    if store.root != nil { withAnimation { page = 2 } }
                } label: {
                    Label("Choose folder…", systemImage: "folder")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
            .padding(.top, 6)

            if candidates.isEmpty {
                Text("No Mage directory detected automatically — pick it manually.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var steam: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            Text("Steam account")
                .font(.title.bold())
            Text("Optional — link Steam to show games you own but haven't installed yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if store.steamAuth.loggedIn {
                Label("Signed in as \(store.steamAuth.account)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if store.root == nil {
                Text("Steam linking needs the Mage directory — go back one step to set it up.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                HStack(spacing: 12) {
                    Button { showSteamSignIn = true } label: {
                        Label("Sign in with Steam", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)

                    Button {
                        withAnimation { showAPIKey.toggle() }
                    } label: {
                        Label("Use API key", systemImage: "key")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .foregroundStyle(showAPIKey ? Color.accentColor : .primary)
                }

                if showAPIKey {
                    VStack(spacing: 6) {
                        SecureField("Steam Web API key", text: $store.steamAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Text("Get a key at steamcommunity.com/dev/apikey — your profile must be public.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 320)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !store.steamAuthMessage.isEmpty {
                    Label(store.steamAuthMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .sheet(isPresented: $showSteamSignIn) { SteamSignInSheet() }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
            Text("You're all set")
                .font(.largeTitle.bold())
            VStack(spacing: 6) {
                if let root = store.root {
                    Label(root.path, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Label(steamLinked
                      ? (store.steamAuth.loggedIn
                         ? "Steam linked as \(store.steamAuth.account)" : "Steam API key saved")
                      : "Steam not linked — you can do it later in Settings",
                      systemImage: steamLinked ? "checkmark.circle" : "circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            } else {
                Button("Skip setup") { isPresented = false }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            switch page {
            case 0:
                Button("Continue") { withAnimation { page = 1 } }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
            case 1:
                Button(store.root == nil ? "Skip for now" : "Continue") {
                    withAnimation { page = 2 }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
            case 2:
                Button(steamLinked ? "Continue" : "Skip for now") {
                    withAnimation { page = 3 }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
            default:
                Button("Open library") { isPresented = false }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Sheets

struct SettingsView: View {
    @EnvironmentObject private var store: MageStore
    @ObservedObject private var updater = Updater.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showSteamSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2.bold())
                .padding([.top, .leading], 20)

            Form {
                Section("General") {
                    LabeledContent("Mage directory") {
                        HStack {
                            Text(store.root?.path ?? "—")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Change…") { store.pickRoot() }
                        }
                    }
                }

                Section("Steam account") {
                    if store.steamAuth.loggedIn {
                        LabeledContent("Signed in as", value: store.steamAuth.account)
                        Button("Sign out") { store.signOut() }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                    } else {
                        Button { showSteamSignIn = true } label: {
                            Label("Sign in with Steam", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        Text("Uses Steam's own sign-in page — your password and "
                             + "Steam Guard code never touch Mage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !store.steamAuthMessage.isEmpty {
                        Label(store.steamAuthMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    SecureField("Steam Web API key", text: $store.steamAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Read-only alternative to signing in, to show games you own. "
                         + "Get a key at steamcommunity.com/dev/apikey — "
                         + "your Steam profile must be public.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Maintenance") {
                    Button("Kill all Wine processes") { store.killAllWine() }
                    Text("Stops every wineserver owned by a Mage runtime. "
                         + "Use when games won't launch or Wine processes pile up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Reveal Mage directory in Finder") {
                        if let root = store.root {
                            NSWorkspace.shared.selectFile(
                                nil, inFileViewerRootedAtPath: root.path)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Mage", value: updater.currentVersion)
                    LabeledContent("Wine runtime",
                                   value: store.wineVersion.isEmpty ? "—" : store.wineVersion)
                    HStack {
                        Button(updater.checking ? "Checking…" : "Check for Updates") {
                            Task { await updater.check(silent: false) }
                        }
                        .disabled(updater.checking)
                        if !updater.statusLine.isEmpty {
                            Text(updater.statusLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text("Mage runs Windows games on Apple silicon using the "
                         + "Mage Wine fork and the Mage MoltenVK fork.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 560, height: 660)
        .sheet(isPresented: $showSteamSignIn) { SteamSignInSheet() }
    }
}

/// Shown when a newer GitHub release exists (launch check or Settings).
/// Update downloads, swaps /Applications/Mage.app and relaunches.
struct UpdatePromptSheet: View {
    @ObservedObject private var updater = Updater.shared
    @Environment(\.dismiss) private var dismiss
    let release: MageRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mage \(release.version) is available")
                        .font(.title2.bold())
                    Text("You have \(updater.currentVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12,
                                                              style: .continuous))
            }

            if let error = updater.installError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Later") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                    .disabled(updater.installing)
                Button {
                    Task { await updater.install(release) }
                } label: {
                    if updater.installing {
                        ProgressView().controlSize(.small)
                            .frame(minWidth: 52)
                    } else {
                        Text("Update")
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(updater.installing)
            }
        }
        .padding(24)
        .frame(width: 460, height: 380)
    }
}

struct AddGameSheet: View {
    @EnvironmentObject private var store: MageStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    private var appid: String? {
        if let match = input.range(of: #"\d{5,}"#, options: .regularExpression) {
            return String(input[match])
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install game")
                .font(.title2.bold())
            Text("Paste a Steam store URL or AppID. Steam opens its installer; the game appears in your library here once installed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://store.steampowered.com/app/3017860/…", text: $input)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                Button("Install in Steam") {
                    if let appid, let prefix = store.steamCapablePrefix {
                        store.openInSteam("steam://install/\(appid)", prefix: prefix)
                    }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(appid == nil || store.steamCapablePrefix == nil)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

// MARK: - Steam browser sign-in (Heroic-style: Valve's page, we read the cookie)

struct SteamSignInSheet: View {
    @EnvironmentObject private var store: MageStore
    @Environment(\.dismiss) private var dismiss
    @State private var captured = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Sign in with Steam")
                    .font(.title2.bold())
                Text("Sign in with your Steam account. Mage reads only the session cookie — your password never touches Mage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            ZStack {
                SteamWebView { steamid, token, cookie in
                    withAnimation { captured = true }
                    store.saveSteamSession(steamid: steamid, token: token, cookie: cookie)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if captured {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                        Text("Signed in — fetching your games…")
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520, height: 680)
    }
}

/// WKWebView wrapper that watches for Steam's steamLoginSecure cookie
/// (<steamID64>%7C%7C<JWT>), both on a 1s poll and after each navigation.
struct SteamWebView: NSViewRepresentable {
    let onCapture: (_ steamid: String, _ token: String, _ cookie: String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://steamcommunity.com/login/home/")!))
        context.coordinator.startPolling(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCapture: (String, String, String) -> Void
        private var captured = false
        private var timer: Timer?

        init(onCapture: @escaping (String, String, String) -> Void) {
            self.onCapture = onCapture
        }

        func startPolling(_ webView: WKWebView) {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak webView] _ in
                guard let webView else { return }
                Task { @MainActor in self?.checkCookies(webView) }
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkCookies(webView)
        }

        func checkCookies(_ webView: WKWebView) {
            guard !captured else { return }
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                for cookie in cookies
                where cookie.name == "steamLoginSecure"
                    && cookie.domain.contains("steamcommunity.com") {
                    guard let decoded = cookie.value.removingPercentEncoding,
                          let sep = decoded.range(of: "||") else { continue }
                    let steamid = String(decoded[..<sep.lowerBound])
                    let token = String(decoded[sep.upperBound...])
                    guard !steamid.isEmpty, !token.isEmpty else { continue }
                    Task { @MainActor [weak self] in
                        guard let self, !self.captured else { return }
                        self.captured = true
                        self.stop()
                        self.onCapture(steamid, token, cookie.value)
                    }
                    return
                }
            }
        }
    }
}

// MARK: - Console

struct ConsoleView: View {
    @EnvironmentObject private var store: MageStore

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Console")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { store.logText = "" }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Text(store.logText.isEmpty
                             ? "Console output appears here."
                             : store.logText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(store.logText.isEmpty ? 0.4 : 0.92))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        Spacer(minLength: 0).id("bottom")
                    }
                }
                .background(.black.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1))
                }
                .onChange(of: store.logText) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - File-backed image

struct FileImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: NSImage?

    init(url: URL?, contentMode: ContentMode = .fill,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await Self.load(url)
        }
    }

    /// Local files load directly; remote URLs (Steam CDN) are fetched async
    /// and cached on disk under ~/Library/Caches, keyed by appid + filename.
    private static func load(_ url: URL) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
        }
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mage/artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir,
                                                 withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent(
            url.path.split(separator: "/").suffix(2).joined(separator: "-"))
        if let cached = NSImage(contentsOf: cacheFile) { return cached }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let downloaded = NSImage(data: data) else { return nil }
        try? data.write(to: cacheFile)
        return downloaded
    }
}
