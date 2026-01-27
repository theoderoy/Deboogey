//
//  main.swift
//  ws_overlayHelper
//
//  Created by Théo De Roy on 13/10/2025.
//

import Foundation
import Darwin

// MARK: - Process Lookup

struct ProcessHelper {
    static func findWindowServerPID() -> Int32? {
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length: Int = 0

        let err = sysctl(&name, UInt32(name.count), nil, &length, nil, 0)
        if err != 0 { return nil }
        
        let count = length / MemoryLayout<kinfo_proc>.size
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: count)
        
        let result = sysctl(&name, UInt32(name.count), &processes, &length, nil, 0)
        if result != 0 { return nil }
        
        for i in 0..<count {
            let p = processes[i]
            let comm = withUnsafePointer(to: p.kp_proc.p_comm) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if comm == "WindowServer" {
                return p.kp_proc.p_pid
            }
        }
        
        return nil
    }
}

// MARK: - Overlay Injection

struct OverlayEnabler {
    
    enum OverlayError: Error, LocalizedError {
        case windowServerNotFound
        case lldbNotFound(path: String)
        case lldbNotExecutable(path: String)
        case executionFailed(status: Int32, stderr: String)
        case symbolNotSupported
        
        var errorDescription: String? {
            switch self {
            case .windowServerNotFound: return "WindowServer process not found."
            case .lldbNotFound(let path): return "LLDB not found at \(path). Install Xcode Command Line Tools."
            case .lldbNotExecutable(let path): return "LLDB not executable at \(path)."
            case .executionFailed(let status, let stderr): return "LLDB exited with status \(status): \(stderr)"
            case .symbolNotSupported: return "The 'enable_overlay' symbol is not supported on this version of macOS."
            }
        }
    }

    static func resolveLLDBPath() -> String {
        return "/usr/bin/lldb"
    }
    
    static func runLLDB(arguments: [String], input: String? = nil) throws -> (stdout: String, stderr: String, status: Int32) {
        let lldbPath = resolveLLDBPath()
        guard FileManager.default.isExecutableFile(atPath: lldbPath) else {
            throw OverlayError.lldbNotFound(path: lldbPath)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lldbPath)
        process.arguments = arguments
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let input = input {
            process.standardInput = inPipe
            if let data = input.data(using: .utf8) {
                try inPipe.fileHandleForWriting.write(contentsOf: data)
                inPipe.fileHandleForWriting.closeFile()
            }
        } else {
             process.standardInput = FileHandle.nullDevice
        }
        
        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()
        
        group.enter()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
             let data = handle.availableData
             if data.isEmpty {
                 handle.readabilityHandler = nil
                 group.leave()
             } else {
                 stdoutData.append(data)
             }
        }
        
        group.enter()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
             if data.isEmpty {
                 handle.readabilityHandler = nil
                 group.leave()
             } else {
                 stderrData.append(data)
             }
        }
        
        try process.run()
        process.waitUntilExit()
        group.wait()
        
        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        
        return (stdoutStr, stderrStr, process.terminationStatus)
    }

    static func enableOverlay(mask: Int) throws {
        guard let pid = ProcessHelper.findWindowServerPID() else {
            throw OverlayError.windowServerNotFound
        }
        
        // Inject call directly (EAFP strategy)
        // If the symbol 'enable_overlay' is missing, lldb will return an error about an undeclared identifier.
        // expr -u true -i false -- (void)enable_overlay(mask)
        let execArgs = ["--batch", "--no-lldbinit", "--source-quietly",
                        "--attach-pid", String(pid),
                        "--one-line", "expr -u true -i false -- (void)enable_overlay(0b\(String(mask, radix: 2)))",
                        "--one-line", "process detach",
                        "--one-line", "quit"]
        
        let execResult = try runLLDB(arguments: execArgs)
        
        // specific check for unsupported symbol
        if execResult.stderr.contains("use of undeclared identifier 'enable_overlay'") ||
            execResult.stdout.contains("use of undeclared identifier 'enable_overlay'") {
            throw OverlayError.symbolNotSupported
        }
        
        if execResult.status != 0 {
             // If legitimate failure, throw it
             throw OverlayError.executionFailed(status: execResult.status, stderr: execResult.stderr)
        }
        
        if !execResult.stderr.isEmpty {
            // LLDB prints to stderr sometimes even on success (e.g. process attached/detached)
            // Filter out common benign messages
             let errors = execResult.stderr.split(separator: "\n").filter {
                 !$0.contains("Process") && !$0.contains("detached") && !$0.contains("attached")
             }
             if !errors.isEmpty {
                 fputs(errors.joined(separator: "\n") + "\n", stderr)
             }
        }
    }
}

// MARK: - CLI Entry Point

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

// Main Execution
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
    try OverlayEnabler.enableOverlay(mask: mask)
    print("Overlay command sent successfully.")
    exit(EXIT_SUCCESS)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
