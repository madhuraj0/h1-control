// Reverts the un-reverted experimental writes (0xFF "game on" payloads, ADV work mode) and prints
// status/target info to compare with the very first readings.
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
func send(_ label: String, _ op: UInt8, _ p: [UInt8]) {
    var m = rcsp(op, sn, p); sn &+= 1
    print("->", label, hex(m)); fflush(stdout)
    _ = ch.writeSync(&m, length: UInt16(m.count)); pump(1.2)
}
send("0xFF game off (full frame)", 0xFF, [0x85, 0x86, 0x87, 0x02, 0x04, 0x00])
send("0xFF game off (short)", 0xFF, [0x04, 0x00])
send("ADV work mode = 0", 0xC0, [0x02, 0x05, 0x00])
send("read status", 0x07, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
send("read target info", 0x03, [0xFF, 0xFF, 0xFF, 0xFF, 0x00])
ch.close(); pump(0.5)
