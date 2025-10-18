//
//  ladybugLauncher.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation

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
        #if DEBUG
        print("[Deboogey] Using deboogeyLadybugHelper at path:\n\(toolPath)")
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw ladybugLauncherError.executionFailed(userFacing: "Failed to start helper.", details: ["error": String(describing: error)])
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ladybugLauncherError.executionFailed(userFacing: "Failed to read helper output.", details: [:])
        }

        if process.terminationStatus != 0 {
            throw ladybugLauncherError.executionFailed(userFacing: "Helper failed.", details: ["output": output])
        }

        return output
    }
}
