// Read-only: JieLi ADV info (opcode 0xC1) with per-type masks (big-endian 32-bit, bit n = type n).
import Foundation
import IOBluetooth
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
func rcsp(_ op: UInt8, _ sn: UInt8, _ p: [UInt8]) -> [UInt8] {
    let l = p.count + 1
    return [0xFE, 0xDC, 0xBA, 0xC0, op, UInt8(l >> 8), UInt8(l & 0xFF), sn] + p + [0xEF]
}
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        print("   <-", hex(Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n)))); fflush(stdout)
    }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
let d = D(); var c: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&c, withChannelID: 1, delegate: d) == kIOReturnSuccess, let ch = c else { print("open failed"); exit(1) }
pump(1)
var sn: UInt8 = 1
for t in 0..<11 {
    let mask = UInt32(1) << UInt32(t)
    var m = rcsp(0xC1, sn, [UInt8(mask >> 24), UInt8((mask >> 16) & 0xFF), UInt8((mask >> 8) & 0xFF), UInt8(mask & 0xFF)]); sn &+= 1
    print("type \(t):"); fflush(stdout)
    _ = ch.writeSync(&m, length: UInt16(m.count)); pump(0.8)
}
ch.close(); pump(0.5)
