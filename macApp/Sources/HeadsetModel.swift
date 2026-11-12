import Foundation
import H1Core
import IOBluetooth
import ServiceManagement

/// Simple Swift mirror of the core's NoiseMode, so SwiftUI can use it as a selection.
enum NoiseChoice: Int32, CaseIterable, Identifiable {
    case off = 0, transparency = 2, anc = 1

    var id: Int32 { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .transparency: return "Transparency"
        case .anc: return "ANC"
        }
    }

    var coreMode: NoiseMode { NoiseMode.companion.fromCode(code: rawValue)! }

    init?(_ mode: NoiseMode?) {
        guard let mode else { return nil }
        self.init(rawValue: mode.code)
    }
}

/// Owns the RFCOMM connection to the headphones (IOBluetooth) and feeds it through the shared Kotlin core.
/// IOBluetooth delivers callbacks on the main run loop, so everything here runs on the main thread.
final class HeadsetModel: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    enum Link { case disconnected, connecting, connected }

    @Published private(set) var link: Link = .disconnected
    @Published private(set) var deviceName: String?
    @Published private(set) var battery: Int?
    @Published private(set) var noiseMode: NoiseChoice?
    @Published private(set) var lastSeenFeatures: [Int: Int]
    @Published private(set) var message: String?
    @Published var launchAtLogin: Bool {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    var gameMode: Bool? { lastSeenFeatures[Int(RealmeFrame.shared.FEATURE_GAME_MODE)].map { $0 != 0 } }
    var spatialAudio: Bool? { lastSeenFeatures[Int(RealmeFrame.shared.FEATURE_SPATIAL_AUDIO)].map { $0 != 0 } }

    private let defaults = UserDefaults.standard
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var session: HeadsetSession?
    private var pollTimer: Timer?
    private var retryTimer: Timer?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?

    private static let controlChannel: BluetoothRFCOMMChannelID = 1
    private static let featuresKey = "buttonFeatures"
    private static let addressKey = "deviceAddress"

    override init() {
        let saved = UserDefaults.standard.dictionary(forKey: Self.featuresKey) as? [String: Int] ?? [:]
        lastSeenFeatures = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in Int(k).map { ($0, v) } })
        launchAtLogin = SMAppService.mainApp.status == .enabled
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceDidConnect(_:device:)))
        connect()
    }

    // MARK: - Actions

    func connect() {
        guard link == .disconnected else { return }
        guard let device = findDevice() else {
            message = "Pair the Studio H1 with this Mac in System Settings › Bluetooth."
            return
        }
        self.device = device
        deviceName = device.name
        guard device.isConnected() else {
            message = "Headphones aren't connected to this Mac."
            return
        }
        link = .connecting
        message = nil
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: Self.controlChannel, delegate: self)
        if result != kIOReturnSuccess {
            controlChannelUnavailable()
        } else {
            channel = newChannel
        }
    }

    func setNoiseMode(_ choice: NoiseChoice) {
        session?.setNoiseMode(mode: choice.coreMode)
    }

    func cycleNoiseMode() {
        let next: NoiseChoice
        switch noiseMode {
        case .off: next = .transparency
        case .transparency: next = .anc
        case .anc, .none: next = .off
        }
        setNoiseMode(next)
    }

    // MARK: - Device discovery

    private func findDevice() -> IOBluetoothDevice? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        if let saved = defaults.string(forKey: Self.addressKey),
           let match = paired.first(where: { $0.addressString == saved }) {
            return match
        }
        let match = paired.first { device in
            let name = (device.name ?? "").lowercased()
            return name.contains("studio") || name.contains("h1")
        }
        if let match { defaults.set(match.addressString, forKey: Self.addressKey) }
        return match
    }

    @objc private func deviceDidConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.addressString == (self.device ?? findDevice())?.addressString else { return }
        // Give the headphones a moment to finish connecting audio before opening the control channel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connect() }
    }

    @objc private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        tearDown()
        message = "Headphones disconnected."
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            controlChannelUnavailable()
            return
        }
        let session = HeadsetSession(transport: { [weak self] bytes in self?.write(bytes) })
        session.onStateChanged = { [weak self] state in self?.apply(state) }
        self.session = session
        link = .connected
        message = nil
        retryTimer?.invalidate()
        disconnectNotification = device?.register(
            forDisconnectNotification: self, selector: #selector(deviceDidDisconnect(_:device:)))
        session.requestStatus()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.session?.requestStatus()
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: Int8.self), count: dataLength)
        let array = KotlinByteArray(size: Int32(dataLength))
        for (index, byte) in bytes.enumerated() { array.set(index: Int32(index), value: byte) }
        session?.onBytes(data: array)
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel === channel else { return }
        tearDown()
        // Closed while the headphones are still connected (e.g. they reset their link): reopen shortly.
        guard device?.isConnected() == true else { return }
        link = .connecting
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.link = .disconnected
            self?.connect()
        }
    }

    // MARK: - Internals

    private func write(_ bytes: KotlinByteArray) {
        guard let channel else { return }
        var buffer = (0..<bytes.size).map { UInt8(bitPattern: bytes.get(index: $0)) }
        _ = channel.writeSync(&buffer, length: UInt16(buffer.count))
    }

    private func apply(_ state: HeadsetState) {
        battery = (state.batteryPercent as NSNumber?)?.intValue
        noiseMode = NoiseChoice(state.noiseMode)
        var features = lastSeenFeatures
        // Kotlin's Map<Int, Int> arrives as an NSDictionary of NSNumbers; read it as such rather than
        // force-bridging to [KotlinInt: KotlinInt], which fails at runtime.
        for (key, value) in state.buttonFeatures as NSDictionary {
            if let key = key as? NSNumber, let value = value as? NSNumber { features[key.intValue] = value.intValue }
        }
        if features != lastSeenFeatures {
            lastSeenFeatures = features
            defaults.set(Dictionary(uniqueKeysWithValues: features.map { (String($0.key), $0.value) }), forKey: Self.featuresKey)
        }
    }

    /// The headphones accept one control connection; usually the phone holds it. Keep retrying quietly.
    private func controlChannelUnavailable() {
        tearDown()
        message = "Control channel busy. Another device (e.g. the phone app) may be using it. Retrying…"
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.connect() }
    }

    private func tearDown() {
        pollTimer?.invalidate()
        pollTimer = nil
        disconnectNotification?.unregister()
        disconnectNotification = nil
        let old = channel
        channel = nil
        session = nil
        old?.close()
        link = .disconnected
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Couldn't change launch at login: \(error.localizedDescription)"
        }
    }
}
