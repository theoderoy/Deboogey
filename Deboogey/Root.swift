//
//  Root.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI
import AppKit
import Security

public private(set) var isSIPSatisfied: Bool = true

private struct UpgradeCommands: Commands {
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    @ObservedObject var upgradeChecker = UpgradeChecker.shared
    
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if #available(macOS 13.0, *) {
                Button(
                    upgradeChecker.upgradeAvailable ? "Upgrade to \(upgradeChecker.formattedLatestVersion)" : "Check for Upgrades...",
                    systemImage: networkMonitor.isConnected ? "network" : "network.slash"
                ) { 
                    UpgradeChecker.shared.requestManualCheck() 
                }
                .disabled(!networkMonitor.isConnected)
            } else if #available(macOS 11.0, *) {
                Button(upgradeChecker.upgradeAvailable ? "Upgrade to \(upgradeChecker.formattedLatestVersion)" : "Check for Upgrades...") { 
                    UpgradeChecker.shared.requestManualCheck() 
                }
                .disabled(!networkMonitor.isConnected)
            } else {
                Button("Check for Upgrades...") { 
                    UpgradeChecker.shared.requestManualCheck() 
                }
                .disabled(!networkMonitor.isConnected)
            }
            
            if !networkMonitor.isConnected {
                Text("Network connection required")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct SceneSwitcher: Scene {
    @SceneBuilder
    var body: some Scene {
        ConfigurationLegacy()

        if #available(macOS 14.0, *) {
            ConfigurationModern()
        }

        if #available(macOS 13.0, *) {
            LadybugLauncherScene()
            WsOverlayLauncherScene()
            EntityTrackerScene()
        }
    }
}

@available(macOS 13.0, *)
private struct LadybugLauncherScene: Scene {
    var body: some Scene {
        Window("Cocoa Debug Menu", id: "ladybug-launcher") {
            NavigationStack {
                LadybugLauncherView { arguments in
                    EntityTracker.shared.record(source: .ladybug, arguments: arguments)
                }
            }
        }
        .commandsRemoved()
        .defaultSize(width: 520, height: 650)
        .windowResizability(.contentSize)
    }
}

@available(macOS 13.0, *)
private struct WsOverlayLauncherScene: Scene {
    var body: some Scene {
        Window("SkyLight Diagnostics", id: "ws-overlay-launcher") {
            NavigationStack {
                ws_overlayLauncherView { argument in
                    EntityTracker.shared.record(source: .wsOverlay, arguments: [argument])
                }
            }
        }
        .commandsRemoved()
        .defaultSize(width: 520, height: 540)
        .windowResizability(.contentSize)
    }
}

@available(macOS 13.0, *)
private struct EntityTrackerScene: Scene {
    var body: some Scene {
        Window("Entity Tracker", id: "entity-tracker") {
            NavigationStack {
                EntityTrackerView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 560, height: 480)
        .windowResizability(.contentSize)
    }
}

@available(macOS 13.0, *)
struct ConfigurationModern: Scene {
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Settings", id: "settings") {
            ConfigurationRootView()
        }
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Configuration", systemImage: "gear") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

struct ConfigurationLegacy: Scene {
    var body: some Scene {
        Settings {
            ConfigurationRootView()
        }
    }
}

@main
struct Root: App {
    @State private var sipSatisfied: Bool = true

    init() {
        csrutilChecker.refreshSIPStatus()
        self._sipSatisfied = State(initialValue: isSIPSatisfied)
        print("csrutil: \(isSIPSatisfied)")

        if UserDefaults.standard.bool(forKey: "deboogey.entityTracker.autoDeleteEnabled") {
            let scope = UserDefaults.standard.string(forKey: "deboogey.entityTracker.autoDeleteScope") ?? "ephemerals"
            let trigger = UserDefaults.standard.string(forKey: "deboogey.entityTracker.autoDeleteTrigger") ?? "login"

            let shouldDelete: Bool
            if trigger == "launch" {
                shouldDelete = true
            } else {
                // "login" — only delete once per macOS login session.
                let sessionKey = "deboogey.entityTracker.lastKnownSessionID"
                let currentSession = loginSessionID()
                let storedSession = UserDefaults.standard.string(forKey: sessionKey)
                if let current = currentSession {
                    if storedSession == nil {
                        // First time the setting is active — record session, don't delete yet.
                        UserDefaults.standard.set(current, forKey: sessionKey)
                        shouldDelete = false
                    } else if current != storedSession {
                        UserDefaults.standard.set(current, forKey: sessionKey)
                        shouldDelete = true
                    } else {
                        shouldDelete = false
                    }
                } else {
                    shouldDelete = false
                }
            }

            if shouldDelete {
                switch scope {
                case "ephemerals": EntityTracker.shared.removeEphemerals()
                case "all":        EntityTracker.shared.removeAll()
                default: break
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.sipSatisfied, sipSatisfied)
        }
        .commands {
            UpgradeCommands()
        }

        SceneSwitcher()
    }
}

private struct SIPSatisfiedKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var sipSatisfied: Bool {
        get { self[SIPSatisfiedKey.self] }
        set { self[SIPSatisfiedKey.self] = newValue }
    }
}

private func loginSessionID() -> String? {
    var sessionID: SecuritySessionId = 0
    var attrs = SessionAttributeBits(rawValue: 0)
    guard SessionGetInfo(callerSecuritySession, &sessionID, &attrs) == errSecSuccess else { return nil }
    return String(sessionID)
}

private enum csrutilChecker {
    static func refreshSIPStatus() {
        let path = "/usr/bin/csrutil"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            isSIPSatisfied = true
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            isSIPSatisfied = true
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.lowercased() else {
            isSIPSatisfied = true
            return
        }

        if !output.contains("enabled") && output.contains("disabled") {
            isSIPSatisfied = false
            return
        }

        if output.contains("debugging restrictions: disabled") {
            isSIPSatisfied = false
            return
        }
        isSIPSatisfied = true
    }
}
