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
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        let b = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        // For sysinfo replies, show only attr 0x0D / 0x0E
        if b.count > 10 && b[4] == 0x07 {
            var i = 10; var out: [String] = []
            while i < b.count - 1 { let l = Int(b[i]); if l == 0 { break }; let t = b[i+1]
                if t == 0x0D || t == 0x0E { out.append(String(format: "attr %02X: ", t) + hex(Array(b[(i+2)..<(i+1+l)]))) }
                i += 1 + l }
            print(ts(), "   <- state:", out.joined(separator: " | "))
        } else { print(ts(), "   <-", hex(b)) }
        fflush(stdout)
    }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
let d = D(); var chan: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&chan, withChannelID: 1, delegate: d) == kIOReturnSuccess, let c = chan else { print("open failed"); exit(1) }
var sn: UInt8 = 1
func send(_ label: String, _ b: [UInt8]) { var m = b; sn &+= 1; print(ts(), "->", label, hex(b)); fflush(stdout); _ = c.writeSync(&m, length: UInt16(m.count)); pump(1.5) }
func read() { send("read", rcsp(0x07, sn, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF])) }
read()
for (name, mode) in [("ANC (01)", UInt8(1)), ("TRANSPARENCY (02)", 2), ("OFF (00)", 0)] {
    let gains: [UInt8] = mode == 0 ? [0,0,0,0,0,0,0,0] : [0x40,0,0,0,0x40,0,0,0]
    send("SET \(name)", rcsp(0x08, sn, [0xFF, 0x0A, 0x0D, mode] + gains))
    read()
    pump(6.5)
}
c.close(); pump(0.5)
