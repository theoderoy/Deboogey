//
//  main.swift
//  deboogeyLadybugHelper
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation

// MARK: - Defaults Write

enum ToggleAction: String {
    case enable
    case disable
}

struct DefaultsToggler {
    static func writeToggle(action: ToggleAction, domain: String) throws -> (stdout: String, stderr: String, status: Int32) {
        let defaultsPath = "/usr/bin/defaults"
        let value = (action == .enable) ? "true" : "false"

        let args = ["write", domain, "_NS_4445425547", "-bool", value]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: defaultsPath)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let stdoutStr = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout: stdoutStr, stderr: stderrStr, status: process.terminationStatus)
    }
}

// MARK: - Arguments

let args = CommandLine.arguments

func hasAutoKillFlag(_ args: [String]) -> Bool {
    return args.contains("--autokill")
}

func printUsage() {
    let tool = (args.first as NSString?)?.lastPathComponent ?? "deboogeyLadybugHelper"
    let usage = """
    Usage: \(tool) <enable|disable> <global|BUNDLE_ID> [--autokill]

      Examples:
        \(tool) enable global
        \(tool) disable com.example.myapp
        \(tool) enable com.example.myapp --autokill

      This writes the boolean key `_NS_4445425547` using `defaults`:
        defaults write <domain> _NS_4445425547 -bool <true|false>

      Where <domain> is:
        - "-g" (global domain) when you pass `global`
        - a specific bundle identifier when you pass `BUNDLE_ID`

      Optional flags:
        --autokill    After applying, politely ask the target (by bundle id) to quit.
                      No quit is attempted when this flag is omitted.
"""
    print(usage)
}

let autoKillRequested = hasAutoKillFlag(args)

let minimumArgsOK = args.count >= 3
let positionalArgs = args.filter { $0 != "--autokill" }

guard minimumArgsOK && positionalArgs.count == 3 else {
    printUsage()
    exit(EXIT_FAILURE)
}

func parseAction(_ string: String) -> ToggleAction? {
    return ToggleAction(rawValue: string.lowercased())
}

func parseDomain(_ string: String) -> String? {
    if string.lowercased() == "global" { return "-g" }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    if string.rangeOfCharacter(from: allowed.inverted) == nil, string.contains(".") {
        return string
    }
    return nil
}

let actionArg = positionalArgs[1]
let domainArg = positionalArgs[2]

guard let action = parseAction(actionArg) else {
    fputs("Unrecognized action: \(actionArg)\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}

guard let domain = parseDomain(domainArg) else {
    fputs("Unrecognized domain: \(domainArg). Use 'global' or a bundle identifier (e.g., com.apple.TextEdit).\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}

if domain != "-g" {
    if #unavailable(macOS 12.0) {
        fputs("Targeting individual apps requires macOS 12.0 (Monterey) or later.\n", stderr)
        exit(EXIT_FAILURE)
    }
}

func runDefaultsWriteAndMaybeKill(action: ToggleAction, domain: String, autoKill: Bool) {
    do {
        let result = try DefaultsToggler.writeToggle(action: action, domain: domain)
        if !result.stdout.isEmpty { fputs(result.stdout, stdout) }
        if !result.stderr.isEmpty { fputs(result.stderr, stderr) }

        if autoKill {
            if domain == "-g" {
                fputs("Notice: Auto-Quit is ignored for the global domain. You should restart your machine to see all changes.\n", stderr)
                exit(Int32(result.status))
            } else {
                let script = "tell application id \"\(domain)\" to quit"
                let osaResult = runAppleScript(script)
                switch osaResult {
                case .success:
                    exit(Int32(result.status))
                case .failure(let message):
                    fputs("Auto-Quit failed or was cancelled: \(message)\n", stderr)
                    exit(EXIT_FAILURE)
                }
            }
        } else {
            exit(Int32(result.status))
        }
    } catch {
        fputs("defaults write failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

enum AppleScriptResult { case success; case failure(String) }

func runAppleScript(_ script: String) -> AppleScriptResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let status = process.terminationStatus
        if status == 0 {
            return .success
        } else {
            let stderrStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return .failure(stderrStr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    } catch {
        return .failure("osascript failed to run: \(error)")
    }
}

runDefaultsWriteAndMaybeKill(action: action, domain: domain, autoKill: autoKillRequested)
