// Listen-only: opens RFCOMM ch 1 and ch 10, speaks button-press cues, logs every byte received.
import Foundation
import IOBluetooth
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
let t0 = Date()
func ts() -> String { String(format: "%5.1fs", Date().timeIntervalSince(t0)) }
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        print(ts(), "  <- ch\(c.getID())", hex(Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n)))); fflush(stdout)
    }
    func rfcommChannelClosed(_ c: IOBluetoothRFCOMMChannel!) { print(ts(), "  ch\(c.getID()) closed"); fflush(stdout) }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
func say(_ s: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = [s]
    try? p.run(); while p.isRunning { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) } }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
let d = D(); var c1: IOBluetoothRFCOMMChannel?; var c10: IOBluetoothRFCOMMChannel?
print("open ch1:", dev.openRFCOMMChannelSync(&c1, withChannelID: 1, delegate: d) == kIOReturnSuccess)
print("open ch10:", dev.openRFCOMMChannelSync(&c10, withChannelID: 10, delegate: d) == kIOReturnSuccess)
pump(2)
for cue in ["Hold A N C", "Hold A N C again", "Double press A N C", "Double press A N C again", "Hold A N C and plus", "Hold A N C and plus again"] {
    print(ts(), "=== CUE:", cue); fflush(stdout)
    say(cue); pump(9)
}
say("Done"); c1?.close(); c10?.close(); pump(0.5)
