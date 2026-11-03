import CoreBluetooth
import Foundation

/// A note that is still on the pendant.
struct DeviceNote: Identifiable, Hashable {
    let name: String
    let bytes: Int
    let seconds: Int
    var id: String { name }
}

/// Bluetooth link to the pendant. Finds it, keeps it connected, lists and downloads notes.
///
/// Protocol (must match firmware main/ble.c):
///   write CTRL: "L" list, "G:<name>" get (Opus if the pendant has it), "W:<name>" get the WAV,
///               "D:<name>" delete, "T:<secs>" set clock, "R:1" / "R:0" start / stop recording
///   DATA notifications, first byte: L list item, E end of list, H WAV header (u32 size),
///   P Opus header (u32 size), C file chunk, F file done, K ok, X error
///   LIVE notifications while the pendant records: S + name (start), A + bytes of the .opus file,
///   Z + u32 size (end, 0 = incomplete). A complete live note is saved right away, nothing to download.
///   J + u32 offset + name: we (re)connected while the pendant was recording. We fetch the part we
///   missed with "O:<name>:<from>:<to>", then carry on live. Out of range, the pendant just keeps
///   recording to its storage.
/// Opus files are turned back into WAV on the phone (PendantOpus), so the rest of the app only sees WAV.
final class PendantLink: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "9F2A0001-5C2B-4F3B-9C1E-7A1D5E0B1A01")
    static let ctrlUUID = CBUUID(string: "9F2A0002-5C2B-4F3B-9C1E-7A1D5E0B1A01")
    static let dataUUID = CBUUID(string: "9F2A0003-5C2B-4F3B-9C1E-7A1D5E0B1A01")
    static let liveUUID = CBUUID(string: "9F2A0004-5C2B-4F3B-9C1E-7A1D5E0B1A01")

    @Published private(set) var status = "Starting Bluetooth…"
    @Published private(set) var connected = false
    @Published private(set) var deviceNotes: [DeviceNote] = []
    @Published private(set) var downloading: String?
    @Published private(set) var progress: Double = 0
    /// Name of the note the pendant is recording and streaming right now.
    @Published private(set) var liveNote: String?

    /// Called on the main thread when a whole file has arrived.
    var onFileReceived: ((String, Data) -> Void)?

    enum LiveEvent {
        case start(String), bytes(Data), end
        case paused      // out of range; the pendant keeps recording
        case resumed     // back in range and caught up
        case incomplete  // couldn't catch up: the live text has a hole, transcribe the file instead
    }
    /// Called on the main thread for every live packet, for the live transcript.
    var onLive: ((LiveEvent) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var ctrl: CBCharacteristic?

    private var pending: [String] = []
    private var current: String?
    private var listBuffer: [DeviceNote] = []
    private var fileBuffer = Data()
    private var fileSize = 0
    private var fileIsOpus = false
    private var liveBuffer = Data()
    /// Catching up after reconnecting: live bytes wait here until the missed part has arrived
    private var liveHold: Data?
    private var liveJoined = false   // a live note continued on this connection
    private var wavOnly: Set<String> = []   // notes whose Opus copy failed to decode

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Commands

    func refreshList() { enqueue("L") }

    func download(_ name: String) {
        let cmd = (wavOnly.contains(name) ? "W:" : "G:") + name
        guard !pending.contains(cmd), current != cmd else { return }
        enqueue(cmd)
    }

    func deleteFromDevice(_ name: String) { enqueue("D:" + name) }

    /// Start or stop recording on the pendant. Goes ahead of any downloads waiting in line.
    func setRecording(_ on: Bool) {
        let cmd = on ? "R:1" : "R:0"
        pending.removeAll { $0.hasPrefix("R:") }
        pending.insert(cmd, at: 0)
        pump()
    }

    private func enqueue(_ cmd: String) {
        pending.append(cmd)
        pump()
    }

    private func pump() {
        guard current == nil, connected, let p = peripheral, let c = ctrl, !pending.isEmpty else { return }
        let cmd = pending.removeFirst()
        current = cmd
        if cmd.hasPrefix("G:") || cmd.hasPrefix("W:") {
            downloading = String(cmd.dropFirst(2))
            progress = 0
        }
        p.writeValue(Data(cmd.utf8), for: c, type: .withResponse)
    }

    private func finishCommand() {
        current = nil
        downloading = nil
        pump()
    }

    // MARK: Incoming data

    private func handle(_ packet: Data) {
        guard let tag = packet.first else { return }
        let body = packet.dropFirst()
        switch tag {
        case UInt8(ascii: "L"):
            let parts = String(decoding: body, as: UTF8.self).split(separator: "|")
            if parts.count == 3, let b = Int(parts[1]), let s = Int(parts[2]) {
                listBuffer.append(DeviceNote(name: String(parts[0]), bytes: b, seconds: s))
            }
        case UInt8(ascii: "E"):
            deviceNotes = listBuffer
            listBuffer = []
            finishCommand()
            // A live note we were following finished while we were out of range: it's a normal
            // download now (it's in this list). Give the pendant a moment to rejoin first.
            if liveNote != nil, !liveJoined {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.connected, self.liveNote != nil, !self.liveJoined else { return }
                    self.onLive?(.incomplete)
                    self.onLive?(.end)
                    self.liveNote = nil
                    self.liveBuffer = Data()
                }
            }
        case UInt8(ascii: "H"), UInt8(ascii: "P"):
            fileIsOpus = tag == UInt8(ascii: "P")
            let b = [UInt8](body)
            fileSize = b.count >= 4 ? Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24 : 0
            fileBuffer = Data(capacity: fileSize)
        case UInt8(ascii: "C"):
            fileBuffer.append(body)
            if fileSize > 0 { progress = Double(fileBuffer.count) / Double(fileSize) }
        case UInt8(ascii: "F") where current?.hasPrefix("O:") == true:
            caughtUp(fileBuffer.count == fileSize ? fileBuffer : nil)
            fileBuffer = Data()
            finishCommand()
        case UInt8(ascii: "F"):
            if let name = downloading, fileBuffer.count == fileSize {
                if fileIsOpus {
                    let data = fileBuffer
                    Task.detached(priority: .userInitiated) { [weak self] in
                        let wav = try? PendantOpus.wav(from: data)
                        await MainActor.run {
                            guard let self else { return }
                            if let wav {
                                self.onFileReceived?(name, wav)
                            } else {   // fall back to the full WAV for this note
                                self.wavOnly.insert(name)
                                self.download(name)
                            }
                        }
                    }
                } else {
                    onFileReceived?(name, fileBuffer)
                }
            } else {
                status = "Download incomplete, will retry"
            }
            fileBuffer = Data()
            finishCommand()
        case UInt8(ascii: "K"):
            if let cmd = current, cmd.hasPrefix("D:") {
                deviceNotes.removeAll { $0.name == String(cmd.dropFirst(2)) }
            }
            finishCommand()
        case UInt8(ascii: "X") where current?.hasPrefix("O:") == true:
            caughtUp(nil)
            fileBuffer = Data()
            finishCommand()
        case UInt8(ascii: "X"):
            status = "Pendant: " + String(decoding: body, as: UTF8.self)
            listBuffer = []
            fileBuffer = Data()
            finishCommand()
        default:
            break
        }
    }

    // MARK: Live notes

    /// The part recorded while we were away has arrived (or not): feed it, then the held live bytes.
    private func caughtUp(_ missed: Data?) {
        guard let held = liveHold else { return }
        liveHold = nil
        if let missed {
            liveBuffer.append(missed)
            onLive?(.bytes(missed))
            onLive?(.resumed)
        } else {
            onLive?(.incomplete)
        }
        liveBuffer.append(held)
        if !held.isEmpty { onLive?(.bytes(held)) }
    }

    private func handleLive(_ packet: Data) {
        guard let tag = packet.first else { return }
        let body = packet.dropFirst()
        switch tag {
        case UInt8(ascii: "S"):
            liveNote = String(decoding: body, as: UTF8.self)
            liveBuffer = Data()
            liveHold = nil
            liveJoined = true
            onLive?(.start(liveNote!))
        case UInt8(ascii: "A"):
            guard liveNote != nil else { break }
            if liveHold != nil { liveHold!.append(body) } else { liveBuffer.append(body); onLive?(.bytes(Data(body))) }
        case UInt8(ascii: "J"):
            let b = [UInt8](body)
            guard b.count > 4 else { break }
            let offset = Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24
            let name = String(decoding: b[4...], as: UTF8.self)
            liveJoined = true
            if liveNote != name {   // recording we haven't seen yet (started while out of range)
                liveNote = name
                liveBuffer = Data()
                onLive?(.start(name))
            }
            if liveBuffer.count == offset {
                onLive?(.resumed)
            } else if liveBuffer.count < offset {
                liveHold = Data()
                let cmd = "O:\(name):\(liveBuffer.count):\(offset)"
                pending.removeAll { $0.hasPrefix("O:") }
                pending.insert(cmd, at: 0)
                pump()
            } else {
                onLive?(.incomplete)   // shouldn't happen; keep going, the file is transcribed later
            }
        case UInt8(ascii: "Z"):
            let b = [UInt8](body)
            let size = b.count >= 4 ? Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24 : 0
            guard let name = liveNote else { return }
            onLive?(.end)
            let data = liveBuffer
            liveNote = nil
            liveBuffer = Data()
            guard size > 0, data.count == size else {   // missed some: fetch it the normal way
                download(name)
                return
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                let wav = try? PendantOpus.wav(from: data)
                await MainActor.run {
                    guard let self else { return }
                    if let wav { self.onFileReceived?(name, wav) } else { self.download(name) }
                }
            }
        default:
            break
        }
    }

    private func resetLink() {
        // Out of range mid-recording: keep what we have; the pendant keeps recording and we
        // catch up when it's back. (Bluetooth off for good also lands here; that's fine.)
        if liveNote != nil { onLive?(.paused) }
        if liveHold != nil { liveHold = nil; onLive?(.incomplete) }
        liveJoined = false
        connected = false
        ctrl = nil
        current = nil
        downloading = nil
        pending = []
        listBuffer = []
        fileBuffer = Data()
    }
}

// MARK: - CoreBluetooth

extension PendantLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Looking for your pendant…"
            if let known = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]).first {
                connect(known)
            } else {
                central.scanForPeripherals(withServices: [Self.serviceUUID])
            }
        case .unauthorized:
            status = "Allow Bluetooth for Pendant in Settings"
        case .poweredOff:
            status = "Turn on Bluetooth"
            resetLink()
        default:
            status = "Bluetooth not available"
        }
    }

    private func connect(_ p: CBPeripheral) {
        central.stopScan()
        peripheral = p
        p.delegate = self
        status = "Connecting…"
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Couldn't connect, retrying…"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetLink()
        status = "Pendant out of range. Waiting for it…"
        central.connect(peripheral)   // iOS reconnects as soon as it's back
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.ctrlUUID, Self.dataUUID, Self.liveUUID], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == Self.ctrlUUID { ctrl = c }
            if c.uuid == Self.dataUUID || c.uuid == Self.liveUUID { peripheral.setNotifyValue(true, for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.dataUUID, characteristic.isNotifying else { return }
        connected = true
        status = "Connected"
        // Pendant keeps local time; send ours so note dates are right
        let local = Int(Date().timeIntervalSince1970) + TimeZone.current.secondsFromGMT()
        enqueue("T:\(local)")
        refreshList()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let v = characteristic.value else { return }
        if characteristic.uuid == Self.dataUUID { handle(v) }
        else if characteristic.uuid == Self.liveUUID { handleLive(v) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            status = "Write failed: \(error.localizedDescription)"
            finishCommand()
        }
    }
}
