import Foundation
import IOBluetooth

func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
func oppo(_ cmd: UInt16, _ seq: UInt8, _ p: [UInt8] = []) -> [UInt8] {
    [0xAA, UInt8(p.count + 7), 0, 0, UInt8(cmd & 0xFF), UInt8(cmd >> 8), seq, UInt8(p.count & 0xFF), UInt8(p.count >> 8)] + p
}
// JieLi RCSP: FE DC BA <flag> <opcode> <len BE16 = 1+payload> <sn> <payload> EF
func rcsp(_ op: UInt8, _ sn: UInt8, _ p: [UInt8]) -> [UInt8] {
    let l = p.count + 1
    return [0xFE, 0xDC, 0xBA, 0xC0, op, UInt8(l >> 8), UInt8(l & 0xFF), sn] + p + [0xEF]
}

class D: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var got = 0
    func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        got += 1
        print("   <-", hex(Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))))
    }
    func rfcommChannelClosed(_ c: IOBluetoothRFCOMMChannel!) { print("   (closed)") }
}
func pump(_ s: Double) { let e = Date().addingTimeInterval(s); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) } }

guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
for ch in CommandLine.arguments.dropFirst().compactMap({ UInt8($0) }) {
    print("== RFCOMM channel \(ch)")
    let d = D(); var chan: IOBluetoothRFCOMMChannel?
    let r = dev.openRFCOMMChannelSync(&chan, withChannelID: ch, delegate: d)
    guard r == kIOReturnSuccess, let c = chan else { print("   open failed: \(r)"); continue }
    pump(1.5); print("   (passive listen done)")
    func send(_ label: String, _ b: [UInt8]) {
        var m = b; print("   ->", label, hex(b))
        _ = c.writeSync(&m, length: UInt16(m.count)); pump(1.5)
    }
    send("oppo hello", oppo(0x0100, 1))
    send("oppo productID", oppo(0x0103, 2))
    send("oppo battery", oppo(0x0106, 3))
    send("oppo noise", oppo(0x010C, 4, [1, 1]))
    send("rcsp targetInfo", rcsp(0x03, 1, [0xFF, 0xFF, 0xFF, 0xFF, 0x00]))
    print("   replies: \(d.got)")
    c.close(); pump(1)
}
