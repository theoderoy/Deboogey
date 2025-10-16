//
//  ws_overlayAlert.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
import AppKit

enum ws_overlayAlertError: LocalizedError {
    case toolNotFound
    case toolOutsideResources(path: String)
    case toolNotExecutable(path: String)
    case scriptCreationFailed
    case executionFailed(userFacing: String, details: [String: Any])

    var errorDescription: String? {
        switch self {
        case .toolNotFound:
            return "ws_overlayHelper not found at Contents/Resources within the app bundle."
        case .toolOutsideResources(let path):
            return "Resolved tool path is not inside Contents/Resources. (path: \(path))"
        case .toolNotExecutable(let path):
            return "ws_overlayHelper exists but is not executable. (path: \(path))"
        case .scriptCreationFailed:
            return "Failed to create AppleScript for privileged execution."
        case .executionFailed(let userFacing, _):
            return userFacing
        }
    }
}

struct ws_overlayAlert {
    static func runOverlayHelper(arguments: [String]) throws -> String {
        if !Thread.isMainThread {
            return try DispatchQueue.main.sync { try ws_overlayAlert.runOverlayHelper(arguments: arguments) }
        }

        let alert = NSAlert()
        alert.messageText = "WindowServer Diagnostics"
        alert.informativeText = "Choose the overlay to enable.\n\nYou can stack these to see multiple diagnostics at once, but to revert back to stock, you'll have to kill WindowServer or log out."

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        let options: [(title: String, arg: String)] = [
            ("All", "all"),
            ("Contributor Screen", "contributor"),
            ("Foreground Tracking", "mouse"),
            ("Foreground Debugger", "foreground"),
            ("Framerate & Hang Sensors", "hang")
        ]
        popup.addItems(withTitles: options.map { $0.title })
        popup.selectItem(at: 0)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.setContentCompressionResistancePriority(.required, for: .horizontal)

        let accessory = NSView()
        accessory.translatesAutoresizingMaskIntoConstraints = false

        accessory.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            popup.topAnchor.constraint(equalTo: accessory.topAnchor),
            popup.bottomAnchor.constraint(equalTo: accessory.bottomAnchor)
        ])

        alert.accessoryView = accessory
        alert.alertStyle = .informational
        alert.layout()

        alert.addButton(withTitle: "Run")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            throw ws_overlayAlertError.executionFailed(userFacing: "Operation cancelled.", details: [:])
        }

        let selectedIndex = popup.indexOfSelectedItem
        let chosenArg = options[selectedIndex].arg

        let arguments = [chosenArg]

        guard let toolPath = Bundle.main.path(forResource: "ws_overlayHelper", ofType: nil) else {
            throw ws_overlayAlertError.toolNotFound
        }
        if !toolPath.contains("/Contents/Resources/") {
            throw ws_overlayAlertError.toolOutsideResources(path: toolPath)
        }
        if !FileManager.default.isExecutableFile(atPath: toolPath) {
            throw ws_overlayAlertError.toolNotExecutable(path: toolPath)
        }
        #if DEBUG
        print("[Deboogey] Using ws_overlayHelper at path:\n\(toolPath)")
        #endif

        @inline(__always)
        func shellEscape(_ s: String) -> String {
            "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        let escapedArgs = arguments.map(shellEscape).joined(separator: " ")
        let command = shellEscape("/usr/bin/env") + " " + shellEscape(toolPath) + (escapedArgs.isEmpty ? "" : " " + escapedArgs) + " 2>&1"
        let scriptSource = "do shell script \"" + command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\" with administrator privileges"

        guard let script = NSAppleScript(source: scriptSource) else {
            throw ws_overlayAlertError.scriptCreationFailed
        }

        var errorDict: NSDictionary? = nil
        let result = script.executeAndReturnError(&errorDict)

        if let output = result.stringValue { return output }

        if let errorDict = errorDict as? [String: Any] {
            let detailedMessage = (errorDict[NSAppleScript.errorMessage] as? String)
                ?? (errorDict[NSAppleScript.errorBriefMessage] as? String)
                ?? (errorDict[NSLocalizedDescriptionKey] as? String)
                ?? "Unknown AppleScript error"
            let number = (errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
            let userFacing = "Helper failed (code \(number)). \(detailedMessage)"

            var details: [String: Any] = [:]
            details["AppleScriptErrorNumber"] = number
            details["AppleScriptErrorMessage"] = errorDict[NSAppleScript.errorMessage] as Any
            details["AppleScriptErrorBriefMessage"] = errorDict[NSAppleScript.errorBriefMessage] as Any
            details["AppleScriptError"] = errorDict
            details["command"] = command
            details["toolPath"] = toolPath
            #if DEBUG
            print("[Deboogey] AppleScript error (\(number)): \(detailedMessage)\nDict: \(errorDict)\nCommand: \(command)\nTool: \(toolPath)")
            #endif
            throw ws_overlayAlertError.executionFailed(userFacing: userFacing, details: details)
        }

        throw ws_overlayAlertError.executionFailed(userFacing: "Failed to run ws_overlayHelper with administrator privileges.", details: [:])
    }
}
