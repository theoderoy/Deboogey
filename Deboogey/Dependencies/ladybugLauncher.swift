//
//  ladybugLauncher.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation

enum ladybugLauncherError: LocalizedError {
    case toolNotFound
    case toolOutsideResources(path: String)
    case toolNotExecutable(path: String)
    case invalidBundleIdentifier(String)
    case executionFailed(userFacing: String, details: [String: Any])
    var errorDescription: String? {
        switch self {
        case .toolNotFound: return "deboogeyLadybugHelper not found at Contents/Resources within the app bundle."
        case .toolOutsideResources(let path): return "Resolved tool path is not inside Contents/Resources. (path: \(path))"
        case .toolNotExecutable(let path): return "deboogeyLadybugHelper exists but is not executable. (path: \(path))"
        case .invalidBundleIdentifier(let id): return "Invalid bundle identifier: \(id)"
        case .executionFailed(let userFacing, _): return userFacing
        }
    }
}

struct ladybugLauncher {
    static func runLadybugHelper(arguments: [String]) throws -> String {
        guard arguments.count == 2 else {
            throw ladybugLauncherError.executionFailed(userFacing: "Invalid arguments.", details: ["arguments": arguments])
        }

        let action = arguments[0]
        guard action == "enable" || action == "disable" else {
            throw ladybugLauncherError.executionFailed(userFacing: "Invalid arguments.", details: ["arguments": arguments])
        }

        let domain = arguments[1]
        if domain != "global" {
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
            if trimmed.isEmpty || !trimmed.contains(".") || trimmed.rangeOfCharacter(from: allowedChars.inverted) != nil {
                throw ladybugLauncherError.invalidBundleIdentifier(domain)
            }
        }

        guard let toolPath = Bundle.main.path(forResource: "deboogeyLadybugHelper", ofType: nil) else {
            throw ladybugLauncherError.toolNotFound
        }
        if !toolPath.contains("/Contents/Resources/") {
            throw ladybugLauncherError.toolOutsideResources(path: toolPath)
        }
        if !FileManager.default.isExecutableFile(atPath: toolPath) {
            throw ladybugLauncherError.toolNotExecutable(path: toolPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ladybugLauncherError.executionFailed(userFacing: "Failed to launch deboogeyLadybugHelper.", details: ["error": error.localizedDescription])
        }
        process.waitUntilExit()

        let stdoutStr = String(data: (process.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrStr = String(data: (process.standardError as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ladybugLauncherError.executionFailed(
                userFacing: "Helper failed (code \(process.terminationStatus)). \(stderrStr.isEmpty ? stdoutStr : stderrStr)",
                details: [
                    "terminationStatus": Int(process.terminationStatus),
                    "stdout": stdoutStr,
                    "stderr": stderrStr,
                    "args": arguments,
                    "toolPath": toolPath
                ])
        }

        return stdoutStr.isEmpty ? stderrStr : stdoutStr
    }
}
