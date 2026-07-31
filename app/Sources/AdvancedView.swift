import AppKit
import SwiftUI

/// Advanced per-game editor. Writes recipe JSON (tuning lives in recipe
/// data — the GUI only authors that data, never logic).
struct AdvancedView: View {
    @EnvironmentObject private var store: MageStore
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle
    @State private var recipe: Recipe
    @State private var prefixPath: String
    @State private var switchStates: [String: Bool] = [:]
    @State private var frameCap: Int = 0
    @State private var envRows: [EnvRow] = []
    @State private var steps: [LaunchStep] = []

    struct EnvRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    init(bottle: Bottle, recipe: Recipe) {
        self.bottle = bottle
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
        _steps = State(initialValue: recipe.launch ?? [])
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

            LabeledContent("Runtime") {
                Picker("Runtime", selection: $recipe.runtime) {
                    ForEach(store.runtimes) { runtime in
                        Text(runtime.displayName).tag(runtime.id)
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
                Button { steps.append(LaunchStep(program: "", args: nil, background: true, thenWait: nil)) } label: {
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
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    stepRow(index)
                }
            }
        }
    }

    private func stepRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(index + 1).")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Program (e.g. C:\\…\\steam.exe)", text: $steps[index].program)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                Button { moveStep(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).disabled(index == 0)
                Button { moveStep(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).disabled(index == steps.count - 1)
                Button { steps.remove(at: index) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("Arguments (space-separated)", text: Binding(
                    get: { (steps[index].args ?? []).joined(separator: " ") },
                    set: { steps[index].args = $0.isEmpty ? nil : $0.split(separator: " ").map(String.init) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.leading, 26)
                Toggle("Background", isOn: Binding(
                    get: { steps[index].background ?? true },
                    set: { steps[index].background = $0 }))
                .toggleStyle(.checkbox)
                Text("then wait")
                    .foregroundStyle(.secondary)
                TextField("0", text: Binding(
                    get: { steps[index].thenWait.map(String.init) ?? "" },
                    set: { steps[index].thenWait = Int($0) }))
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
        recipe.launch = steps.isEmpty ? nil : steps.filter { !$0.program.isEmpty }
        store.saveRecipe(recipe)
        if bottle.imported, prefixPath != bottle.prefix.path {
            store.setBottlePrefix(bottle, to: URL(fileURLWithPath: prefixPath))
        }
        dismiss()
    }
}
