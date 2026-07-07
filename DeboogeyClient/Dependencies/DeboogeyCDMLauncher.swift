//
//  DeboogeyCDMLauncher.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
import AppKit

enum DeboogeyCDMLauncherError: LocalizedError {
    case invalidArguments(userFacing: String, details: [String: Any])
    case toolNotFound
    case toolOutsideResources(path: String)
    case toolNotExecutable(path: String)
    case processStartFailed(details: [String: Any])
    case executionFailed(userFacing: String, details: [String: Any])

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let userFacing, _):
            return userFacing
        case .toolNotFound:
            return L10n.t("DeboogeyCDMHelper not found at Contents/Resources within the app bundle.")
        case .toolOutsideResources(let path):
            return L10n.f("Resolved tool path is not inside Contents/Resources. (path: %@)", path)
        case .toolNotExecutable(let path):
            return L10n.f("DeboogeyCDMHelper exists but is not executable. (path: %@)", path)
        case .processStartFailed:
            return L10n.t("Failed to start helper.")
        case .executionFailed(let userFacing, _):
            return userFacing
        }
    }
}

struct DeboogeyCDMLauncher {
    static func runDeboogeyCDMHelper(arguments: [String]) throws -> String {
        guard arguments.count == 2 || arguments.count == 3 else {
            throw DeboogeyCDMLauncherError.invalidArguments(userFacing: L10n.t("Invalid arguments. Expected: enable|disable <bundle-id|global> [--autokill]"), details: ["arguments": arguments])
        }

        let action = arguments[0]
        guard action == "enable" || action == "disable" else {
            throw DeboogeyCDMLauncherError.invalidArguments(userFacing: L10n.t("Invalid arguments. First argument must be 'enable' or 'disable'"), details: ["arguments": arguments])
        }

        let domain = arguments[1]

        if arguments.count == 3 {
            guard arguments[2] == "--autokill" else {
                throw DeboogeyCDMLauncherError.invalidArguments(userFacing: L10n.f("Invalid arguments. Unknown flag: %@", arguments[2]), details: ["arguments": arguments])
            }
        }
        
        guard let toolPath = Bundle.main.path(forResource: "DeboogeyCDMHelper", ofType: nil) else {
            throw DeboogeyCDMLauncherError.toolNotFound
        }
        if !toolPath.contains("/Contents/Resources/") {
            throw DeboogeyCDMLauncherError.toolOutsideResources(path: toolPath)
        }
        if !FileManager.default.isExecutableFile(atPath: toolPath) {
            throw DeboogeyCDMLauncherError.toolNotExecutable(path: toolPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var collectedStdout = Data()
        var collectedStderr = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                collectedStdout.append(data)
                if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                    print(chunk, terminator: "")
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                collectedStderr.append(data)
                FileHandle.standardError.write(data)
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw DeboogeyCDMLauncherError.processStartFailed(details: ["error": String(describing: error)])
        }
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingOut.isEmpty { collectedStdout.append(remainingOut) }
        let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingErr.isEmpty { collectedStderr.append(remainingErr) }

        let stdout = String(data: collectedStdout, encoding: .utf8) ?? ""
        let stderr = String(data: collectedStderr, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let status = Int(process.terminationStatus)
            let userFacing: String
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userFacing = L10n.f("Helper failed (code %d). %@", status, stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            } else if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userFacing = L10n.f("Helper failed (code %d). %@", status, stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                userFacing = L10n.f("Helper failed (code %d).", status)
            }

            var details: [String: Any] = [:]
            details["stdout"] = stdout
            details["stderr"] = stderr
            details["status"] = status
            details["arguments"] = arguments
            details["toolPath"] = toolPath
            #if DEBUG
            print("[DeboogeyCDMHelper] Exit status: \(status). Args: \(arguments)\nSTDERR:\n\(stderr)\nSTDOUT:\n\(stdout)")
            #endif

            throw DeboogeyCDMLauncherError.executionFailed(userFacing: userFacing, details: details)
        }

        return stdout
    }
}
