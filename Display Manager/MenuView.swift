import SwiftUI

struct MenuView: View {
    @EnvironmentObject var monitorManager: MonitorManager
    @State private var brightnessLevels: [CGDirectDisplayID: Double] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // 1. Die Monitore und ihre Slider
            ForEach(monitorManager.displays) { display in
                VStack(alignment: .leading, spacing: 6) {
                    Text(display.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "sun.min")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Slider(
                            value: Binding(
                                get: { brightnessLevels[display.id] ?? display.brightness },
                                set: { newValue in
                                    brightnessLevels[display.id] = newValue
                                    monitorManager.setBrightness(for: display.id, value: newValue)
                                }
                            ),
                            in: 0...100
                        )
                        .controlSize(.small)
                        
                        Image(systemName: "sun.max")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // 2. Die runden Kontrollzentrum-Buttons (Genau wie in deinem Bild)
            HStack(alignment: .top) {
                Spacer()
                
                // Dunkelmodus (Design-Platzhalter)
                FeatureButton(
                    icon: "circle.lefthalf.filled",
                    title: "Dunkelmodus",
                    subtitle: "Aus",
                    isActive: false
                ) {
                    // Optional: NSAppearance Logik
                }
                
                Spacer()
                
                // Night Shift (Design-Platzhalter)
                FeatureButton(
                    icon: "sun.max.fill",
                    title: "Night Shift",
                    subtitle: "Aus",
                    isActive: false
                ) {
                    // Optional: CoreBrightness Logik
                }
                
                Spacer()
                
                // DEIN AUTO-HELLIGKEIT BUTTON
                FeatureButton(
                    icon: "sun.max.circle.fill",
                    title: "Auto-Helligkeit",
                    subtitle: monitorManager.isAutoSyncEnabled ? "Ein" : "Aus",
                    isActive: monitorManager.isAutoSyncEnabled
                ) {
                    monitorManager.isAutoSyncEnabled.toggle()
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
            
            Divider()
            
            SettingsLink {
                Text("Einstellungen ...")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Beenden-Button
            HStack {
                Spacer()
                Button("Beenden") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            refreshLevels()
        }
        .onChange(of: monitorManager.displays) {
            refreshLevels()
        }
    }
    
    private func refreshLevels() {
        for display in monitorManager.displays {
            brightnessLevels[display.id] = display.brightness
        }
    }
}

// MARK: - Hilfs-View für die runden Buttons (mit Action-Support)
struct FeatureButton: View {
    var icon: String
    var title: String
    var subtitle: String
    var isActive: Bool
    var action: () -> Void = {}
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.blue : Color.primary.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(isActive ? .white : .primary)
                }
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(width: 90)
        }
        .buttonStyle(.plain)
    }
}
