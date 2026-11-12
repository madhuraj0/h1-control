import Foundation
import IOBluetooth
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
print("name:", dev.name ?? "?", "connected:", dev.isConnected())
_ = dev.performSDPQuery(nil)
let deadline = Date().addingTimeInterval(8)
while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
for case let rec as IOBluetoothSDPServiceRecord in dev.services ?? [] {
    var ch: BluetoothRFCOMMChannelID = 0
    let rf = rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess ? "RFCOMM ch \(ch)" : ""
    var uuids: [String] = []
    if let a = rec.getAttributeDataElement(1), let arr = a.getArrayValue() as? [IOBluetoothSDPDataElement] {
        for e in arr { if let u = e.getUUIDValue() { uuids.append(u.description) } }
    }
    print("-", rec.getServiceName() ?? "(unnamed)", rf, uuids.joined(separator: " "))
}
