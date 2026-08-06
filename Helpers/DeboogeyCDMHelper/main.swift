//
//  main.swift
//  DeboogeyCDMHelper
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
#if !DEBOOGEY_MCE
import AppKit
#endif

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

let args = CommandLine.arguments

func printUsage() {
    let tool = (args.first as NSString?)?.lastPathComponent ?? "DeboogeyCDMHelper"
    let usage = """
    Usage: \(tool) <enable|disable> <global|bundle> [--autokill]

      Examples:
        \(tool) enable global
        \(tool) disable example.myapp
        \(tool) enable example.myapp --autokill

      This writes the boolean key `_NS_4445425547` using `defaults`:
        defaults write <domain> _NS_4445425547 -bool <true|false>

      Where <domain> is:
        - "-g" (global domain) when you pass `global`
        - a bundle identifier (example.myapp) in place of passing `bundle`

      Optional flags:
        --autokill    After applying, politely ask the target to quit.
                      No quit is attempted when this flag is omitted.
"""
    print(usage)
}

let autoKillRequested = args.contains("--autokill")
let positionalArgs = args.filter { $0 != "--autokill" }

guard positionalArgs.count == 3 else {
    printUsage()
    exit(EXIT_FAILURE)
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

guard let action = ToggleAction(rawValue: actionArg.lowercased()) else {
    fputs("Unrecognized action: \(actionArg)\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}

guard let domain = parseDomain(domainArg) else {
    fputs("Unrecognized domain: \(domainArg). Use 'global' or a bundle identifier (e.g., com.apple.TextEdit).\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}

#if DEBOOGEY_MCE
guard domain == "theoderoy.Deboogey.MCE" else {
    fputs("This helper can only update the Deboogey client.\n", stderr)
    exit(EXIT_FAILURE)
}
#endif

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
#if DEBOOGEY_MCE
                exit(Int32(result.status))
#else
                switch requestGracefulTermination(bundleIdentifier: domain) {
                case .success:
                    exit(Int32(result.status))
                case .failure(let message):
                    fputs("Auto-Quit failed or was cancelled: \(message)\n", stderr)
                    exit(EXIT_FAILURE)
                }
#endif
            }
        } else {
            exit(Int32(result.status))
        }
    } catch {
        fputs("defaults write failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

#if !DEBOOGEY_MCE
enum TerminationResult { case success; case failure(String) }

func requestGracefulTermination(bundleIdentifier: String) -> TerminationResult {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { !$0.isTerminated }
    guard !applications.isEmpty else { return .success }

    for application in applications where !application.terminate() {
        return .failure("The application rejected the quit request.")
    }

    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if applications.allSatisfy(\.isTerminated) { return .success }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    for application in applications where !application.isTerminated {
        _ = application.terminate()
    }
    let retryDeadline = Date().addingTimeInterval(3)
    while Date() < retryDeadline {
        if applications.allSatisfy(\.isTerminated) { return .success }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    return .failure("The application did not finish quitting.")
}
#endif

runDefaultsWriteAndMaybeKill(action: action, domain: domain, autoKill: autoKillRequested)
