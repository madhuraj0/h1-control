// Read-only: snapshots target info (0x03) and public sys info (0x07) before and after spoken button cues,
// printing only what changed, plus any pushes. Used to look for readable game-mode / adaptive-ANC state.
import Foundation
import IOBluetooth
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
func rcsp(_ op: UInt8, _ sn: UInt8, _ p: [UInt8]) -> [UInt8] {
    let l = p.count + 1
    return [0xFE, 0xDC, 0xBA, 0xC0, op, UInt8(l >> 8), UInt8(l & 0xFF), sn] + p + [0xEF]
}
let t0 = Date()
func ts() -> String { String(format: "%5.1fs", Date().timeIntervalSince(t0)) }
func tlvs(_ b: [UInt8], from start: Int) -> [String: String] {
    var out: [String: String] = [:]; var i = start
    while i < b.count - 1 { let l = Int(b[i]); if l == 0 || i + 1 + l > b.count - 1 { break }
        out[String(format: "%02X", b[i+1])] = hex(Array(b[(i+2)..<(i+1+l)])); i += 1 + l }
    return out
}
class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var target: [String: String] = [:], sys: [String: String] = [:]
    var pending = Data()
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        let b = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        if b.count > 10 && b[0] == 0xFE && b[3] == 0x00 && b[4] == 0x03 { target = tlvs(b, from: 9) }
        else if b.count > 10 && b[0] == 0xFE && b[3] == 0x00 && b[4] == 0x07 { sys = tlvs(b, from: 10) }
        else { print(ts(), "  PUSH", hex(b)); fflush(stdout) }
    }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }
func say(_ s: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = [s]
    try? p.run(); while p.isRunning { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) } }
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
if !dev.isConnected() { print("baseband connect:", dev.openConnection() == kIOReturnSuccess); pump(2) }
let d = D(); var c: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&c, withChannelID: 1, delegate: d) == kIOReturnSuccess, let ch = c else { print("open failed"); exit(1) }
pump(1)
var sn: UInt8 = 1
func snap() -> ([String: String], [String: String]) {
    for (op, p) in [(UInt8(0x03), [UInt8](repeating: 0xFF, count: 4) + [0x00]), (0x07, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF])] {
        var m = rcsp(op, sn, p); sn &+= 1; _ = ch.writeSync(&m, length: UInt16(m.count)); pump(0.8)
    }
    return (d.target, d.sys)
}
var (prevT, prevS) = snap()
print("baseline target:", prevT.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
print("baseline sys:   ", prevS.sorted { $0.key < $1.key }.filter { $0.key != "02" }.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
fflush(stdout)
for cue in ["Hold A N C", "Hold A N C again", "Hold A N C and plus", "Hold A N C and plus again"] {
    print(ts(), "=== CUE:", cue); fflush(stdout)
    say(cue); pump(7)
    let (t, s) = snap()
    for (name, a, b) in [("target", prevT, t), ("sys", prevS, s)] {
        for k in Set(a.keys).union(b.keys).sorted() where a[k] != b[k] {
            print(ts(), "  CHANGED \(name) \(k): \(a[k] ?? "-") -> \(b[k] ?? "-")")
        }
    }
    print(ts(), "  (snapshot done)"); fflush(stdout)
    prevT = t; prevS = s
}
say("Done"); ch.close(); pump(0.5)
