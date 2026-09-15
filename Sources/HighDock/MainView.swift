import SwiftUI
import ServiceManagement
import HighDockCore

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmDelete = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            VStack(spacing: 0) {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(model.selectedSetup?.name ?? "New Setup")
                                    .font(.title2.weight(.semibold))
                                    .lineLimit(2)
                                Spacer()
                                Label(model.editingCurrent ? "Connected" : "Not connected",
                                      systemImage: model.editingCurrent ? "checkmark.circle.fill" : "display")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            MonitorPreview(layout: model.displayedLayout, settings: model.draftSettings)
                                .frame(height: 220)
                                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.draftSettings)
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        TextField("Setup name", text: $model.draftName)
                            .textFieldStyle(.roundedBorder)
                        Picker("Main display", selection: $model.draftSettings.mainDisplayID) {
                            Text("Keep current main display").tag(Optional<String>.none)
                            ForEach(Array(model.displayedLayout.selectableDisplays.enumerated()), id: \.element.id) { index, display in
                                Text("\(index + 1). \(display.name)").tag(Optional(display.id))
                            }
                        }
                        Text("Choosing a display makes it the Mac’s main display when this setup applies. macOS still controls Dock placement on shared edges.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Dock position", selection: $model.draftSettings.edge) {
                            ForEach(DockEdge.allCases, id: \.self) { edge in
                                Text(edge.rawValue.capitalized).tag(edge)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle(isOn: $model.draftSettings.autoHide) {
                            Text("Automatically hide and show the Dock")
                            Text("Show the Dock when the pointer reaches its edge.")
                        }
                        .toggleStyle(.switch)
                        Toggle(isOn: $model.draftAnimationEnabled) {
                            Text("Animate Dock show and hide")
                            Text(model.draftSettings.autoHide
                                 ? "Turn off to remove the slide animation. The delay before showing stays unchanged."
                                 : "Turn on automatic hiding to change the animation.")
                        }
                        .toggleStyle(.switch)
                        .disabled(!model.draftSettings.autoHide)
                        .saturation(model.draftSettings.autoHide ? 1 : 0)
                        .opacity(model.draftSettings.autoHide ? 1 : 0.55)
                    } header: {
                        Text("Dock Settings")
                    } footer: {
                        Text(model.editingCurrent
                             ? "Save to apply these settings whenever this display layout connects. Dock size stays unchanged."
                             : "These settings apply the next time this display layout connects. Dock size stays unchanged.")
                    }

                    Section("General") {
                        Toggle("Launch at login", isOn: Binding(
                            get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch)
                        if model.loginNeedsApproval {
                            LabeledContent("Login permission required") {
                                Button("Open System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                            }
                        }
                    }

                    if model.displayedLayout.signature == nil {
                        Section {
                            Label("Could not identify this display layout. Reconnect your displays to try again.",
                                  systemImage: "display.trianglebadge.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = model.error {
                        Section {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text(error).textSelection(.enabled)
                                Spacer(minLength: 0)
                                Button("Retry") { model.retry() }.disabled(model.applying)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollIndicators(.hidden)
                .clipped()
                actionBar
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("HighDock")
        }
        .toolbar {
            ToolbarItem {
                Button(model.paused ? "Resume Switching" : "Pause Switching",
                       systemImage: model.paused ? "play" : "pause") { model.togglePause() }
                    .help(model.paused ? "Resume automatic switching" : "Pause automatic switching")
            }
        }
        .confirmationDialog("Delete \(model.selectedSetup?.name ?? "this setup")?", isPresented: $confirmDelete) {
            Button("Delete Setup", role: .destructive) { model.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("HighDock will forget this setup’s settings. The Dock will stay as it is.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginStatus()
            model.scheduleRefresh()
        }
    }

    private var sidebar: some View {
        List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
            if model.activeSetup == nil {
                Section("Connected Now") {
                    Label("Unsaved setup", systemImage: "display")
                        .padding(.vertical, 4)
                        .tag(Optional<UUID>.none)
                }
            }
            Section("Saved Setups") {
                ForEach(model.setups) { setup in
                    HStack(spacing: 10) {
                        Image(systemName: setup.layout.displays.count > 1 ? "display.2" : "display")
                            .font(.title3)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(setup.name).lineLimit(1)
                            Text(setup.id == model.activeSetup?.id ? "Connected" : displayCount(setup.layout))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    .tag(Optional(setup.id))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Label(model.paused ? "Automatic switching paused" : "Automatic switching on",
                      systemImage: model.paused ? "pause.circle" : "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if model.selectedSetup != nil {
                    Button("Delete Setup…", role: .destructive) { confirmDelete = true }
                        .disabled(model.applying || !model.storageAvailable)
                }
                Spacer(minLength: 0)
                if model.applying {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Applying Dock settings")
                } else if !model.status.isEmpty {
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                Button(model.editingCurrent ? "Save and Apply" : "Save Setup") { model.save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSave)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    private func displayCount(_ layout: DisplayLayout) -> String {
        layout.displays.count == 1 ? "1 display" : "\(layout.displays.count) displays"
    }
}

struct MonitorPreview: View {
    let layout: DisplayLayout
    let settings: DockSettings
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { geometry in
            let displays = layout.selectableDisplays
            let minX = displays.map(\.x).min() ?? 0
            let minY = displays.map(\.y).min() ?? 0
            let width = max(1, (displays.map { $0.x + $0.width }.max() ?? 1) - minX)
            let height = max(1, (displays.map { $0.y + $0.height }.max() ?? 1) - minY)
            let scale = min((geometry.size.width - 70) / width, (geometry.size.height - 60) / height)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    let showsDock = isMain(display) || displays.count == 1
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(.linearGradient(colors: [.indigo.opacity(0.75), .blue.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack {
                            HStack {
                                Text("\(index + 1). \(display.name)").font(.system(size: 9, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                                if isMain(display) { Image(systemName: "star.fill").font(.system(size: 7)) }
                            }
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.vertical, 8)
                            .padding(.leading, showsDock && settings.edge == .left ? 24 : 8)
                            .padding(.trailing, showsDock && settings.edge == .right ? 24 : 8)
                            Spacer()
                        }
                        if showsDock {
                            dockGlyph
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                                .padding(7)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(contrast == .increased ? Color.primary : Color.black.opacity(0.65), lineWidth: 4))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
                    .frame(width: max(15, display.width * scale), height: max(15, display.height * scale))
                    .position(x: (geometry.size.width - width * scale) / 2 + (display.x - minX + display.width / 2) * scale,
                              y: (geometry.size.height - height * scale) / 2 + (display.y - minY + display.height / 2) * scale)
                }
                VStack { Spacer(); Text(settings.mainDisplayID == nil ? "Edge preview · macOS chooses the display" : "Requested main display · Dock placement depends on macOS")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 8) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(layout.displays.count) displays. Dock on the \(settings.edge.rawValue). Auto-hide \(settings.autoHide ? "on" : "off"). Preview only; macOS chooses the display.")
    }
    private func isMain(_ display: Display) -> Bool {
        settings.mainDisplayID.map { $0 == display.id } ?? display.primary
    }
    private var alignment: Alignment {
        switch settings.edge { case .left: .leading; case .bottom: .bottom; case .right: .trailing }
    }
    private var dockGlyph: some View {
        let vertical = settings.edge != .bottom
        return (vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2).fill([Color.blue, .white, .orange, .purple, .mint][index])
                    .frame(width: 5, height: 5)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: settings.autoHide ? [2, 2] : [])))
        .opacity(settings.autoHide ? 0.5 : 1)
    }
}
