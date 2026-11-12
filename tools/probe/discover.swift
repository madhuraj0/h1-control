// Feature discovery: writes 01 then 00 to candidate one-byte attributes of
// function 0xFF (public) via RCSP SET_SYS_INFO (0x08), announcing each step via `say`.
import Foundation
import IOBluetooth
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
func rcsp(_ op: UInt8, _ sn: UInt8, _ p: [UInt8]) -> [UInt8] {
    let l = p.count + 1
    return [0xFE, 0xDC, 0xBA, 0xC0, op, UInt8(l >> 8), UInt8(l & 0xFF), sn] + p + [0xEF]
}
let t0 = Date()
func ts() -> String { String(format: "%5.1fs", Date().timeIntervalSince(t0)) }
let watched: Set<UInt8> = [0x06, 0x09, 0x0F, 0x0D]
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        let b = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        if b.count > 10 && b[3] == 0x00 && b[4] == 0x07 {
            var i = 10; var out: [String] = []
            while i < b.count - 1 { let l = Int(b[i]); if l == 0 { break }; let t = b[i+1]
                if watched.contains(t) { out.append(String(format: "%02X=", t) + hex(Array(b[(i+2)..<(i+1+l)]))) }
                i += 1 + l }
            print(ts(), "   <- state:", out.joined(separator: "  "))
        } else { print(ts(), "   <-", hex(b)) }
        fflush(stdout)
    }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
func say(_ s: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = [s]; try? p.run(); p.waitUntilExit() }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
let d = D(); var chan: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&chan, withChannelID: 1, delegate: d) == kIOReturnSuccess, let c = chan else { print("open failed"); exit(1) }
var sn: UInt8 = 1
func send(_ label: String, _ b: [UInt8], wait: Double = 1.0) { var m = b; sn &+= 1; print(ts(), "->", label, hex(b)); fflush(stdout); _ = c.writeSync(&m, length: UInt16(m.count)); pump(wait) }
func read() { send("read", rcsp(0x07, sn, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF])) }
read()
let attrs: [UInt8] = CommandLine.arguments.dropFirst().compactMap { UInt8($0, radix: 16) }
for (n, a) in (attrs.isEmpty ? [0x06, 0x09, 0x0F] : attrs).enumerated() {
    for v: UInt8 in [1, 0] {
        print(ts(), "=== TEST \(n + 1): attr \(String(format: "%02X", a)) = \(v)"); fflush(stdout)
        say("Test \(n + 1), \(v == 1 ? "on" : "off")"); pump(1)
        send(String(format: "SET attr %02X = %02X", a, v), rcsp(0x08, sn, [0xFF, 0x02, a, v]), wait: 1.5)
        read(); pump(4)
    }
}
say("Done")
c.close(); pump(0.5)
