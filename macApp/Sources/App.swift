import SwiftUI

@main
struct H1ControlApp: App {
    @StateObject private var model = HeadsetModel()
    @StateObject private var wired = WiredAudio()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model, wired: wired)
        } label: {
            Image(systemName: model.link == .connected || wired.isConnected ? "headphones" : "headphones.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var model: HeadsetModel
    @ObservedObject var wired: WiredAudio

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Both views share one space and only the active one is visible, so the panel never changes size
            // while open (menu bar panels don't re-anchor or keep their rounding when they resize).
            ZStack(alignment: .topLeading) {
                bluetoothSections
                    .opacity(wired.isConnected ? 0 : 1)
                    .allowsHitTesting(!wired.isConnected)
                    .accessibilityHidden(wired.isConnected)
                wiredSection
                    .opacity(wired.isConnected ? 1 : 0)
                    .allowsHitTesting(wired.isConnected)
                    .accessibilityHidden(!wired.isConnected)
            }

            Divider()

            Toggle("Launch at login", isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack {
                Spacer()
                Button("Quit H1 Control") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(RoundedPanel(cornerRadius: 14))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.deviceName ?? "Studio H1").font(.headline)
                Text(status).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if model.link == .disconnected && !wired.isConnected {
                Button("Connect") { model.connect() }
                    .controlSize(.small)
            }
        }
    }

    private var status: String {
        if wired.isConnected { return "Wired (USB-C)" }
        switch model.link {
        case .connected:
            if let battery = model.battery { return "Connected · \(battery)% battery" }
            return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Not connected"
        }
    }

    // MARK: - Wired

    private var wiredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wired audio").font(.subheadline.weight(.semibold))
            valueRow("Output now", wired.current?.label ?? "—")
            valueRow("Best supported", wired.best?.label ?? "—")
            if let best = wired.best, wired.current != best {
                Button("Use \(best.label)") { wired.useBestFormat() }
                    .controlSize(.small)
            }
            if let error = wired.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            caption("Over USB-C the audio is uncompressed (lossless). The headphones turn Bluetooth off while wired, " +
                    "so noise control and modes can only be changed with their buttons.")
        }
    }

    // MARK: - Bluetooth

    private var bluetoothSections: some View {
        VStack(alignment: .leading, spacing: 12) {
        // Fixed-height slot so a message appearing or disappearing doesn't resize the panel.
        caption(model.message ?? "")
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .topLeading)

        VStack(alignment: .leading, spacing: 6) {
            Text("Noise control").font(.subheadline.weight(.semibold))
            Picker("Noise control", selection: Binding(
                get: { model.noiseMode ?? .off },
                set: { model.setNoiseMode($0) }
            )) {
                ForEach([NoiseChoice.off, .transparency, .anc]) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.link != .connected)
            caption("Changes made with the ANC button aren't reported, so this shows the last mode set here.")
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("Modes").font(.subheadline.weight(.semibold))
            modeRow("Game mode", hint: "Hold ANC 1 s · needs LDAC off", value: onOff(model.gameMode))
            modeRow("Spatial audio", hint: "Press ANC twice", value: onOff(model.spatialAudio))
            modeRow("Adaptive noise", hint: "Hold ANC + plus 1 s", value: "Not reported")
            caption("Switch these on the headphones; they show the last state the headphones reported.")
        }
        }
    }

    // MARK: - Pieces

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func modeRow(_ title: String, hint: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func onOff(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "On"
        case .some(false): return "Off"
        case .none: return "—"
        }
    }
}

/// Rounds the menu bar panel's corners. Apps built against an SDK older than the running macOS get the
/// older square-cornered panel, so clip the window's frame view ourselves (again each time it opens).
private struct RoundedPanel: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView { WindowHook(cornerRadius: cornerRadius) }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowHook: NSView {
        let cornerRadius: CGFloat
        private var observer: NSObjectProtocol?

        init(cornerRadius: CGFloat) {
            self.cornerRadius = cornerRadius
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit { observer.map(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            applyRounding()
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.applyRounding() }
        }

        private func applyRounding() {
            guard let window, let frameView = window.contentView?.superview else { return }
            frameView.wantsLayer = true
            frameView.layer?.cornerRadius = cornerRadius
            frameView.layer?.cornerCurve = .continuous
            frameView.layer?.masksToBounds = true
            window.invalidateShadow()
        }
    }
}
