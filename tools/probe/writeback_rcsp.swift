// Sends the realme-style "85 86 87 <len> <feature> <value>" frames observed on button presses
// back to the headphones on RFCOMM ch 1, with spoken cues, logging any reply.
import Foundation
import IOBluetooth
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
let t0 = Date()
func ts() -> String { String(format: "%5.1fs", Date().timeIntervalSince(t0)) }
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        print(ts(), "  <- ch\(c.getID())", hex(Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n)))); fflush(stdout)
    }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
func say(_ s: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = [s]
    try? p.run(); while p.isRunning { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) } }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
let d = D(); var c: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&c, withChannelID: 1, delegate: d) == kIOReturnSuccess, let ch = c else { print("open failed"); exit(1) }
pump(1.5)
func rcsp(_ op: UInt8, _ sn: UInt8, _ p: [UInt8]) -> [UInt8] {
    let l = p.count + 1
    return [0xFE, 0xDC, 0xBA, 0xC0, op, UInt8(l >> 8), UInt8(l & 0xFF), sn] + p + [0xEF]
}
var sn: UInt8 = 1
let steps: [(String, [UInt8])] = [
    ("Game mode on, A",  [0x85, 0x86, 0x87, 0x02, 0x04, 0x01]),
    ("Game mode off, A", [0x85, 0x86, 0x87, 0x02, 0x04, 0x00]),
    ("Game mode on, B",  [0x04, 0x01]),
    ("Game mode off, B", [0x04, 0x00]),
]
for (cue, payload) in steps {
    print(ts(), "=== CUE:", cue); fflush(stdout)
    say(cue); pump(0.8)
    var m = rcsp(0xFF, sn, payload); sn &+= 1
    print(ts(), "  ->", hex(m)); fflush(stdout)
    _ = ch.writeSync(&m, length: UInt16(m.count)); pump(6)
}
say("Done"); ch.close(); pump(0.5)
