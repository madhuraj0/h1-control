import CoreAudio
import Foundation

/// Watches for the headphones connected over USB-C, where they act as a USB audio device (and switch
/// Bluetooth off, so the control channel is unavailable). Reports and sets the output stream format.
final class WiredAudio: ObservableObject {
    struct Format: Hashable, Comparable {
        let sampleRate: Double
        let bits: UInt32

        var label: String {
            let khz = sampleRate / 1000
            let rate = khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz)
            return "\(rate) / \(bits)-bit"
        }

        static func < (a: Format, b: Format) -> Bool {
            (a.sampleRate, a.bits) < (b.sampleRate, b.bits)
        }
    }

    @Published private(set) var isConnected = false
    @Published private(set) var current: Format?
    @Published private(set) var best: Format?
    @Published private(set) var error: String?

    private var outputStream: AudioObjectID?
    private var bestDescription: AudioStreamBasicDescription?
    private var listenerQueue = DispatchQueue.main

    init() {
        refresh()
        var devices = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, listenerQueue) { [weak self] _, _ in
            self?.refresh()
        }
    }

    /// Switches the USB output to the highest sample rate and bit depth it supports.
    func useBestFormat() {
        guard let stream = outputStream, var description = bestDescription else { return }
        var addr = address(kAudioStreamPropertyPhysicalFormat)
        let status = AudioObjectSetPropertyData(stream, &addr, 0, nil, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &description)
        error = status == noErr ? nil : "Couldn't change the format (error \(status))."
        // The change is applied asynchronously; read it back shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard let device = findUSBDevice(), let stream = outputStreams(of: device).first else {
            isConnected = false
            current = nil
            best = nil
            outputStream = nil
            return
        }
        isConnected = true
        outputStream = stream

        var addr = address(kAudioStreamPropertyPhysicalFormat)
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(stream, &addr, 0, nil, &size, &description) == noErr {
            current = Format(sampleRate: description.mSampleRate, bits: description.mBitsPerChannel)
        }

        let available: [AudioStreamRangedDescription] = array(stream, kAudioStreamPropertyAvailablePhysicalFormats)
        let linearPCM = available.filter { $0.mFormat.mFormatID == kAudioFormatLinearPCM }
        if let top = linearPCM.max(by: {
            Format(sampleRate: $0.mFormat.mSampleRate, bits: $0.mFormat.mBitsPerChannel)
                < Format(sampleRate: $1.mFormat.mSampleRate, bits: $1.mFormat.mBitsPerChannel)
        }) {
            bestDescription = top.mFormat
            best = Format(sampleRate: top.mFormat.mSampleRate, bits: top.mFormat.mBitsPerChannel)
        }
    }

    // MARK: - Core Audio helpers

    private func findUSBDevice() -> AudioObjectID? {
        let devices: [AudioObjectID] = array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        return devices.first { device in
            guard transportType(of: device) == kAudioDeviceTransportTypeUSB, !outputStreams(of: device).isEmpty else { return false }
            let name = self.name(of: device).lowercased()
            return name.contains("studio h1") || name.contains("realme")
        }
    }

    private func outputStreams(of device: AudioObjectID) -> [AudioObjectID] {
        array(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
    }

    private func transportType(of device: AudioObjectID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value
    }

    private func name(of device: AudioObjectID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr else { return "" }
        return name?.takeRetainedValue() as String? ?? ""
    }

    private func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [T] {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, pointer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: pointer.bindMemory(to: T.self, capacity: count), count: count))
    }

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
