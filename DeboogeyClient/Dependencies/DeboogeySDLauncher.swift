//
//  DeboogeySDLauncher.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
import AppKit

enum DeboogeySDLauncherError: LocalizedError {
    case toolNotFound
    case toolOutsideResources(path: String)
    case toolNotExecutable(path: String)
    case scriptCreationFailed
    case executionFailed(userFacing: String, details: [String: Any])

    var errorDescription: String? {
        switch self {
        case .toolNotFound:
            return L10n.t("DeboogeySDHelper not found at Contents/Resources within the app bundle.")
        case .toolOutsideResources(let path):
            return L10n.f("Resolved tool path is not inside Contents/Resources. (path: %@)", path)
        case .toolNotExecutable(let path):
            return L10n.f("DeboogeySDHelper exists but is not executable. (path: %@)", path)
        case .scriptCreationFailed:
            return L10n.t("Failed to create AppleScript for privileged execution.")
        case .executionFailed(let userFacing, _):
            return userFacing
        }
    }
}

struct DeboogeySDLauncher {
    static func runOverlayHelper(arguments: [String]) throws -> String {
        if !Thread.isMainThread {
            return try DispatchQueue.main.sync { try DeboogeySDLauncher.runOverlayHelper(arguments: arguments) }
        }

        guard let toolPath = Bundle.main.path(forResource: "DeboogeySDHelper", ofType: nil) else {
            throw DeboogeySDLauncherError.toolNotFound
        }
        if !toolPath.contains("/Contents/Resources/") {
            throw DeboogeySDLauncherError.toolOutsideResources(path: toolPath)
        }
        if !FileManager.default.isExecutableFile(atPath: toolPath) {
            throw DeboogeySDLauncherError.toolNotExecutable(path: toolPath)
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
            throw DeboogeySDLauncherError.scriptCreationFailed
        }

        var errorDict: NSDictionary? = nil
        let result = script.executeAndReturnError(&errorDict)

        if let output = result.stringValue { return output }

        if let errorDict = errorDict as? [String: Any] {
            let detailedMessage = (errorDict[NSAppleScript.errorMessage] as? String)
                ?? (errorDict[NSAppleScript.errorBriefMessage] as? String)
                ?? (errorDict[NSLocalizedDescriptionKey] as? String)
                ?? L10n.t("Unknown AppleScript error")
            let number = (errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
            let userFacing = L10n.f("Helper failed (code %d). %@", number, detailedMessage)

            var details: [String: Any] = [:]
            details["AppleScriptErrorNumber"] = number
            details["AppleScriptErrorMessage"] = errorDict[NSAppleScript.errorMessage] as Any
            details["AppleScriptErrorBriefMessage"] = errorDict[NSAppleScript.errorBriefMessage] as Any
            details["AppleScriptError"] = errorDict
            details["command"] = command
            details["toolPath"] = toolPath
            #if DEBUG
            print("[DeboogeyClient] AppleScript error (\(number)): \(detailedMessage)\nDict: \(errorDict)\nCommand: \(command)\nTool: \(toolPath)")
            #endif
            throw DeboogeySDLauncherError.executionFailed(userFacing: userFacing, details: details)
        }

        throw DeboogeySDLauncherError.executionFailed(userFacing: L10n.t("Failed to run DeboogeySDHelper with administrator privileges."), details: [:])
    }
}
