//
//  MonitorManager.swift
//  DisplayManager
//

import Foundation
import CoreGraphics
import Combine
import AppKit

// --- APPLE SILICON SECRET API (Für externe Monitore über M-Chips) ---
typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreate")
func IOAVServiceCreate(_ allocator: CFAllocator?, _ displayID: CGDirectDisplayID) -> IOAVService?

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32, _ data: UnsafeRawPointer, _ dataLength: UInt32) -> kern_return_t

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32, _ data: UnsafeMutableRawPointer, _ dataLength: UInt32) -> kern_return_t

// --------------------------------------------------------------------

// --- APPLE NATIVE API TYPEN (Für internes MacBook Display) ---
typealias DisplayServicesSetBrightnessType = @convention(c) (CGDirectDisplayID, Float) -> Int32
typealias DisplayServicesGetBrightnessType = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
// -------------------------------------------------------------

struct DisplayDevice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    var brightness: Double
}

class MonitorManager: ObservableObject {
    @Published var displays: [DisplayDevice] = []
    
    @Published var isAutoSyncEnabled: Bool = true {
            didSet {
                // Speichert die Einstellung direkt in den macOS-Benutzereinstellungen
                UserDefaults.standard.set(isAutoSyncEnabled, forKey: "isAutoSyncEnabled")
            }
        }
    
    private var setBrightnessFunc: DisplayServicesSetBrightnessType?
    private var getBrightnessFunc: DisplayServicesGetBrightnessType?
    private var lastSendTime: [CGDirectDisplayID: Date] = [:]
    private var pendingTasks: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private let throttleInterval: TimeInterval = 0.04
    
    // Timer für den Echtzeit-Sync
    private var syncTimer: Timer?
    private var lastKnownInternalBrightness: Double = -1.0

    init() {
        // 1. Apple Dienste laden
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) {
            setBrightnessFunc = unsafeBitCast(dlsym(handle, "DisplayServicesSetBrightness"), to: DisplayServicesSetBrightnessType.self)
            getBrightnessFunc = unsafeBitCast(dlsym(handle, "DisplayServicesGetBrightness"), to: DisplayServicesGetBrightnessType.self)
        }
        self.isAutoSyncEnabled = UserDefaults.standard.object(forKey: "isAutoSyncEnabled") as? Bool ?? true
        // 2. Den Timer starten: Prüft alle 0,2 Sekunden
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkAndSync()
        }
        
        // Initialer Scan
        fetchDisplays()
    }

    private func checkAndSync() {
        let maxDisplays: UInt32 = 10
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        
        guard CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount) == .success else { return }
        let ids = Array(activeDisplays.prefix(Int(displayCount)))
        
        // Suche das interne Display
        guard let builtinID = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return }
        let currentInternal = getCurrentBrightness(for: builtinID)
        
        // NUR wenn sich die Helligkeit geändert hat
        if abs(currentInternal - lastKnownInternalBrightness) > 0.5 {
            print("Änderung erkannt: \(currentInternal)%")
            lastKnownInternalBrightness = currentInternal
            
            DispatchQueue.main.async {
                // 1. Liste für UI aktualisieren
                self.fetchDisplays()
                
                
                // NUR wenn der Schalter an ist, senden wir an externe Monitore
                if self.isAutoSyncEnabled {
                    for id in ids where CGDisplayIsBuiltin(id) == 0 {
                        self.setBrightness(for: id, value: currentInternal)
                    }
                }
                
                self.objectWillChange.send()
            }
        }
    }
    
    func fetchDisplays() {
        let maxDisplays: UInt32 = 10
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        
        if CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount) == .success {
            let ids = Array(activeDisplays.prefix(Int(displayCount)))
            self.displays = ids.map { id in
                DisplayDevice(id: id, name: getDisplayName(for: id), brightness: self.getCurrentBrightness(for: id))
            }
        }
    }
    
    private func getCurrentBrightness(for displayID: CGDirectDisplayID) -> Double {
        if CGDisplayIsBuiltin(displayID) != 0 {
            var brightness: Float = 0.5
            _ = getBrightnessFunc?(displayID, &brightness)
            return Double(brightness * 100.0)
        } else {
            return getExternalBrightness(for: displayID)
        }
    }

    // ... hier deine getExternalBrightness, setBrightness und executeDDCWrite Funktionen behalten ...
    
    // NEU: Die Hardware-Funktion zum Auslesen von externen Monitoren
    private func getExternalBrightness(for displayID: CGDirectDisplayID) -> Double {
        guard let avService = IOAVServiceCreate(kCFAllocatorDefault, displayID) else { return 50.0 }
        
        // 1. Lese-Anfrage an den Monitor senden (Gib mir deinen Wert für Helligkeit 0x10)
        var writeData: [UInt8] = [
            0x82, // Länge (Flag 0x80 + 2 Bytes Daten)
            0x01, // Befehl: Get VCP Feature
            0x10  // VCP Code: Helligkeit
        ]
        
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in writeData { checksum ^= byte }
        writeData.append(checksum)
        
        let writeResult = IOAVServiceWriteI2C(avService, 0x37, 0x51, &writeData, UInt32(writeData.count))
        
        if writeResult != KERN_SUCCESS {
            print("DDC Read-Anfrage blockiert für ID \(displayID)")
            return 50.0 // Fallback
        }
        
        // 2. WICHTIG: Der Monitor ist langsam. Wir müssen warten, bevor wir die Antwort abholen!
        usleep(40000) // 40 Millisekunden Pause
        
        // 3. Antwort abholen (Ein DDC-Reply Paket ist exakt 11 Bytes lang)
        var readData = [UInt8](repeating: 0, count: 11)
        let readResult = IOAVServiceReadI2C(avService, 0x37, 0x51, &readData, UInt32(readData.count))
        
        if readResult == KERN_SUCCESS {
            // Ein gültiges Antwort-Paket hat an Stelle 2 den Reply-Code (0x02)
            // und an Stelle 4 unseren angefragten VCP-Code (0x10).
            if readData.count >= 10 && readData[2] == 0x02 && readData[4] == 0x10 {
                
                // Der aktuelle Wert versteckt sich an Index 9 (Low Byte)
                let currentValue = Double(readData[9])
                print("Erfolg! Externer Monitor \(displayID) steht aktuell auf \(currentValue)%")
                return currentValue
            }
        }
        
        print("Konnte externen Monitor nicht auslesen (Rückkanal blockiert?). Nutze 50%.")
        return 50.0
    }
    
    private func getDisplayName(for displayID: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first { screen in
            let description = screen.deviceDescription
            if let id = description[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                return id == displayID
            }
            return false
        }
        return screen?.localizedName ?? "Externer Monitor (\(displayID))"
    }
    
    func setBrightness(for displayID: CGDirectDisplayID, value: Double) {
        // --- WEICHE: IST ES DER INTERNE MAC-BILDSCHIRM? ---
        if CGDisplayIsBuiltin(displayID) != 0 {
            if let setFunc = setBrightnessFunc {
                _ = setFunc(displayID, Float(value / 100.0))
            }
            return // Wichtig: Hier abbrechen, keine DDC-Befehle ans MacBook!
        }
        
        // --- EXTERNER MONITOR (DDC LOGIK MIT THROTTLER) ---
        let safeValue = UInt8(max(0, min(100, Int(value))))
        let now = Date()
        let lastTime = lastSendTime[displayID] ?? .distantPast
        
        // Vorherige verzögerte Befehle abbrechen
        pendingTasks[displayID]?.cancel()
        
        if now.timeIntervalSince(lastTime) >= throttleInterval {
            // Drosselung: Wir dürfen sofort senden
            lastSendTime[displayID] = now
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.executeDDCWrite(displayID: displayID, value: safeValue)
            }
        } else {
            // Drosselung: Wir ziehen den Slider extrem schnell, warten kurz ab
            let timeToWait = throttleInterval - now.timeIntervalSince(lastTime)
            let task = DispatchWorkItem { [weak self] in
                self?.lastSendTime[displayID] = Date()
                self?.executeDDCWrite(displayID: displayID, value: safeValue)
            }
            pendingTasks[displayID] = task
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeToWait, execute: task)
        }
    }
    
    // Die reine Hardware-Kommunikation zum Dell/LG etc.
    private func executeDDCWrite(displayID: CGDirectDisplayID, value: UInt8) {
        guard let avService = IOAVServiceCreate(kCFAllocatorDefault, displayID) else { return }
        
        var ddcData: [UInt8] = [
            0x84,       // Länge (0x80 Flag + 4 Bytes)
            0x03,       // Befehl: Set VCP
            0x10,       // VCP Code: Helligkeit
            0x00,       // High Byte
            value       // Low Byte (Helligkeit)
        ]
        
        // Checksumme berechnen (XOR)
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in ddcData {
            checksum ^= byte
        }
        ddcData.append(checksum)
        
        // Hardware-Schreibvorgang an den M-Chip Coprozessor
        _ = IOAVServiceWriteI2C(avService, 0x37, 0x51, &ddcData, UInt32(ddcData.count))
    }
}
