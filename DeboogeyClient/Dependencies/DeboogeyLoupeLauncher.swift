//
//  DeboogeyLoupeLauncher.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 28/07/2026.
//

import Foundation
import Darwin
import CoreFoundation
import AppKit

#if !DEBOOGEY_MCE
enum LoupeApplicationDataError: LocalizedError {
    case applicationUnavailable
    case unsupportedFlag(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable:
            return L10n.t("The selected application is unavailable.")
        case .unsupportedFlag(let name):
            return L10n.f("%@ cannot be written to application preferences.", name)
        case .writeFailed:
            return L10n.t("The application preferences could not be saved.")
        }
    }
}

struct LoupeApplicationData {
    static func apply(_ values: [LoupeFlag: String], to appURL: URL) throws {
        guard let identifier = Bundle(url: appURL)?.bundleIdentifier, !identifier.isEmpty else {
            throw LoupeApplicationDataError.applicationUnavailable
        }

        let changes = try values.map { flag, value -> (LoupeFlag, Any?) in
            guard flag.source != nil, !flag.keyPath.isEmpty else {
                throw LoupeApplicationDataError.unsupportedFlag(flag.name)
            }
            if flag.source == .systemFeatureFlags {
                guard flag.backingFilePath != nil else {
                    throw LoupeApplicationDataError.unsupportedFlag(flag.name)
                }
            }
            return (flag, preferenceValue(from: value))
        }

        let featureChanges = Dictionary(grouping: changes.filter { $0.0.source == .systemFeatureFlags }) {
            $0.0.backingFilePath!
        }
        for (path, fileChanges) in featureChanges {
            try writeFeatureFlags(fileChanges, to: URL(fileURLWithPath: path))
        }

        let applicationChanges = changes.filter {
            $0.0.source == .defaults || $0.0.source == .binaryFlags || $0.0.source == .other
        }
        if !applicationChanges.isEmpty {
            try writeDefaults(applicationChanges, domain: identifier)
        }

        let globalChanges = changes.filter { $0.0.source == .globalDefaults }
        if !globalChanges.isEmpty {
            try writeDefaults(globalChanges, domain: UserDefaults.globalDomain)
        }

        for (flag, _) in values.sorted(by: { $0.key.name.localizedStandardCompare($1.key.name) == .orderedAscending }) {
            EntityTracker.shared.record(source: .loupeMachine, arguments: [flag.name, identifier])
        }
    }

    private static func writeDefaults(_ changes: [(LoupeFlag, Any?)], domain: String) throws {
        let defaults = UserDefaults.standard
        var dictionary = defaults.persistentDomain(forName: domain) ?? [:]
        for (flag, value) in changes {
            dictionary = setting(value, at: flag.keyPath[...], in: dictionary)
        }
        defaults.setPersistentDomain(dictionary, forName: domain)
        guard defaults.synchronize() else { throw LoupeApplicationDataError.writeFailed }
    }

    private static func writeFeatureFlags(_ changes: [(LoupeFlag, Any?)], to url: URL) throws {
        do {
            let destination = featureFlagWriteURL(for: url)
            let currentURL = FileManager.default.fileExists(atPath: destination.path) ? destination : url
            let data = try Data(contentsOf: currentURL)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard var dictionary = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any] else {
                throw LoupeApplicationDataError.writeFailed
            }
            for (flag, value) in changes {
                dictionary = setting(value, at: flag.keyPath[...], in: dictionary)
            }
            let output = try PropertyListSerialization.data(fromPropertyList: dictionary, format: format, options: 0)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try output.write(to: destination, options: .atomic)
            } catch where requiresPrivileges(error) {
                try writeWithAdministratorPrivileges(output, to: destination)
            }
        } catch let error as LoupeApplicationDataError {
            throw error
        } catch {
            throw LoupeApplicationDataError.writeFailed
        }
    }

    private static func featureFlagWriteURL(for source: URL) -> URL {
        let systemRoot = URL(fileURLWithPath: "/System/Library/FeatureFlags", isDirectory: true)
            .standardizedFileURL
        let standardizedSource = source.standardizedFileURL
        guard standardizedSource.path.hasPrefix(systemRoot.path + "/") else { return source }
        return URL(fileURLWithPath: "/Library/Preferences/FeatureFlags/Domain", isDirectory: true)
            .appendingPathComponent(source.lastPathComponent)
    }

    private static func requiresPrivileges(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(error.code) {
            return true
        }
        if error.domain == NSPOSIXErrorDomain,
           [EPERM, EACCES, EROFS].contains(Int32(error.code)) {
            return true
        }
        return (error.userInfo[NSUnderlyingErrorKey] as? Error).map(requiresPrivileges) ?? false
    }

    private static func writeWithAdministratorPrivileges(_ data: Data, to destination: URL) throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoupeMachine-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: [.atomic, .completeFileProtection])

        let directory = destination.deletingLastPathComponent().path
        let command = "/bin/mkdir -p \(shellQuoted(directory)) && "
            + "/bin/cp -f \(shellQuoted(temporaryURL.path)) \(shellQuoted(destination.path))"
        let source = "do shell script \(appleScriptString(command)) with administrator privileges"
        var errorInfo: NSDictionary?
        guard NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) != nil else {
            throw LoupeApplicationDataError.writeFailed
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func setting(
        _ value: Any?,
        at path: ArraySlice<String>,
        in dictionary: [String: Any]
    ) -> [String: Any] {
        guard let key = path.first else { return dictionary }
        var dictionary = dictionary
        if path.count == 1 {
            if let value { dictionary[key] = value }
            else { dictionary.removeValue(forKey: key) }
            return dictionary
        }
        let nested = dictionary[key] as? [String: Any] ?? [:]
        dictionary[key] = setting(value, at: path.dropFirst(), in: nested)
        return dictionary
    }

    private static func preferenceValue(from text: String) -> Any? {
        if text == L10n.t("Unassigned") { return nil }
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return text
        }
        return value is NSNull ? nil : value
    }
}
#endif

enum DeboogeyLoupeLauncherError: LocalizedError {
    case toolNotFound
    case toolNotExecutable
    case failed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .toolNotFound:
            return L10n.t("DeboogeyLoupe was not found in the app resources.")
        case .toolNotExecutable:
            return L10n.t("DeboogeyLoupe is not executable.")
        case .failed(let message):
            return message
        case .invalidOutput:
            return L10n.t("DeboogeyLoupe returned an invalid result.")
        }
    }
}

struct LoupeFlag: Identifiable, Hashable {
    enum Source: String, Hashable, Codable {
        case defaults
        case globalDefaults
        case systemFeatureFlags
        case binaryFlags
        case other
    }

    let name: String
    let source: Source?
    let keyPath: [String]
    let backingFilePath: String?
    private let inlineValue: String?
    let valueFileURL: URL?

    init(
        name: String,
        value: String,
        source: Source? = nil,
        keyPath: [String]? = nil,
        backingFilePath: String? = nil
    ) {
        self.name = name
        let inferred = Self.inferredTarget(for: name)
        self.source = source ?? inferred.source
        self.keyPath = keyPath ?? inferred.keyPath
        self.backingFilePath = backingFilePath ?? inferred.backingFilePath
        inlineValue = value
        valueFileURL = nil
    }

    init(
        name: String,
        valueFileURL: URL,
        source: Source? = nil,
        keyPath: [String]? = nil,
        backingFilePath: String? = nil
    ) {
        self.name = name
        let inferred = Self.inferredTarget(for: name)
        self.source = source ?? inferred.source
        self.keyPath = keyPath ?? inferred.keyPath
        self.backingFilePath = backingFilePath ?? inferred.backingFilePath
        inlineValue = nil
        self.valueFileURL = valueFileURL
    }

    func replacingValue(with value: String) -> LoupeFlag {
        LoupeFlag(
            name: name,
            value: value,
            source: source,
            keyPath: keyPath,
            backingFilePath: backingFilePath
        )
    }

    var value: String {
        inlineValue ?? valueFileURL.flatMap(DeboogeyLoupeLauncher.displayValue(at:))
            ?? L10n.t("DeboogeyLoupe returned an invalid result.")
    }

    var id: String { name }

    private static func inferredTarget(for name: String) -> (
        source: Source?, keyPath: [String], backingFilePath: String?
    ) {
        for source in [Source.defaults, .globalDefaults, .binaryFlags] {
            let prefix = source.rawValue + "."
            if name.hasPrefix(prefix) {
                return (source, [String(name.dropFirst(prefix.count))], nil)
            }
        }
        let prefix = Source.systemFeatureFlags.rawValue + "."
        guard name.hasPrefix(prefix) else { return (.other, [name], nil) }
        let remainder = String(name.dropFirst(prefix.count))
        guard let plistRange = remainder.range(of: ".plist.") else {
            return (.systemFeatureFlags, [], nil)
        }
        let path = String(remainder[..<plistRange.lowerBound]) + ".plist"
        let key = String(remainder[plistRange.upperBound...])
        return (.systemFeatureFlags, key.isEmpty ? [] : [key], path)
    }
}

final class DeboogeyLoupeInspection: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        let runningProcess = process
        lock.unlock()
        hardKill(runningProcess)
    }

    fileprivate func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldKill = isCancelled
        lock.unlock()
        if shouldKill { hardKill(process) }
    }

    fileprivate func detach(_ process: Process) {
        lock.lock()
        if self.process === process { self.process = nil }
        lock.unlock()
    }

    private func hardKill(_ process: Process?) {
        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }
}

struct DeboogeyLoupeLauncher {
    static func inspect(
        appURL: URL,
        inspection: DeboogeyLoupeInspection? = nil,
        didLoad: (([LoupeFlag]) -> Void)? = nil
    ) throws -> [LoupeFlag] {
#if DEBOOGEY_MCE
        let toolURL = Bundle.main.url(forAuxiliaryExecutable: "DeboogeyLoupeMCE")
#else
        let toolURL = Bundle.main.url(forResource: "DeboogeyLoupe", withExtension: nil)
#endif
        guard let toolURL else {
            throw DeboogeyLoupeLauncherError.toolNotFound
        }
        guard FileManager.default.isExecutableFile(atPath: toolURL.path) else {
            throw DeboogeyLoupeLauncherError.toolNotExecutable
        }

        let process = Process()
        process.executableURL = toolURL
        process.arguments = [appURL.path]
        var environment = ProcessInfo.processInfo.environment
#if DEBOOGEY_MCE
        let bookmark = try appURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        environment["DEBOOGEY_LOUPE_APP_BOOKMARK"] = bookmark.base64EncodedString()
#endif
        environment["DEBOOGEY_LOUPE_GUI_LAUNCH"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        inspection?.attach(process)
        defer {
            inspection?.detach(process)
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        let errorReadGroup = DispatchGroup()
        let errorLock = NSLock()
        var errorData = Data()
        errorReadGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            errorLock.lock()
            errorData = data
            errorLock.unlock()
            errorReadGroup.leave()
        }

        var pending = Data()
        var result: [LoupeFlag] = []
        while true {
            let data = output.fileHandleForReading.availableData
            if data.isEmpty { break }
            pending.append(data)
            var lineStart = pending.startIndex
            while let newline = pending[lineStart...].firstIndex(of: 0x0a) {
                let line = pending[lineStart..<newline]
                guard !line.isEmpty,
                      let records = try JSONSerialization.jsonObject(with: Data(line)) as? [[String: Any]] else {
                    throw DeboogeyLoupeLauncherError.invalidOutput
                }
                let batch = records.compactMap { record -> LoupeFlag? in
                    guard let name = record["name"] as? String,
                          let path = record["file"] as? String else { return nil }
                    let source = (record["source"] as? String).flatMap(LoupeFlag.Source.init(rawValue:))
                    let keyPath = record["keyPath"] as? [String]
                    let backingFilePath = record["backingFile"] as? String
                    return LoupeFlag(
                        name: name,
                        valueFileURL: URL(fileURLWithPath: path),
                        source: source,
                        keyPath: keyPath,
                        backingFilePath: backingFilePath
                    )
                }
                guard batch.count == records.count else { throw DeboogeyLoupeLauncherError.invalidOutput }
                result.append(contentsOf: batch)
                didLoad?(batch)
                lineStart = pending.index(after: newline)
                if lineStart == pending.endIndex { break }
            }
            if lineStart != pending.startIndex {
                pending.removeSubrange(pending.startIndex..<lineStart)
            }
        }
        process.waitUntilExit()
        errorReadGroup.wait()

        guard process.terminationStatus == 0 else {
            errorLock.lock()
            let capturedErrorData = errorData
            errorLock.unlock()
            let detail = String(data: capturedErrorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DeboogeyLoupeLauncherError.failed(
                detail?.isEmpty == false ? detail! : L10n.t("DeboogeyLoupe could not inspect the application.")
            )
        }

        guard pending.isEmpty else {
            throw DeboogeyLoupeLauncherError.invalidOutput
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated static func displayValue(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = wrapper["value"] else { return nil }
        return displayValue(value)
    }

    nonisolated private static func displayValue(_ value: Any) -> String {
        if value is NSNull {
            return L10n.t("Unassigned")
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return String(describing: value)
    }
}
