import Foundation
import IOBluetooth
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
func rcsp(_ op: UInt8, _ sn: UInt8, _ p: [UInt8]) -> [UInt8] {
    let l = p.count + 1
    return [0xFE, 0xDC, 0xBA, 0xC0, op, UInt8(l >> 8), UInt8(l & 0xFF), sn] + p + [0xEF]
}
let t0 = Date()
func ts() -> String { String(format: "%5.1fs", Date().timeIntervalSince(t0)) }
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var last = ""
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        var b = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        let isPoll = b.count > 9 && b[3] == 0x00 && b[4] == 0x07
        if isPoll { b[8] = 0 } // ignore sequence number
        let s = hex(b)
        if !isPoll { print(ts(), "PUSH", s); fflush(stdout); return }
        if s != last { print(ts(), last.isEmpty ? "INITIAL" : "CHANGED", s); fflush(stdout); last = s }
    }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
let d = D(); var chan: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&chan, withChannelID: 1, delegate: d) == kIOReturnSuccess, let c = chan else { print("open failed"); exit(1) }
let secs = Double(CommandLine.arguments.dropFirst().first ?? "60")!
var sn: UInt8 = 1
while Date().timeIntervalSince(t0) < secs {
    var m = rcsp(0x07, sn, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF]); sn &+= 1
    _ = c.writeSync(&m, length: UInt16(m.count)); pump(2)
}
c.close(); pump(0.5); print(ts(), "done")
