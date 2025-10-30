//
//  Root.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI
import AppKit

public private(set) var isSIPEnabled: Bool = true

private struct SceneSwitcher: Scene {
    @SceneBuilder
    var body: some Scene {
        ConfigurationLegacy()

        if #available(macOS 14.0, *) {
            ConfigurationModern()
        }
    }
}

struct ConfigurationModern: Scene {
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Settings", id: "settings") {
            ConfigurationRootView()
        }

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
    @Environment(\.openWindow) private var openWindow
    @State private var sipEnabled: Bool = true

    init() {
        csrutilChecker.refreshSIPStatus()
        self._sipEnabled = State(initialValue: isSIPEnabled)
        print("csrutil: \(sipEnabled)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.sipEnabled, sipEnabled)
        }
        
        SceneSwitcher()
    }
}

private struct SIPEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var sipEnabled: Bool {
        get { self[SIPEnabledKey.self] }
        set { self[SIPEnabledKey.self] = newValue }
    }
}

private enum csrutilChecker {
    static func refreshSIPStatus() {
        let path = "/usr/bin/csrutil"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            isSIPEnabled = true
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
            isSIPEnabled = true
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.lowercased() else {
            isSIPEnabled = true
            return
        }

        if output.contains("enabled") && !output.contains("disabled") {
            isSIPEnabled = true
            return
        }
        if output.contains("disabled") {
            isSIPEnabled = false
            return
        }
        isSIPEnabled = true
    }
}
