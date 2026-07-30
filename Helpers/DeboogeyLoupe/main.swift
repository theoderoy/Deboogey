//
//  main.swift
//  DeboogeyLoupe
//
//  Created by Théo De Roy on 12/07/2026.
//

import Foundation
import Darwin

guard ProcessInfo.processInfo.environment["DEBOOGEY_LOUPE_GUI_LAUNCH"] == "1" else {
    print("Running DeboogeyLoupe in a command-line interface is unsupported.")
    exit(EXIT_FAILURE)
}

enum LoupeError: LocalizedError {
    case usage(String)
    case notAFile(String)
    case notExecutable(String)
    case noBundle(String)
    case noBundleIdentifier(String)
    case defaultsFailed(String)
    case invalidDefaults

    var errorDescription: String? {
        switch self {
        case .usage(let tool):
            return "Usage: \(tool) <app-bundle>"
        case .notAFile(let path):
            return "No app binary exists at \(path)."
        case .notExecutable(let path):
            return "The file is not executable: \(path)."
        case .noBundle(let path):
            return "The binary is not inside a macOS .app bundle: \(path)."
        case .noBundleIdentifier(let path):
            return "The app bundle has no CFBundleIdentifier: \(path)."
        case .defaultsFailed(let message):
            return "Could not read the defaults domain: \(message)"
        case .invalidDefaults:
            return "The defaults domain was not a property list dictionary."
        }
    }
}

struct AppIdentity {
    let binaryURL: URL
    let bundleURL: URL
    let bundleIdentifier: String
    let executableName: String
    let bundleName: String

    init(argument: String) throws {
        let expanded = (argument as NSString).expandingTildeInPath
        let suppliedURL = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()

        if suppliedURL.pathExtension.lowercased() == "app", let bundle = Bundle(url: suppliedURL),
           let executableURL = bundle.executableURL {
            binaryURL = executableURL.resolvingSymlinksInPath()
        } else {
            binaryURL = suppliedURL
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: binaryURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw LoupeError.notAFile(binaryURL.path)
        }
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw LoupeError.notExecutable(binaryURL.path)
        }

        var candidate = binaryURL.deletingLastPathComponent()
        var foundBundle: Bundle?
        while candidate.path != "/" {
            if candidate.pathExtension.lowercased() == "app", let bundle = Bundle(url: candidate) {
                foundBundle = bundle
                break
            }
            candidate.deleteLastPathComponent()
        }

        guard let bundle = foundBundle else { throw LoupeError.noBundle(binaryURL.path) }
        guard let identifier = bundle.bundleIdentifier, !identifier.isEmpty else {
            throw LoupeError.noBundleIdentifier(bundle.bundleURL.path)
        }

        bundleURL = bundle.bundleURL.resolvingSymlinksInPath()
        bundleIdentifier = identifier
        executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            ?? binaryURL.lastPathComponent
        bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }
}

func run(_ executable: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice

    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors

    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let message = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "defaults exited with \(process.terminationStatus)"
        throw LoupeError.defaultsFailed(message)
    }
    return data
}

func readDefaults(domain: String) throws -> [String: Any] {
    do {
        let data = try run("/usr/bin/defaults", ["export", domain, "-"])
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any] else {
            throw LoupeError.invalidDefaults
        }
        return dictionary
    } catch LoupeError.defaultsFailed(let message) where message.contains("does not exist") {
        return [:]
    }
}

func normalizedForJSON(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]:
        return dictionary.mapValues(normalizedForJSON)
    case let array as [Any]:
        return array.map(normalizedForJSON)
    case let date as Date:
        return ISO8601DateFormatter().string(from: date)
    case let data as Data:
        return data.base64EncodedString()
    case let url as URL:
        return url.absoluteString
    case is NSNull, is String, is NSNumber:
        return value
    default:
        return String(describing: value)
    }
}

func looksLikePreferenceKey(_ value: String) -> Bool {
    guard value.count >= 3, value.count <= 128,
          value.first?.isLetter == true,
          value.unicodeScalars.allSatisfy({
              CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
          }),
          !value.contains(".."), !value.hasSuffix("."),
          !value.hasSuffix(".dylib"), !value.hasSuffix(".framework"),
          !value.hasSuffix(".swift"), !value.hasSuffix(".plist") else { return false }

    return true
}

private enum RegisterValue: Equatable {
    case argument(Int)
    case literal(String)
    case preferences
}

private struct CallSite {
    let callee: String
    let arguments: [Int: RegisterValue]
}

private struct FunctionAnalysis {
    let name: String
    var preferenceArguments: Set<Int> = []
    var literalKeys: Set<String> = []
    var calls: [CallSite] = []
}

private let preferenceSymbolFragments = [
    "NSUserDefaults", "UserDefaults", "CFPreferences",
    "boolForKey:", "integerForKey:", "floatForKey:", "doubleForKey:",
    "stringForKey:", "arrayForKey:", "dictionaryForKey:", "dataForKey:",
    "stringArrayForKey:", "URLForKey:", "objectForKey:"
]

private func isMachOFile(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
    let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    return [
        UInt32(MH_MAGIC), UInt32(MH_CIGAM), UInt32(MH_MAGIC_64), UInt32(MH_CIGAM_64),
        UInt32(FAT_MAGIC), UInt32(FAT_CIGAM), UInt32(FAT_MAGIC_64), UInt32(FAT_CIGAM_64)
    ].contains(magic)
}

private func containsPreferenceSymbols(_ url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
    return preferenceSymbolFragments.contains { fragment in
        data.range(of: Data(fragment.utf8)) != nil
    }
}

private func streamLines(
    from executable: String,
    arguments: [String],
    _ consume: (String) -> Void
) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output

    try process.run()
    var pending = Data()
    while true {
        let chunk = output.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        pending.append(chunk)
        var lineStart = pending.startIndex
        while let newline = pending[lineStart...].firstIndex(of: 0x0a) {
            let line = pending[lineStart..<newline]
            if let text = String(data: line, encoding: .utf8) { consume(text) }
            lineStart = pending.index(after: newline)
            if lineStart == pending.endIndex { break }
        }
        if lineStart != pending.startIndex {
            pending.removeSubrange(pending.startIndex..<lineStart)
        }
    }
    if !pending.isEmpty, let text = String(data: pending, encoding: .utf8) { consume(text) }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw LoupeError.defaultsFailed("dyld_info exited with \(process.terminationStatus)")
    }
}

private func inspectableBinaries(in app: AppIdentity) -> [URL] {
    let contents = app.bundleURL.appendingPathComponent("Contents", isDirectory: true)
    let codeDirectories = [
        "MacOS", "Frameworks", "SharedFrameworks", "PlugIns", "XPCServices",
        "Helpers", "Library/LoginItems"
    ]
    var paths = Set([app.binaryURL.resolvingSymlinksInPath().path])

    for directory in codeDirectories.map({ contents.appendingPathComponent($0, isDirectory: true) }) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { continue }

        for case let url as URL in enumerator {
            let resolved = url.resolvingSymlinksInPath()
            guard !paths.contains(resolved.path),
                  (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  isMachOFile(resolved), containsPreferenceSymbols(resolved) else { continue }
            paths.insert(resolved.path)
        }
    }
    return paths.sorted().map(URL.init(fileURLWithPath:))
}

private func normalizedRegister(_ value: Substring) -> String? {
    let register = value.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "[]!"))
        .lowercased()
    if register == "sp" || register == "fp" || register == "lr" { return register }
    if let number = Int(register.dropFirst()), register.first == "x" || register.first == "w" {
        return "x\(number)"
    }
    if register.hasPrefix("r"), register.count >= 2 { return register }
    return nil
}

private func quotedLiteral(in comment: Substring) -> String? {
    guard let firstQuote = comment.firstIndex(of: "\"") else { return nil }
    let contents = comment[comment.index(after: firstQuote)...]
    guard let lastQuote = contents.lastIndex(of: "\"") else { return nil }
    let value = String(contents[..<lastQuote])
    return looksLikePreferenceKey(value) ? value : nil
}

private func callTarget(in operands: Substring) -> String {
    operands.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
}

private func preferenceKeyRegister(for symbol: String) -> Int? {
    let cfPreferenceReaders = [
        "CFPreferencesCopyAppValue", "CFPreferencesCopyValue",
        "CFPreferencesGetAppBooleanValue", "CFPreferencesGetAppIntegerValue"
    ]
    if cfPreferenceReaders.contains(where: symbol.contains) { return 0 }
    if symbol.contains("NSUserDefaults") || symbol.contains("UserDefaults") {
        let readers = ["bool", "integer", "float", "double", "string", "array", "dictionary", "data", "URL", "object"]
        return symbol.contains("forKey") && readers.contains(where: symbol.contains) ? 1 : nil
    }
    let selectors = [
        "boolForKey:", "integerForKey:", "floatForKey:", "doubleForKey:",
        "stringForKey:", "arrayForKey:", "dictionaryForKey:", "dataForKey:",
        "stringArrayForKey:", "URLForKey:", "objectForKey:"
    ]
    return selectors.contains(where: symbol.contains) ? 2 : nil
}

private func analyzeBinary(at url: URL, didDiscover: (Set<String>) -> Void) -> [FunctionAnalysis] {
    var starts: [UInt64: String] = [:]
    var knownFunctions: Set<String> = []
    var isReadingFunctionStarts = false
    var isReadingDisassembly = false
    var analyses: [FunctionAnalysis] = []
    var pendingKeys: Set<String> = []
    var current = FunctionAnalysis(name: "\(url.path)#entry")
    var registers: [String: RegisterValue] = Dictionary(
        uniqueKeysWithValues: (0...7).map { ("x\($0)", .argument($0)) }
    )

    func finishFunction() {
        if !current.calls.isEmpty || !current.literalKeys.isEmpty || !current.preferenceArguments.isEmpty {
            analyses.append(current)
        }
    }

    func discovered(_ key: String) {
        pendingKeys.insert(key)
        if pendingKeys.count >= 64 {
            didDiscover(pendingKeys)
            pendingKeys.removeAll(keepingCapacity: true)
        }
    }

    func consume(_ text: String) {
        if text.contains("-function_starts:") {
            isReadingFunctionStarts = true
            return
        }
        if text.contains(" section:") {
            isReadingFunctionStarts = false
            isReadingDisassembly = true
            knownFunctions = Set(starts.values)
            return
        }

        let line = text[...]
        if isReadingFunctionStarts {
            let fields = line.trimmingCharacters(in: .whitespaces)
                .split(maxSplits: 1, whereSeparator: \ .isWhitespace)
            guard fields.count == 2, fields[0].hasPrefix("0x"),
                  let address = UInt64(fields[0].dropFirst(2), radix: 16) else { return }
            let name = String(fields[1])
            starts[address] = name
            knownFunctions.insert(name)
            return
        }
        guard isReadingDisassembly else { return }

        let fields = line.split(maxSplits: 2, whereSeparator: \ .isWhitespace)
        guard fields.count >= 2, fields[0].hasPrefix("0x"),
              let address = UInt64(fields[0].dropFirst(2), radix: 16) else { return }

        if let functionName = starts[address] {
            finishFunction()
            current = FunctionAnalysis(name: functionName)
            registers = Dictionary(uniqueKeysWithValues: (0...7).map { ("x\($0)", .argument($0)) })
        }

        let instruction = String(fields[1]).lowercased()
        let remainder = fields.count == 3 ? fields[2] : ""
        let pieces = remainder.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let operandText = pieces.first ?? ""
        let operands = operandText.split(separator: ",", omittingEmptySubsequences: false)

        if instruction == "bl" || instruction == "call" || instruction == "callq" {
            let target = callTarget(in: operandText)
            let arguments = Dictionary(uniqueKeysWithValues: (0...7).compactMap { index in
                registers["x\(index)"].map { (index, $0) }
            })
            let isObjectiveCSelector = target.contains("objc_msgSend$")
            if let keyRegister = preferenceKeyRegister(for: target),
               (!isObjectiveCSelector || arguments[0] == .preferences),
                let value = arguments[keyRegister] {
                switch value {
                case .literal(let key):
                    if current.literalKeys.insert(key).inserted { discovered(key) }
                case .argument(let index): current.preferenceArguments.insert(index)
                case .preferences: break
                }
            } else if knownFunctions.contains(target) {
                current.calls.append(CallSite(callee: target, arguments: arguments))
            }
            let returnsPreferences = target.contains("standardUserDefaults")
                || target.contains("UserDefaultsC8standard")
                || target.contains("initWithSuiteName:")
            let preservesReturnValue = target.contains("objc_claimAutoreleasedReturnValue")
                || target.contains("objc_retainAutoreleasedReturnValue")
                || target == "_objc_retain"
            let returnValue: RegisterValue? = returnsPreferences
                ? .preferences
                : (preservesReturnValue ? arguments[0] : nil)
            for index in 0...18 { registers.removeValue(forKey: "x\(index)") }
            registers["x0"] = returnValue
            return
        }

        guard let destination = operands.first.flatMap(normalizedRegister) else { return }
        if pieces.count == 2, let literal = quotedLiteral(in: pieces[1]) {
            registers[destination] = .literal(literal)
            return
        }

        let propagatingInstructions = ["mov", "orr", "add", "lea", "movq", "movl"]
        if propagatingInstructions.contains(instruction),
           let source = operands.dropFirst().compactMap(normalizedRegister).compactMap({ registers[$0] }).first {
            registers[destination] = source
        } else if !["str", "stp", "cmp", "cmn", "tst"].contains(instruction) {
            registers.removeValue(forKey: destination)
        }
    }

    do {
        try streamLines(
            from: "/usr/bin/dyld_info",
            arguments: ["-function_starts", "-disassemble", url.path],
            consume
        )
    } catch {
        return []
    }
    finishFunction()
    if !pendingKeys.isEmpty { didDiscover(pendingKeys) }
    return analyses
}

private func resolvedPreferenceKeys(in functions: [FunctionAnalysis]) -> Set<String> {
    var functions = functions
    var summaries: [String: Set<Int>] = [:]
    for function in functions where !function.preferenceArguments.isEmpty {
        summaries[function.name, default: []].formUnion(function.preferenceArguments)
    }

    var changed = true
    while changed {
        changed = false
        for index in functions.indices {
            for call in functions[index].calls {
                for keyArgument in summaries[call.callee, default: []] {
                    guard let value = call.arguments[keyArgument] else { continue }
                    switch value {
                    case .literal(let key):
                        if functions[index].literalKeys.insert(key).inserted { changed = true }
                    case .argument(let argument):
                        if functions[index].preferenceArguments.insert(argument).inserted {
                            summaries[functions[index].name, default: []].insert(argument)
                            changed = true
                        }
                    case .preferences:
                        break
                    }
                }
            }
        }
    }
    return functions.reduce(into: Set<String>()) { $0.formUnion($1.literalKeys) }
}

private func streamDisassembledPreferenceKeys(
    in app: AppIdentity,
    excluding assignedKeys: Set<String>,
    didDiscover: @escaping ([String]) -> Void
) {
    let binaries = inspectableBinaries(in: app)
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = min(2, max(1, ProcessInfo.processInfo.activeProcessorCount))
    let lock = NSLock()
    var emittedKeys: Set<String> = []

    func publish(_ keys: Set<String>) {
        lock.lock()
        let newKeys = keys.subtracting(assignedKeys).subtracting(emittedKeys)
        emittedKeys.formUnion(newKeys)
        if !newKeys.isEmpty {
            didDiscover(newKeys.sorted())
        }
        lock.unlock()
    }

    for binary in binaries {
        queue.addOperation {
            let analysis = analyzeBinary(at: binary, didDiscover: publish)
            publish(resolvedPreferenceKeys(in: analysis))
        }
    }
    queue.waitUntilAllOperationsAreFinished()
}

func featureFlagFiles(for app: AppIdentity) -> [String: Any] {
    let names = Set([app.bundleIdentifier, app.executableName, app.bundleName].map { $0.lowercased() })
    let roots = [
        "/System/Library/FeatureFlags/Domain",
        "/System/Library/FeatureFlags/Unified/Domain",
        "/Library/Preferences/FeatureFlags/Domain",
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Preferences/FeatureFlags/Domain")
    ]
    var result: [String: Any] = [:]

    for root in roots {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
        for filename in files where (filename as NSString).pathExtension.lowercased() == "plist" {
            let stem = (filename as NSString).deletingPathExtension.lowercased()
            guard names.contains(stem) else { continue }
            let path = (root as NSString).appendingPathComponent(filename)
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { continue }
            result[path] = normalizedForJSON(plist)
        }
    }
    return result
}

func emitFlags(
    _ dictionary: [String: Any],
    prefix: String,
    source: String,
    backingFilePath: String? = nil,
    outputDirectory: URL
) throws {
    func flatten(_ dictionary: [String: Any], prefix: String, keyPath: [String]) -> [(String, [String], Any)] {
        dictionary.flatMap { key, value -> [(String, [String], Any)] in
            let name = prefix.isEmpty ? key : "\(prefix).\(key)"
            let nestedKeyPath = keyPath + [key]
            if let nested = value as? [String: Any] {
                return flatten(nested, prefix: name, keyPath: nestedKeyPath)
            }
            return [(name, nestedKeyPath, value)]
        }
    }

    let records = try flatten(dictionary, prefix: prefix, keyPath: [])
        .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        .map { name, keyPath, value -> [String: Any] in
            let fileURL = outputDirectory.appendingPathComponent("\(UUID().uuidString).json")
            let data = try JSONSerialization.data(withJSONObject: ["value": normalizedForJSON(value)])
            try data.write(to: fileURL, options: .atomic)
            var record: [String: Any] = [
                "name": name,
                "file": fileURL.path,
                "source": source,
                "keyPath": keyPath
            ]
            if let backingFilePath { record["backingFile"] = backingFilePath }
            return record
        }
    guard !records.isEmpty else { return }
    let data = try JSONSerialization.data(withJSONObject: records)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 2 else {
        throw LoupeError.usage((arguments.first as NSString?)?.lastPathComponent ?? "DeboogeyLoupe")
    }

    let app = try AppIdentity(argument: arguments[1])
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeboogeyLoupe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    let appDefaults = try readDefaults(domain: app.bundleIdentifier)
    try emitFlags(appDefaults, prefix: "defaults", source: "defaults", outputDirectory: outputDirectory)
    let globalDefaults = try readDefaults(domain: "NSGlobalDomain")
    try emitFlags(globalDefaults, prefix: "globalDefaults", source: "globalDefaults", outputDirectory: outputDirectory)
    let systemFeatureFlags = featureFlagFiles(for: app)
    for (path, value) in systemFeatureFlags {
        guard let dictionary = value as? [String: Any] else { continue }
        try emitFlags(
            dictionary,
            prefix: "systemFeatureFlags.\(path)",
            source: "systemFeatureFlags",
            backingFilePath: path,
            outputDirectory: outputDirectory
        )
    }
    let assignedKeys = Set(appDefaults.keys).union(globalDefaults.keys)
    var emissionError: Error?
    streamDisassembledPreferenceKeys(in: app, excluding: assignedKeys) { names in
        guard emissionError == nil else { return }
        do {
            let flags = Dictionary(uniqueKeysWithValues: names.map { ($0, NSNull()) })
            try emitFlags(flags, prefix: "binaryFlags", source: "binaryFlags", outputDirectory: outputDirectory)
        } catch {
            emissionError = error
        }
    }
    if let emissionError { throw emissionError }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
