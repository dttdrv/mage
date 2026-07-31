import AppKit
import SwiftUI

/// Advanced per-game editor. Writes recipe JSON (tuning lives in recipe
/// data — the GUI only authors that data, never logic).
struct AdvancedView: View {
    @EnvironmentObject private var store: MageStore
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle
    let appid: String?
    @State private var recipe: Recipe
    @State private var prefixPath: String
    @State private var switchStates: [String: Bool] = [:]
    @State private var frameCap: Int = 0
    @State private var envRows: [EnvRow] = []
    @State private var steps: [StepRow] = []

    struct EnvRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    /// LaunchStep wrapped with a stable identity so reorder/delete doesn't
    /// desync TextField state (index-based ForEach does).
    struct StepRow: Identifiable {
        let id = UUID()
        var step: LaunchStep
    }

    init(bottle: Bottle, recipe: Recipe, appid: String? = nil) {
        self.bottle = bottle
        self.appid = appid
        _recipe = State(initialValue: recipe)
        _prefixPath = State(initialValue: bottle.prefix.path)
        var knownKeys = Set(MageStore.envSwitches.map(\.id))
        knownKeys.insert(MageStore.frameRateCapKey)
        _switchStates = State(initialValue: Dictionary(
            uniqueKeysWithValues: MageStore.envSwitches.map {
                ($0.id, recipe.env?[$0.id] == $0.onValue)
            }))
        _frameCap = State(initialValue:
            recipe.env?[MageStore.frameRateCapKey].flatMap(Int.init) ?? 0)
        _envRows = State(initialValue: (recipe.env ?? [:])
            .filter { !knownKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { EnvRow(key: $0.key, value: $0.value) })
        _steps = State(initialValue: (recipe.launch ?? []).map { StepRow(step: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Advanced — \(recipe.title ?? recipe.id)")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    general
                    features
                    environment
                    launch
                    tools
                    console
                }
                .padding(.vertical, 4)
            }

            HStack {
                Text("Saved to recipes/\(recipe.id).json")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
                    .disabled(recipe.id.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("General", icon: "gearshape")

            LabeledContent("Title") {
                TextField("Title", text: Binding(
                    get: { recipe.title ?? "" },
                    set: { recipe.title = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            }

            if let appid {
                LabeledContent("Steam AppID") {
                    Text(appid)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            LabeledContent("Runtime") {
                Picker("Runtime", selection: $recipe.runtime) {
                    ForEach(store.runtimes) { runtime in
                        Text(runtime.displayName).tag(runtime.id)
                    }
                }
                .labelsHidden()
            }

            LabeledContent("MoltenVK") {
                Picker("MoltenVK", selection: Binding(
                    get: { recipe.vulkanLibraryPath ?? "" },
                    set: { recipe.vulkanLibraryPath = $0.isEmpty ? nil : $0 })) {
                    Text("Runtime default").tag("")
                    ForEach(store.moltenVKBuilds, id: \.path) { build in
                        Text(build.name).tag(build.path)
                    }
                }
                .labelsHidden()
            }

            LabeledContent("Wine prefix") {
                HStack {
                    Text(prefixPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            prefixPath = url.path
                        }
                    }
                    .disabled(!bottle.imported)
                }
            }
            if !bottle.imported {
                Text("Prefix change is available for imported bottles; mage-managed bottles live in mage/prefixes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Features (known settings as toggles)

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Features", icon: "switch.2")
            ForEach(MageStore.envSwitches) { sw in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sw.title)
                        Text(sw.hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { switchStates[sw.id] ?? false },
                        set: { switchStates[sw.id] = $0 }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Framerate cap")
                    Text("Throttles presentation to this rate (MVK_CONFIG_FRAME_RATE_CAP)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $frameCap) {
                    Text("Off").tag(0)
                    ForEach(MageStore.frameRateCapOptions.filter { $0 > 0 }, id: \.self) { fps in
                        Text("\(fps) FPS").tag(fps)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: Environment

    private var environment: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Other variables", icon: "terminal")
                Spacer()
                Button { envRows.append(EnvRow(key: "", value: "")) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }

            Text("Raw key=value pairs for anything not covered above.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if envRows.isEmpty {
                Text("None.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($envRows) { $row in
                    HStack(spacing: 8) {
                        TextField("NAME", text: $row.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                        Text("=")
                            .foregroundStyle(.secondary)
                        TextField("value", text: $row.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                        Button { envRows.removeAll { $0.id == row.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Launch steps

    private var launch: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Launch steps", icon: "list.number")
                Spacer()
                Button { steps.append(StepRow(step: LaunchStep(program: "", args: nil, background: true, thenWait: nil))) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }

            if steps.isEmpty {
                Text("No launch steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($steps) { $row in
                    stepRow($row)
                }
            }
        }
    }

    private func stepRow(_ row: Binding<StepRow>) -> some View {
        let index = steps.firstIndex(where: { $0.id == row.id }) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(index + 1).")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Program (e.g. C:\\…\\steam.exe)", text: row.step.program)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                Button { moveStep(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).disabled(index == 0)
                Button { moveStep(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).disabled(index == steps.count - 1)
                Button { steps.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("Arguments (space-separated)", text: Binding(
                    get: { (row.step.wrappedValue.args ?? []).joined(separator: " ") },
                    set: { row.step.wrappedValue.args = $0.isEmpty ? nil : $0.split(separator: " ").map(String.init) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.leading, 26)
                Toggle("Background", isOn: Binding(
                    get: { row.step.wrappedValue.background ?? true },
                    set: { row.step.wrappedValue.background = $0 }))
                .toggleStyle(.checkbox)
                Text("then wait")
                    .foregroundStyle(.secondary)
                TextField("0", text: Binding(
                    get: { row.step.wrappedValue.thenWait.map(String.init) ?? "" },
                    set: { row.step.wrappedValue.thenWait = Int($0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                Text("s")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func moveStep(_ index: Int, by delta: Int) {
        let target = index + delta
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }

    // MARK: Tools (formerly the detail page's More menu)

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tools", icon: "wrench.and.screwdriver")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Dry run") { store.runCLI(["run", bottle.name, "--dry-run"]) }
                    Button("Doctor…") { store.runCLI(["doctor", bottle.name]) }
                    Button("Show launch log") { store.startLogTail(bottle.name) }
                }
                HStack(spacing: 8) {
                    Button("Reveal prefix in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil, inFileViewerRootedAtPath: bottle.prefix.path)
                    }
                    if let appid {
                        Button("Open in Steam") {
                            store.openInSteam("steam://run/\(appid)", prefix: bottle.prefix)
                        }
                    }
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(store.busy)
        }
    }

    // MARK: Console (live CLI output)

    private var console: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Console", icon: "terminal")
                Spacer()
                Button("Clear") { store.logText = "" }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ConsoleView()
                .frame(height: 180)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    // MARK: Save

    private func save() {
        var env = Dictionary(
            uniqueKeysWithValues: envRows
                .filter { !$0.key.isEmpty }
                .map { ($0.key, $0.value) })
        for sw in MageStore.envSwitches {
            env[sw.id] = switchStates[sw.id] == true ? sw.onValue : nil
        }
        env[MageStore.frameRateCapKey] = frameCap == 0 ? nil : String(frameCap)
        recipe.env = env.isEmpty ? nil : env
        recipe.launch = steps.isEmpty ? nil : steps.map(\.step).filter { !$0.program.isEmpty }
        store.saveRecipe(recipe)
        if bottle.imported, prefixPath != bottle.prefix.path {
            store.setBottlePrefix(bottle, to: URL(fileURLWithPath: prefixPath))
        }
        dismiss()
    }
}
