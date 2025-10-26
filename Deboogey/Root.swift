//
//  Root.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI
import AppKit

public private(set) var isSIPEnabled: Bool = true

@main
struct Root: App {
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
