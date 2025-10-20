//
//  ladybugLauncher.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
import AppKit

struct ladybugLauncherError: Error {
    static func executionFailed(userFacing: String, details: [String: Any]) -> ladybugLauncherError {
        return ladybugLauncherError()
    }
}

struct ladybugLauncher {
    static func runLadybugHelper(arguments: [String]) throws -> String {
        guard arguments.count == 2 || arguments.count == 3 else {
            throw ladybugLauncherError.executionFailed(userFacing: "Invalid arguments. Expected: enable|disable <bundle-id|global> [--autokill]", details: ["arguments": arguments])
        }

        let action = arguments[0]
        guard action == "enable" || action == "disable" else {
            throw ladybugLauncherError.executionFailed(userFacing: "Invalid arguments. First argument must be 'enable' or 'disable'", details: ["arguments": arguments])
        }

        let domain = arguments[1]

        if arguments.count == 3 {
            guard arguments[2] == "--autokill" else {
                throw ladybugLauncherError.executionFailed(userFacing: "Invalid arguments. Unknown flag: \(arguments[2])", details: ["arguments": arguments])
            }
        }
        
        guard let toolPath = Bundle.main.path(forResource: "deboogeyLadybugHelper", ofType: nil) else {
            throw ws_overlayAlertError.toolNotFound
        }
        if !toolPath.contains("/Contents/Resources/") {
            throw ws_overlayAlertError.toolOutsideResources(path: toolPath)
        }
        if !FileManager.default.isExecutableFile(atPath: toolPath) {
            throw ws_overlayAlertError.toolNotExecutable(path: toolPath)
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
            throw ladybugLauncherError.executionFailed(userFacing: "Failed to start helper.", details: ["error": String(describing: error)])
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
            if !stderr.isEmpty {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Helper Error"
                alert.informativeText = stderr
                alert.addButton(withTitle: "OK")
                if let window = NSApp.keyWindow {
                    alert.beginSheetModal(for: window) { _ in }
                } else if let window = NSApp.mainWindow {
                    alert.beginSheetModal(for: window) { _ in }
                } else {
                    alert.runModal()
                }
            }
            if !stdout.isEmpty {
                print("[deboogeyLadybugHelper][stdout]:\n\(stdout)")
            }
            print("[deboogeyLadybugHelper] Exit status: \(process.terminationStatus). Args: \(arguments)")

            throw ladybugLauncherError.executionFailed(
                userFacing: "Helper failed.",
                details: [
                    "stdout": stdout,
                    "stderr": stderr,
                    "status": Int(process.terminationStatus),
                    "arguments": arguments
                ]
            )
        }

        return stdout
    }
}
