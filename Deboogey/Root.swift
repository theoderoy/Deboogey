//
//  DeboogeyApp.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI

public struct csrutilFeatures {
    public static var isSIPEnabled: Bool = true
}

@main
struct Root: App {
    @State private var sipEnabled: Bool = true

    init() {
        let isEnabled = csrutilChecker.isSIPEnabled()
        csrutilFeatures.isSIPEnabled = isEnabled
        print("csrutil: \(isEnabled)")
        self._sipEnabled = State(initialValue: isEnabled)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.sipEnabled, sipEnabled)
        }
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
    static func isSIPEnabled() -> Bool {
        let path = "/usr/bin/csrutil"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return true
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
            return true
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.lowercased() else {
            return true
        }

        if output.contains("enabled") && !output.contains("disabled") {
            return true
        }
        if output.contains("disabled") {
            return false
        }
        return true
    }
}
