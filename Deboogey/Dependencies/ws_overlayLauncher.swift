//
//  ws_overlayLauncher.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
import AppKit

enum ws_overlayLauncherError: LocalizedError {
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

struct ws_overlayLauncher {
    static func runOverlayHelper(arguments: [String]) throws -> String {
        if !Thread.isMainThread {
            return try DispatchQueue.main.sync { try ws_overlayLauncher.runOverlayHelper(arguments: arguments) }
        }

        guard let toolPath = Bundle.main.path(forResource: "ws_overlayHelper", ofType: nil) else {
            throw ws_overlayLauncherError.toolNotFound
        }
        if !toolPath.contains("/Contents/Resources/") {
            throw ws_overlayLauncherError.toolOutsideResources(path: toolPath)
        }
        if !FileManager.default.isExecutableFile(atPath: toolPath) {
            throw ws_overlayLauncherError.toolNotExecutable(path: toolPath)
        }

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
            throw ws_overlayLauncherError.scriptCreationFailed
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
            throw ws_overlayLauncherError.executionFailed(userFacing: userFacing, details: details)
        }

        throw ws_overlayLauncherError.executionFailed(userFacing: "Failed to run ws_overlayHelper with administrator privileges.", details: [:])
    }
}
