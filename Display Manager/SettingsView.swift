//
//  SettingsView.swift
//  DisplayManager
//
//  Created by Semih Erikli on 12.05.26.
//

import SwiftUI

struct SettingsView: View {
    // 1. Wir holen uns den Manager aus der Umgebung
    @EnvironmentObject var monitorManager: MonitorManager
    
    var body: some View {
        TabView {
            Form {
                Toggle("Beim Login starten", isOn: .constant(true))
                Text("Hier kommen später die DDC-Optionen hin.")
            }
            .tabItem {
                Label("Allgemein", systemImage: "gearshape")
            }
            
            // 2. Hier zeigen wir die gefundenen Monitore an
            List(monitorManager.displays) { display in
                HStack {
                    // Prüft auf englische UND deutsche Begriffe für interne Displays
                    let isBuiltIn = display.name.contains("Built-in") || display.name.contains("Integriert") || display.name.contains("LCD")
                    
                    Image(systemName: isBuiltIn ? "laptopcomputer" : "display")
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading) {
                        Text(display.name)
                            .font(.body)
                        Text("ID: \(display.id)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)
            }
            .tabItem {
                Label("Monitore", systemImage: "display")
            }
        }
        .frame(width: 400, height: 200)
        .padding()
        .onAppear {
            // 3. Jetzt werden die Monitore sofort gesucht, sobald das Fenster aufgeht
            monitorManager.fetchDisplays()
        }
    }
}
