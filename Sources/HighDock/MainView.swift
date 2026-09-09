import SwiftUI
import ServiceManagement
import HighDockCore

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmDelete = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                Label("HighDock", systemImage: "dock.rectangle")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 16).padding(.top, 24)
                List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                    if model.activeSetup == nil {
                        Section("Connected now") {
                            Label("Unsaved setup", systemImage: "display.badge.checkmark")
                                .tag(Optional<UUID>.none)
                        }
                    }
                    Section("Saved setups") {
                        ForEach(model.setups) { setup in
                            HStack(spacing: 10) {
                                Image(systemName: setup.layout.displays.count > 1 ? "display.2" : "display")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(setup.name).lineLimit(1)
                                    if setup.id == model.activeSetup?.id {
                                        Text("Connected").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(.vertical, 4).tag(Optional(setup.id))
                        }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.paused ? "Switching paused" : "Automatic switching", systemImage: model.paused ? "pause.circle" : "bolt.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                        .toggleStyle(.checkbox).font(.caption)
                    if model.loginNeedsApproval {
                        Button("Allow in System Settings") { SMAppService.openSystemSettingsLoginItems() }
                            .font(.caption)
                    }
                }.padding(16)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.selectedSetup?.name ?? "Make yourself at home.")
                                .font(.system(size: 27, weight: .semibold, design: .rounded))
                            Text(model.editingCurrent ? "Your Dock, right where you like it." : "Ready for the next time you connect.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.editingCurrent ? "CONNECTED" : "SAVED")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(model.editingCurrent ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1), in: Capsule())
                    }
                    MonitorPreview(layout: model.displayedLayout, settings: model.draftSettings)
                        .frame(height: 210)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.draftSettings)
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("Setup name", text: $model.draftName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Setup name")
                        HStack {
                            Text("Dock position").fontWeight(.medium)
                            Spacer()
                            Picker("Dock position", selection: $model.draftSettings.edge) {
                                ForEach(DockEdge.allCases, id: \.self) { edge in
                                    Text(edge.rawValue.capitalized).tag(edge)
                                }
                            }.pickerStyle(.segmented).frame(maxWidth: 260).labelsHidden()
                        }
                        Divider()
                        Toggle(isOn: $model.draftSettings.autoHide) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Automatically hide Dock").fontWeight(.medium)
                                Text("Show it when your pointer reaches the edge.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.toggleStyle(.switch)
                            .accessibilityLabel("Automatically hide Dock")
                            .accessibilityHint("Show the Dock when your pointer reaches the edge.")
                    }
                    if model.displayedLayout.signature == nil {
                        Label("We could not identify this display layout. Reconnect your displays to try again.", systemImage: "display.trianglebadge.exclamationmark")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let error = model.error {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(error).font(.callout).textSelection(.enabled)
                            Spacer()
                            Button("Retry") { model.retry() }.disabled(model.applying)
                        }.padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        if model.selectedSetup != nil {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Image(systemName: "trash")
                            }.help("Delete setup").accessibilityLabel("Delete setup")
                                .disabled(model.applying || !model.storageAvailable)
                        }
                        Spacer()
                        if model.applying { ProgressView().controlSize(.small) }
                        else if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary) }
                        Button(model.editingCurrent ? "Save and Apply" : "Save Setup") { model.save() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(!model.canSave)
                    }
                    Text("Resize your Dock as usual. HighDock only remembers its edge and hiding setting.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(30)
            }.background(.background)
        }
        .toolbar {
            ToolbarItem {
                Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play" : "pause") { model.togglePause() }
                    .help(model.paused ? "Resume automatic switching" : "Pause automatic switching")
            }
        }
        .confirmationDialog("Delete this setup?", isPresented: $confirmDelete) {
            Button("Delete Setup", role: .destructive) { model.deleteSelected() }
        } message: { Text("The Dock will stay as it is.") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshLoginStatus() }
    }
}

struct MonitorPreview: View {
    let layout: DisplayLayout
    let settings: DockSettings
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            let displays = layout.displays.filter { $0.mirrorOf == nil }
            let minX = displays.map(\.x).min() ?? 0
            let minY = displays.map(\.y).min() ?? 0
            let width = max(1, (displays.map { $0.x + $0.width }.max() ?? 1) - minX)
            let height = max(1, (displays.map { $0.y + $0.height }.max() ?? 1) - minY)
            let scale = min((geometry.size.width - 70) / width, (geometry.size.height - 60) / height)
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.07 : 0.04))
                ForEach(displays) { display in
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(.linearGradient(colors: [.indigo.opacity(0.8), .cyan.opacity(0.65), .teal.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Ellipse().fill(.white.opacity(0.13)).rotationEffect(.degrees(-30)).padding(-25).blur(radius: 8)
                        VStack {
                            HStack {
                                Text(display.name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                                if display.primary { Image(systemName: "star.fill").font(.system(size: 7)) }
                            }.foregroundStyle(.white.opacity(0.9)).padding(8)
                            Spacer()
                        }
                        if display.primary || displays.count == 1 {
                            dockGlyph
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                                .padding(7)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(contrast == .increased ? Color.primary : Color.black.opacity(0.65), lineWidth: 4))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 7)
                    .frame(width: max(15, display.width * scale), height: max(15, display.height * scale))
                    .position(x: (geometry.size.width - width * scale) / 2 + (display.x - minX + display.width / 2) * scale,
                              y: (geometry.size.height - height * scale) / 2 + (display.y - minY + display.height / 2) * scale)
                }
                VStack { Spacer(); Text("Edge preview · macOS chooses the display")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 8) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(layout.displays.count) displays. Dock on the \(settings.edge.rawValue). Auto-hide \(settings.autoHide ? "on" : "off"). Preview only; macOS chooses the display.")
    }
    private var alignment: Alignment {
        switch settings.edge { case .left: .leading; case .bottom: .bottom; case .right: .trailing }
    }
    private var dockGlyph: some View {
        let vertical = settings.edge != .bottom
        return (vertical ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2).fill([Color.blue, .white, .orange, .purple, .mint][index])
                    .frame(width: 7, height: 7)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: settings.autoHide ? [2, 2] : [])))
        .opacity(settings.autoHide ? 0.5 : 1)
    }
}
