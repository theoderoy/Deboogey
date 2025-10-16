//
//  main.swift
//  ws_overlayHelper
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
import os.log

// MARK: - Call Injection

struct OverlayEnabler {
    static func resolveWindowServerPID() -> Int32? {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "WindowServer"]

        let outPipe = Pipe()
        pgrep.standardOutput = outPipe
        pgrep.standardError = Pipe()

        do { try pgrep.run() } catch { return resolvePIDViaPS() }
        pgrep.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            return resolvePIDViaPS()
        }
        if let firstLine = output.split(separator: "\n").first, let pid = Int32(firstLine) {
            return pid
        }
        return resolvePIDViaPS()
    }

    static func resolvePIDViaPS() -> Int32? {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "ps axco pid,comm | grep -w WindowServer | awk '{print $1}' | head -n1"]

        let outPipe = Pipe()
        shell.standardOutput = outPipe
        shell.standardError = Pipe()

        do { try shell.run() } catch { return nil }
        shell.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty, let pid = Int32(output) else {
            return nil
        }
        return pid
    }

    static func enableOverlay(mask: Int) throws -> (stdout: String, stderr: String, status: Int32) {
        guard let pid = resolveWindowServerPID() else {
            throw NSError(domain: "theoderoy.ws_overlayHelper", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve WindowServer PID"]) }

        let lldbPath = "/usr/bin/lldb"
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: lldbPath, isDirectory: &isDir) || isDir.boolValue {
            throw NSError(domain: "theoderoy.ws_overlayHelper", code: 1002, userInfo: [NSLocalizedDescriptionKey: "LLDB not found at \(lldbPath). Install Xcode Command Line Tools."]) }
        if access(lldbPath, X_OK) != 0 {
            throw NSError(domain: "theoderoy.ws_overlayHelper", code: 1003, userInfo: [NSLocalizedDescriptionKey: "LLDB not executable at \(lldbPath)"]) }

        let lldbCommands = [
            "process attach --pid \(pid)",
            "expr (void)enable_overlay(0b\(String(mask, radix: 2)))",
            "process detach",
            "quit"
        ]
        var arguments: [String] = ["--batch", "--no-lldbinit", "--source-quietly"]
        for cmd in lldbCommands { arguments.append(contentsOf: ["-o", cmd]) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lldbPath)
        process.arguments = arguments
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        let waitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in waitSemaphore.signal() }
        let timeoutSeconds: TimeInterval = 10
        let timeoutResult = waitSemaphore.wait(timeout: .now() + timeoutSeconds)
        if timeoutResult == .timedOut {
            os_log("lldb timed out; terminating", type: .error)
            process.terminate()
            _ = waitSemaphore.wait(timeout: .now() + 2)
        }

        let stdoutStr = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout: stdoutStr, stderr: stderrStr, status: process.terminationStatus)
    }
}

// MARK: - Arguments & Conditions

let args = CommandLine.arguments

func printUsage() {
    let tool = (args.first ?? "ws_overlayHelper")
    let usage = """
    Usage: \(tool) <all|contributor|mouse|foreground|hang|0bMASK|MASK>

      all         -> 0b1111 (All)
      contributor -> 0b1000 (Contributor Screen)
      mouse       -> 0b0100 (Foreground Tracking)
      foreground  -> 0b0010 (Foreground Debugger)
      hang        -> 0b0001 (Framerate & Hang Sensors)

      You may also pass an explicit mask as binary (e.g. 0b1010) or decimal (e.g. 10).
      This command must be run as root.
    """
    print(usage)
}

func parseMask(from arg: String) -> Int? {
    switch arg.lowercased() {
    case "all": return 0b1111
    case "contributor": return 0b1000
    case "mouse": return 0b0100
    case "foreground": return 0b0010
    case "hang": return 0b0001
    default:
        if arg.hasPrefix("0b") || arg.hasPrefix("0B") {
            let bits = String(arg.dropFirst(2))
            if let val = Int(bits, radix: 2) { return val }
        }
        if let val = Int(arg, radix: 10) { return val }
        return nil
    }
}

guard args.count > 1 else {
    printUsage()
    exit(EXIT_FAILURE)
}

let arg = args[1]

guard geteuid() == 0 else {
    fputs("This command must be run as root. Try: sudo \(args[0]) \(arg)\n", stderr)
    exit(EXIT_FAILURE)
}

guard let mask = parseMask(from: arg) else {
    fputs("Unrecognized option: \(arg)\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}

 do {
    let result = try OverlayEnabler.enableOverlay(mask: mask)
    if !result.stdout.isEmpty { fputs(result.stdout, stdout) }
    if !result.stderr.isEmpty { fputs(result.stderr, stderr) }
    exit(Int32(result.status))
} catch {
    fputs("Overlay command failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
