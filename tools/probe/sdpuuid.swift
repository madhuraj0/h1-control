// Dumps service class UUIDs and RFCOMM channels for each SDP record.
import Foundation
import IOBluetooth
guard let address = ProcessInfo.processInfo.environment["H1_ADDRESS"], let dev = IOBluetoothDevice(addressString: address) else {
    print("Set H1_ADDRESS to the headphones' Bluetooth address, e.g. H1_ADDRESS=aa-bb-cc-dd-ee-ff"); exit(1)
}
_ = dev.performSDPQuery(nil)
let e = Date().addingTimeInterval(6); while Date() < e { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
func uuids(_ el: IOBluetoothSDPDataElement?) -> [String] {
    guard let el = el else { return [] }
    if let u = el.getUUIDValue() { return [u.description] }
    if let arr = el.getArrayValue() { return arr.flatMap { uuids($0 as? IOBluetoothSDPDataElement) } }
    return []
}
for case let rec as IOBluetoothSDPServiceRecord in dev.services ?? [] {
    var ch: BluetoothRFCOMMChannelID = 0
    let rf = rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess ? "ch \(ch)" : "-"
    let attrs = rec.attributes as? [NSNumber: IOBluetoothSDPDataElement] ?? [:]
    print(rec.getServiceName() ?? "(unnamed)", rf, uuids(attrs[1]).joined(separator: ","))
}
