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

nonisolated struct DeboogeySDLauncher {
    static func runOverlayHelper(arguments: [String]) throws -> String {
        if !Thread.isMainThread {
            return try DispatchQueue.main.sync { try DeboogeySDLauncher.runOverlayHelper(arguments: arguments) }
        }

        do {
            return try runOverlayHelperImpl(arguments: arguments)
        } catch {
            ToolCycleFeedback.playHalt()
            throw error
        }
    }

    private static func runOverlayHelperImpl(arguments: [String]) throws -> String {
        let toolPath = try BundleHelperTool.pathMapped(
            resource: "DeboogeySDHelper",
            expectedDirectory: "/Contents/Resources/"
        ) { error in
            switch error {
            case .notFound: return DeboogeySDLauncherError.toolNotFound
            case .outsideExpectedDirectory(let path): return DeboogeySDLauncherError.toolOutsideResources(path: path)
            case .notExecutable(let path): return DeboogeySDLauncherError.toolNotExecutable(path: path)
            }
        }

        let escapedArgs = arguments.map(PrivilegedShell.quoted).joined(separator: " ")
        let command = PrivilegedShell.quoted("/usr/bin/env")
            + " " + PrivilegedShell.quoted(toolPath)
            + (escapedArgs.isEmpty ? "" : " " + escapedArgs)
            + " 2>&1"

        do {
            let output = try PrivilegedShell.runAdministrator(command: command)
            ToolCycleFeedback.playComplete()
            return output
        } catch PrivilegedShell.ExecutionError.scriptCreationFailed {
            throw DeboogeySDLauncherError.scriptCreationFailed
        } catch PrivilegedShell.ExecutionError.executionFailed(let message, let number, let details) {
            let detailedMessage = message ?? L10n.t("Unknown AppleScript error")
            let userFacing = L10n.f("Helper failed (code %d). %@", number, detailedMessage)
            var fullDetails: [String: Any] = details
            fullDetails["AppleScriptErrorNumber"] = number
            fullDetails["command"] = command
            fullDetails["toolPath"] = toolPath
            #if DEBUG
            print("[DeboogeyClient] AppleScript error (\(number)): \(detailedMessage)\nCommand: \(command)\nTool: \(toolPath)")
            #endif
            throw DeboogeySDLauncherError.executionFailed(userFacing: userFacing, details: fullDetails)
        } catch {
            throw DeboogeySDLauncherError.executionFailed(
                userFacing: L10n.t("Failed to run DeboogeySDHelper with administrator privileges."),
                details: [:]
            )
        }
    }
}
