// Runs ONE game-mode candidate command by number, so the user can verify via the ANC-hold prompt.
// Usage: gametest <n>   (no argument lists candidates)
import Foundation
import IOBluetooth
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
func rcsp(_ op: UInt8, _ sn: UInt8, _ p: [UInt8]) -> [UInt8] {
    let l = p.count + 1
    return [0xFE, 0xDC, 0xBA, 0xC0, op, UInt8(l >> 8), UInt8(l & 0xFF), sn] + p + [0xEF]
}
let candidates: [(String, [UInt8])] = [
    ("JieLi ADV work mode = 2 (C0 02 05 02)",            rcsp(0xC0, 1, [0x02, 0x05, 0x02])),
    ("JieLi ADV work mode = 1 (C0 02 05 01)",            rcsp(0xC0, 1, [0x02, 0x05, 0x01])),
    ("JieLi sys-info attr 09 = 01 (08 FF 02 09 01)",     rcsp(0x08, 1, [0xFF, 0x02, 0x09, 0x01])),
    ("Raw realme frame 85 86 87 02 04 01",               [0x85, 0x86, 0x87, 0x02, 0x04, 0x01]),
    ("RCSP 0xFF wrapping full realme frame",             rcsp(0xFF, 1, [0x85, 0x86, 0x87, 0x02, 0x04, 0x01])),
    ("RCSP 0xFF wrapping 04 01",                         rcsp(0xFF, 1, [0x04, 0x01])),
]
guard CommandLine.arguments.count > 1, let n = Int(CommandLine.arguments[1]), (1...candidates.count).contains(n) else {
    for (i, c) in candidates.enumerated() { print("\(i + 1). \(c.0)") }; exit(0)
}
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        print("  <-", hex(Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n)))); fflush(stdout)
    }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
let d = D(); var c: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&c, withChannelID: 1, delegate: d) == kIOReturnSuccess, let ch = c else { print("open failed"); exit(1) }
pump(1)
let (name, bytes) = candidates[n - 1]
print("Test \(n): \(name)"); print("  ->", hex(bytes))
var m = bytes; _ = ch.writeSync(&m, length: UInt16(m.count)); pump(2)
ch.close(); pump(0.5)
