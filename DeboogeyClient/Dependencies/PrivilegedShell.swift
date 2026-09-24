//
//  PrivilegedShell.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum PrivilegedShell {
    enum ExecutionError: Error {
        case scriptCreationFailed
        case executionFailed(message: String?, number: Int, details: [String: String])
    }

    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

#if canImport(AppKit)
    @discardableResult
    static func runAdministrator(command: String) throws -> String {
        let scriptSource = "do shell script \(appleScriptString(command)) with administrator privileges"
        guard let script = NSAppleScript(source: scriptSource) else {
            throw ExecutionError.scriptCreationFailed
        }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let output = result.stringValue {
            return output
        }
        let dict = errorDict as? [String: Any]
        let message = (dict?[NSAppleScript.errorMessage] as? String)
            ?? (dict?[NSAppleScript.errorBriefMessage] as? String)
        let number = (dict?[NSAppleScript.errorNumber] as? Int) ?? 0
        var details: [String: String] = [:]
        if let message { details["message"] = message }
        if let brief = dict?[NSAppleScript.errorBriefMessage] as? String {
            details["brief"] = brief
        }
        throw ExecutionError.executionFailed(message: message, number: number, details: details)
    }
#endif
}
