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

#if !DEBOOGEY_MCE
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
#endif

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
    "stringArrayForKey:", "URLForKey:", "objectForKey:",
    "setBool:forKey:", "setInteger:forKey:", "setFloat:forKey:",
    "setDouble:forKey:", "setURL:forKey:", "setObject:forKey:",
    "removeObjectForKey:"
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

#if !DEBOOGEY_MCE
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
#endif

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
    let cfPreferenceFunctions = [
        "CFPreferencesCopyAppValue", "CFPreferencesCopyValue",
        "CFPreferencesGetAppBooleanValue", "CFPreferencesGetAppIntegerValue",
        "CFPreferencesSetAppValue", "CFPreferencesSetValue"
    ]
    if cfPreferenceFunctions.contains(where: symbol.contains) { return 0 }
    if symbol.contains("NSUserDefaults") || symbol.contains("UserDefaults") {
        let readers = ["bool", "integer", "float", "double", "string", "array", "dictionary", "data", "URL", "object"]
        if symbol.contains("removeObjectForKey") { return 1 }
        if symbol.contains("set") && symbol.contains("forKey") { return 2 }
        return symbol.contains("forKey") && readers.contains(where: symbol.contains) ? 1 : nil
    }
    let readerSelectors = [
        "boolForKey:", "integerForKey:", "floatForKey:", "doubleForKey:",
        "stringForKey:", "arrayForKey:", "dictionaryForKey:", "dataForKey:",
        "stringArrayForKey:", "URLForKey:", "objectForKey:"
    ]
    if readerSelectors.contains(where: symbol.contains) || symbol.contains("removeObjectForKey:") { return 2 }
    return symbol.contains("set") && symbol.contains(":forKey:") ? 3 : nil
}

#if !DEBOOGEY_MCE
private func analyzeBinary(at url: URL, didDiscover: (Set<String>) -> Void) -> [FunctionAnalysis] {
    let disassemblyURL = url
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
            arguments: ["-function_starts", "-disassemble", disassemblyURL.path],
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
#else
private enum ByteOrder {
    case little
    case big
}

private func unsigned32(_ data: Data, at offset: Int, order: ByteOrder) -> UInt32? {
    guard offset >= 0, offset + 4 <= data.count else { return nil }
    let bytes = data[offset..<(offset + 4)]
    switch order {
    case .little:
        return bytes.enumerated().reduce(0) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
    case .big:
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

private func unsigned64(_ data: Data, at offset: Int, order: ByteOrder) -> UInt64? {
    guard offset >= 0, offset + 8 <= data.count else { return nil }
    let bytes = data[offset..<(offset + 8)]
    switch order {
    case .little:
        return bytes.enumerated().reduce(0) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
    case .big:
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

private func fixedName(_ data: Data, at offset: Int) -> String? {
    guard offset >= 0, offset + 16 <= data.count else { return nil }
    let bytes = data[offset..<(offset + 16)].prefix { $0 != 0 }
    return String(bytes: bytes, encoding: .utf8)
}

private func thinMachOSlices(in data: Data) -> [Int] {
    guard data.count >= 4 else { return [] }
    let signature = Array(data.prefix(4))
    if signature == [0xcf, 0xfa, 0xed, 0xfe] || signature == [0xfe, 0xed, 0xfa, 0xcf] {
        return [0]
    }

    let isFat32 = signature == [0xca, 0xfe, 0xba, 0xbe]
    let isFat64 = signature == [0xca, 0xfe, 0xba, 0xbf]
    guard isFat32 || isFat64, let count = unsigned32(data, at: 4, order: .big) else { return [] }
    let recordSize = isFat64 ? 32 : 20
    return (0..<Int(count)).compactMap { index in
        let record = 8 + index * recordSize
        if isFat64 {
            return unsigned64(data, at: record + 8, order: .big).flatMap(Int.init(exactly:))
        }
        return unsigned32(data, at: record + 8, order: .big).map(Int.init)
    }
}

private func constantStrings(in data: Data, sliceBase: Int) -> Set<String> {
    guard sliceBase + 32 <= data.count else { return [] }
    let signature = Array(data[sliceBase..<(sliceBase + 4)])
    let order: ByteOrder
    if signature == [0xcf, 0xfa, 0xed, 0xfe] {
        order = .little
    } else if signature == [0xfe, 0xed, 0xfa, 0xcf] {
        order = .big
    } else {
        return []
    }
    guard let commandCount = unsigned32(data, at: sliceBase + 16, order: order) else { return [] }

    struct Segment {
        let address: UInt64
        let fileOffset: UInt64
        let fileSize: UInt64
    }
    var segments: [Segment] = []
    var constantStringSections: [(offset: Int, size: Int)] = []
    var literalStringSections: [(offset: Int, size: Int)] = []
    var commandOffset = sliceBase + 32

    for _ in 0..<Int(commandCount) {
        guard let command = unsigned32(data, at: commandOffset, order: order),
              let commandSize = unsigned32(data, at: commandOffset + 4, order: order),
              commandSize >= 8,
              commandOffset + Int(commandSize) <= data.count else { break }

        if command == UInt32(LC_SEGMENT_64),
           let address = unsigned64(data, at: commandOffset + 24, order: order),
           let fileOffset = unsigned64(data, at: commandOffset + 40, order: order),
           let fileSize = unsigned64(data, at: commandOffset + 48, order: order),
           let sectionCount = unsigned32(data, at: commandOffset + 64, order: order) {
            segments.append(Segment(address: address, fileOffset: fileOffset, fileSize: fileSize))
            for sectionIndex in 0..<Int(sectionCount) {
                let section = commandOffset + 72 + sectionIndex * 80
                guard section + 80 <= commandOffset + Int(commandSize),
                      let sectionName = fixedName(data, at: section),
                      let sectionSize = unsigned64(data, at: section + 40, order: order),
                      let sectionOffset = unsigned32(data, at: section + 48, order: order),
                      let size = Int(exactly: sectionSize) else { continue }
                if sectionName == "__cfstring" {
                    constantStringSections.append((sliceBase + Int(sectionOffset), size))
                } else if sectionName == "__cstring" {
                    literalStringSections.append((sliceBase + Int(sectionOffset), size))
                }
            }
        }
        commandOffset += Int(commandSize)
    }

    func fileOffset(for address: UInt64) -> Int? {
        guard let segment = segments.first(where: {
            address >= $0.address && address - $0.address < $0.fileSize
        }) else { return nil }
        return Int(exactly: UInt64(sliceBase) + segment.fileOffset + (address - segment.address))
    }

    var result = Set<String>()
    for section in constantStringSections {
        guard section.offset >= 0, section.offset + section.size <= data.count else { continue }
        for record in stride(from: section.offset, to: section.offset + section.size, by: 32) {
            guard record + 32 <= section.offset + section.size,
                  let stringAddress = unsigned64(data, at: record + 16, order: order),
                  let length = unsigned64(data, at: record + 24, order: order),
                  length >= 3, length <= 128,
                  let stringOffset = fileOffset(for: stringAddress),
                  stringOffset + Int(length) <= data.count,
                  let value = String(
                    data: data[stringOffset..<(stringOffset + Int(length))],
                    encoding: .utf8
                  ),
                  looksLikePreferenceKey(value),
                  !preferenceSymbolFragments.contains(where: value.contains) else { continue }
            result.insert(value)
        }
    }
    for section in literalStringSections {
        guard section.offset >= 0, section.offset + section.size <= data.count else { continue }
        var start = section.offset
        for offset in section.offset..<(section.offset + section.size) where data[offset] == 0 {
            defer { start = offset + 1 }
            let length = offset - start
            guard length >= 8, length <= 128,
                  let value = String(data: data[start..<offset], encoding: .utf8),
                  looksLikePreferenceKey(value),
                  value.dropFirst().contains(where: \ .isUppercase),
                  !preferenceSymbolFragments.contains(where: value.contains) else { continue }
            result.insert(value)
        }
    }
    return result
}

private struct SandboxedMachOSection {
    let name: String
    let address: UInt64
    let size: UInt64
    let fileOffset: Int
    let flags: UInt32
    let reserved1: UInt32
    let reserved2: UInt32
}

private struct SandboxedMachO {
    struct Segment {
        let address: UInt64
        let fileOffset: UInt64
        let fileSize: UInt64
    }

    let data: Data
    let sliceBase: Int
    let order: ByteOrder
    let cpuType: UInt32
    let segments: [Segment]
    let sections: [SandboxedMachOSection]
    let symbols: [Int: String]
    let definedSymbolsByAddress: [UInt64: String]
    let indirectSymbols: [UInt32]

    init?(data: Data, sliceBase: Int) {
        guard sliceBase + 32 <= data.count else { return nil }
        let signature = Array(data[sliceBase..<(sliceBase + 4)])
        if signature == [0xcf, 0xfa, 0xed, 0xfe] {
            order = .little
        } else if signature == [0xfe, 0xed, 0xfa, 0xcf] {
            order = .big
        } else {
            return nil
        }
        guard let cpuType = unsigned32(data, at: sliceBase + 4, order: order),
              let commandCount = unsigned32(data, at: sliceBase + 16, order: order) else { return nil }
        self.data = data
        self.sliceBase = sliceBase
        self.cpuType = cpuType

        var parsedSegments: [Segment] = []
        var parsedSections: [SandboxedMachOSection] = []
        var symbolTable: (offset: Int, count: Int, strings: Int, stringSize: Int)?
        var indirectTable: (offset: Int, count: Int)?
        var commandOffset = sliceBase + 32

        for _ in 0..<Int(commandCount) {
            guard let command = unsigned32(data, at: commandOffset, order: order),
                  let commandSize = unsigned32(data, at: commandOffset + 4, order: order),
                  commandSize >= 8,
                  commandOffset + Int(commandSize) <= data.count else { return nil }

            if command == UInt32(LC_SEGMENT_64),
               let address = unsigned64(data, at: commandOffset + 24, order: order),
               let fileOffset = unsigned64(data, at: commandOffset + 40, order: order),
               let fileSize = unsigned64(data, at: commandOffset + 48, order: order),
               let sectionCount = unsigned32(data, at: commandOffset + 64, order: order) {
                parsedSegments.append(Segment(address: address, fileOffset: fileOffset, fileSize: fileSize))
                for sectionIndex in 0..<Int(sectionCount) {
                    let section = commandOffset + 72 + sectionIndex * 80
                    guard section + 80 <= commandOffset + Int(commandSize),
                          let name = fixedName(data, at: section),
                          let address = unsigned64(data, at: section + 32, order: order),
                          let size = unsigned64(data, at: section + 40, order: order),
                          let offset = unsigned32(data, at: section + 48, order: order),
                          let flags = unsigned32(data, at: section + 64, order: order),
                          let reserved1 = unsigned32(data, at: section + 68, order: order),
                          let reserved2 = unsigned32(data, at: section + 72, order: order) else { continue }
                    parsedSections.append(SandboxedMachOSection(
                        name: name,
                        address: address,
                        size: size,
                        fileOffset: sliceBase + Int(offset),
                        flags: flags,
                        reserved1: reserved1,
                        reserved2: reserved2
                    ))
                }
            } else if command == UInt32(LC_SYMTAB),
                      let offset = unsigned32(data, at: commandOffset + 8, order: order),
                      let count = unsigned32(data, at: commandOffset + 12, order: order),
                      let strings = unsigned32(data, at: commandOffset + 16, order: order),
                      let stringSize = unsigned32(data, at: commandOffset + 20, order: order) {
                symbolTable = (sliceBase + Int(offset), Int(count), sliceBase + Int(strings), Int(stringSize))
            } else if command == UInt32(LC_DYSYMTAB),
                      let offset = unsigned32(data, at: commandOffset + 56, order: order),
                      let count = unsigned32(data, at: commandOffset + 60, order: order) {
                indirectTable = (sliceBase + Int(offset), Int(count))
            }
            commandOffset += Int(commandSize)
        }
        segments = parsedSegments
        sections = parsedSections

        var parsedSymbols: [Int: String] = [:]
        var parsedDefinedSymbols: [UInt64: String] = [:]
        if let table = symbolTable,
           table.offset >= 0, table.offset + table.count * 16 <= data.count,
           table.strings >= 0, table.strings + table.stringSize <= data.count {
            for index in 0..<table.count {
                let entry = table.offset + index * 16
                guard let stringIndex = unsigned32(data, at: entry, order: order),
                      stringIndex > 0, Int(stringIndex) < table.stringSize else { continue }
                let start = table.strings + Int(stringIndex)
                guard let end = data[start..<(table.strings + table.stringSize)].firstIndex(of: 0),
                      let name = String(data: data[start..<end], encoding: .utf8), !name.isEmpty else { continue }
                parsedSymbols[index] = name
                if let value = unsigned64(data, at: entry + 8, order: order), value != 0 {
                    parsedDefinedSymbols[value] = name
                }
            }
        }
        symbols = parsedSymbols
        definedSymbolsByAddress = parsedDefinedSymbols

        var parsedIndirect: [UInt32] = []
        if let table = indirectTable, table.offset >= 0, table.offset + table.count * 4 <= data.count {
            for index in 0..<table.count {
                if let symbol = unsigned32(data, at: table.offset + index * 4, order: order) {
                    parsedIndirect.append(symbol)
                }
            }
        }
        indirectSymbols = parsedIndirect
    }

    func fileOffset(for address: UInt64) -> Int? {
        guard let segment = segments.first(where: {
            address >= $0.address && address - $0.address < $0.fileSize
        }) else { return nil }
        return Int(exactly: UInt64(sliceBase) + segment.fileOffset + (address - segment.address))
    }

    func pointer(at address: UInt64) -> UInt64? {
        fileOffset(for: address).flatMap { unsigned64(data, at: $0, order: order) }
    }

    func addressCandidates(for encoded: UInt64) -> [UInt64] {
        let imageBase = segments.filter { $0.fileSize > 0 }.map(\ .address).min() ?? 0
        return [
            encoded,
            encoded & 0x0000_ffff_ffff_ffff,
            encoded & 0x0000_000f_ffff_ffff,
            imageBase &+ (encoded & 0x0000_0000_ffff_ffff)
        ]
    }

    var importedSymbolsByAddress: [UInt64: String] {
        var result = definedSymbolsByAddress
        for section in sections {
            let type = section.flags & 0xff
            let stride: Int
            if type == UInt32(S_SYMBOL_STUBS) {
                stride = Int(section.reserved2)
            } else if type == UInt32(S_LAZY_SYMBOL_POINTERS) || type == UInt32(S_NON_LAZY_SYMBOL_POINTERS) {
                stride = 8
            } else {
                continue
            }
            guard stride > 0 else { continue }
            for index in 0..<Int(section.size) / stride {
                let indirectIndex = Int(section.reserved1) + index
                guard indirectIndex < indirectSymbols.count else { break }
                let symbolIndex = indirectSymbols[indirectIndex]
                guard symbolIndex & 0xc0000000 == 0,
                      let name = symbols[Int(symbolIndex)] else { continue }
                result[section.address + UInt64(index * stride)] = name
            }
        }
        return result
    }

    var stringsByAddress: [UInt64: String] {
        var result: [UInt64: String] = [:]
        for section in sections where section.name == "__cstring" || section.name == "__objc_methname" {
            guard let byteCount = Int(exactly: section.size), section.fileOffset >= 0,
                  section.fileOffset + byteCount <= data.count else { continue }
            var start = section.fileOffset
            for offset in section.fileOffset..<(section.fileOffset + byteCount) where data[offset] == 0 {
                defer { start = offset + 1 }
                guard offset > start,
                      let value = String(data: data[start..<offset], encoding: .utf8) else { continue }
                result[section.address + UInt64(start - section.fileOffset)] = value
            }
        }
        for section in sections where section.name == "__cfstring" {
            guard let byteCount = Int(exactly: section.size) else { continue }
            for relativeOffset in stride(from: 0, to: byteCount, by: 32) {
                let record = section.fileOffset + relativeOffset
                guard record + 32 <= data.count,
                      let encodedStringAddress = unsigned64(data, at: record + 16, order: order),
                      let length = unsigned64(data, at: record + 24, order: order),
                      length <= 4096 else { continue }
                guard let stringOffset = addressCandidates(for: encodedStringAddress)
                    .lazy.compactMap(fileOffset(for:)).first,
                      stringOffset + Int(length) <= data.count,
                      let value = String(data: data[stringOffset..<(stringOffset + Int(length))], encoding: .utf8) else { continue }
                result[section.address + UInt64(relativeOffset)] = value
            }
        }
        for section in sections where section.name == "__objc_selrefs" {
            guard let byteCount = Int(exactly: section.size) else { continue }
            for relativeOffset in stride(from: 0, to: byteCount, by: 8) {
                let slotAddress = section.address + UInt64(relativeOffset)
                guard let encodedTarget = pointer(at: slotAddress) else { continue }
                guard let value = addressCandidates(for: encodedTarget)
                    .lazy.compactMap({ result[$0] }).first else { continue }
                result[slotAddress] = value
            }
        }
        return result
    }
}

private enum SandboxedRegisterValue {
    case address(UInt64)
    case literal(String)
    case preferences
}

private func signed(_ value: UInt64, bits: Int) -> Int64 {
    let shift = 64 - bits
    return Int64(bitPattern: value << UInt64(shift)) >> shift
}

private func preferenceKeyArgument(forSelector value: String) -> Int? {
    let readers = [
        "boolForKey:", "integerForKey:", "floatForKey:", "doubleForKey:",
        "stringForKey:", "arrayForKey:", "dictionaryForKey:", "dataForKey:",
        "stringArrayForKey:", "URLForKey:", "objectForKey:"
    ]
    if readers.contains(value) || value == "removeObjectForKey:" { return 2 }
    if value.hasPrefix("set"), value.hasSuffix(":forKey:") { return 3 }
    return nil
}

private func preferenceKey(
    called symbol: String,
    arguments: [Int: SandboxedRegisterValue],
    selector: String?
) -> (key: String?, returnValue: SandboxedRegisterValue?) {
    if symbol.contains("objc_msgSend") {
        let effectiveSelector = selector ?? symbol.split(separator: "$", maxSplits: 1).last.map(String.init)
        if effectiveSelector == "standardUserDefaults" || effectiveSelector == "initWithSuiteName:" {
            return (nil, .preferences)
        }
        if let effectiveSelector, let keyArgument = preferenceKeyArgument(forSelector: effectiveSelector),
           arguments[0].map({ if case .preferences = $0 { return true }; return false }) == true,
           case .literal(let key) = arguments[keyArgument], looksLikePreferenceKey(key) {
            return (key, nil)
        }
        return (nil, nil)
    }
    if symbol.contains("objc_claimAutoreleasedReturnValue")
        || symbol.contains("objc_retainAutoreleasedReturnValue")
        || symbol == "_objc_retain" {
        return (nil, arguments[0])
    }
    guard let keyRegister = preferenceKeyRegister(for: symbol),
          case .literal(let key) = arguments[keyRegister], looksLikePreferenceKey(key) else {
        let returnsPreferences = symbol.contains("standardUserDefaults") || symbol.contains("UserDefaultsC8standard")
        return (nil, returnsPreferences ? .preferences : nil)
    }
    return (key, nil)
}

private func arm64PreferenceKeys(in machO: SandboxedMachO) -> Set<String> {
    let strings = machO.stringsByAddress
    var imports = machO.importedSymbolsByAddress
    for section in machO.sections where section.name == "__objc_stubs" {
        guard let byteCount = Int(exactly: section.size), section.fileOffset >= 0,
              section.fileOffset + byteCount <= machO.data.count else { continue }
        for relativeOffset in stride(from: 0, to: byteCount, by: 32) {
            let fileOffset = section.fileOffset + relativeOffset
            let pc = section.address + UInt64(relativeOffset)
            guard let adrp = unsigned32(machO.data, at: fileOffset, order: machO.order),
                  let ldr = unsigned32(machO.data, at: fileOffset + 4, order: machO.order),
                  adrp & 0x9f00001f == 0x90000001,
                  ldr & 0xffc003ff == 0xf9400021 else { continue }
            let pageImmediate = (UInt64((adrp >> 5) & 0x7ffff) << 2) | UInt64((adrp >> 29) & 0x3)
            let page = Int64(bitPattern: pc & ~UInt64(0xfff))
            let selectorPage = UInt64(bitPattern: page &+ (signed(pageImmediate, bits: 21) << 12))
            let selectorSlot = selectorPage &+ UInt64((ldr >> 10) & 0xfff) * 8
            let selector: String? = strings[selectorSlot] ?? machO.pointer(at: selectorSlot).flatMap { encoded in
                machO.addressCandidates(for: encoded).lazy.compactMap { target -> String? in
                    guard let offset = machO.fileOffset(for: target), offset < machO.data.count,
                          let end = machO.data[offset...].firstIndex(of: 0) else { return nil }
                    return String(data: machO.data[offset..<end], encoding: .utf8)
                }.first
            }
            guard let selector else { continue }
            imports[pc] = "_objc_msgSend$\(selector)"
        }
    }
    var result = Set<String>()

    for section in machO.sections where section.name == "__text" {
        guard let byteCount = Int(exactly: section.size), section.fileOffset >= 0,
              section.fileOffset + byteCount <= machO.data.count else { continue }
        var registers: [Int: SandboxedRegisterValue] = [:]

        func resolved(_ address: UInt64) -> SandboxedRegisterValue {
            strings[address].map(SandboxedRegisterValue.literal) ?? .address(address)
        }

        for relativeOffset in stride(from: 0, to: byteCount, by: 4) {
            guard let instruction = unsigned32(machO.data, at: section.fileOffset + relativeOffset, order: machO.order) else { break }
            let pc = section.address + UInt64(relativeOffset)

            if instruction & 0x9f000000 == 0x90000000 { // ADRP
                let destination = Int(instruction & 0x1f)
                let immediate = (UInt64((instruction >> 5) & 0x7ffff) << 2) | UInt64((instruction >> 29) & 0x3)
                let displacement = signed(immediate, bits: 21) << 12
                let page = Int64(bitPattern: pc & ~UInt64(0xfff))
                registers[destination] = .address(UInt64(bitPattern: page &+ displacement))
                continue
            }
            if instruction & 0x9f000000 == 0x10000000 { // ADR
                let destination = Int(instruction & 0x1f)
                let immediate = (UInt64((instruction >> 5) & 0x7ffff) << 2) | UInt64((instruction >> 29) & 0x3)
                registers[destination] = resolved(UInt64(bitPattern: Int64(bitPattern: pc) &+ signed(immediate, bits: 21)))
                continue
            }
            if instruction & 0x7f000000 == 0x11000000 { // ADD immediate
                let destination = Int(instruction & 0x1f)
                let source = Int((instruction >> 5) & 0x1f)
                let shift = (instruction >> 22) & 0x1
                let immediate = UInt64((instruction >> 10) & 0xfff) << (shift == 1 ? 12 : 0)
                if case .address(let base) = registers[source] {
                    registers[destination] = resolved(base &+ immediate)
                } else if destination != source {
                    registers.removeValue(forKey: destination)
                }
                continue
            }
            if instruction & 0xffc00000 == 0xf9400000 { // LDR 64-bit unsigned immediate
                let destination = Int(instruction & 0x1f)
                let source = Int((instruction >> 5) & 0x1f)
                let immediate = UInt64((instruction >> 10) & 0xfff) * 8
                if case .address(let base) = registers[source], let pointer = machO.pointer(at: base &+ immediate) {
                    registers[destination] = resolved(pointer)
                } else {
                    registers.removeValue(forKey: destination)
                }
                continue
            }
            if instruction & 0xffe0ffe0 == 0xaa0003e0 { // MOV register alias
                let destination = Int(instruction & 0x1f)
                let source = Int((instruction >> 16) & 0x1f)
                registers[destination] = registers[source]
                continue
            }
            if instruction & 0xfc000000 == 0x94000000 { // BL
                let displacement = signed(UInt64(instruction & 0x03ffffff), bits: 26) << 2
                let target = UInt64(bitPattern: Int64(bitPattern: pc) &+ displacement)
                guard let symbol = imports[target] else {
                    for register in 0...18 { registers.removeValue(forKey: register) }
                    continue
                }
                let arguments = Dictionary(uniqueKeysWithValues: (0...7).compactMap { index in
                    registers[index].map { (index, $0) }
                })
                let selector: String?
                if case .literal(let value) = arguments[1] { selector = value } else { selector = nil }
                let outcome = preferenceKey(called: symbol, arguments: arguments, selector: selector)
                if let key = outcome.key { result.insert(key) }
                for register in 0...18 { registers.removeValue(forKey: register) }
                registers[0] = outcome.returnValue
            }
        }
    }
    return result
}

private func x86PreferenceKeys(in machO: SandboxedMachO) -> Set<String> {
    let strings = machO.stringsByAddress
    let imports = machO.importedSymbolsByAddress
    let argumentRegisters = [7, 6, 2, 1, 8, 9] // rdi, rsi, rdx, rcx, r8, r9
    var result = Set<String>()

    for section in machO.sections where section.name == "__text" {
        guard let byteCount = Int(exactly: section.size), section.fileOffset >= 0,
              section.fileOffset + byteCount <= machO.data.count else { continue }
        var registers: [Int: SandboxedRegisterValue] = [:]
        var offset = 0
        while offset < byteCount {
            let fileOffset = section.fileOffset + offset
            let pc = section.address + UInt64(offset)
            let first = machO.data[fileOffset]

            if first >= 0x48 && first <= 0x4f, offset + 7 <= byteCount {
                let opcode = machO.data[fileOffset + 1]
                let modRM = machO.data[fileOffset + 2]
                if (opcode == 0x8d || opcode == 0x8b), modRM & 0xc7 == 0x05,
                   let displacement = unsigned32(machO.data, at: fileOffset + 3, order: .little) {
                    let rexR = Int((first >> 2) & 1) << 3
                    let destination = Int((modRM >> 3) & 7) | rexR
                    let address = UInt64(bitPattern: Int64(bitPattern: pc + 7) &+ Int64(Int32(bitPattern: displacement)))
                    if opcode == 0x8b, let pointer = machO.pointer(at: address) {
                        registers[destination] = strings[pointer].map(SandboxedRegisterValue.literal) ?? .address(pointer)
                    } else {
                        registers[destination] = strings[address].map(SandboxedRegisterValue.literal) ?? .address(address)
                    }
                    offset += 7
                    continue
                }
            }
            if first == 0xe8, offset + 5 <= byteCount,
               let displacement = unsigned32(machO.data, at: fileOffset + 1, order: .little) {
                let target = UInt64(bitPattern: Int64(bitPattern: pc + 5) &+ Int64(Int32(bitPattern: displacement)))
                if let symbol = imports[target] {
                    let arguments = Dictionary(uniqueKeysWithValues: argumentRegisters.enumerated().compactMap { index, register in
                        registers[register].map { (index, $0) }
                    })
                    let selector: String?
                    if case .literal(let value) = arguments[1] { selector = value } else { selector = nil }
                    let outcome = preferenceKey(called: symbol, arguments: arguments, selector: selector)
                    if let key = outcome.key { result.insert(key) }
                    registers.removeAll(keepingCapacity: true)
                    registers[0] = outcome.returnValue
                }
                offset += 5
                continue
            }
            offset += 1
        }
    }
    return result
}

private func disassembledPreferenceKeys(in data: Data, sliceBase: Int) -> Set<String> {
    guard let machO = SandboxedMachO(data: data, sliceBase: sliceBase) else { return [] }
    if machO.cpuType == UInt32(bitPattern: CPU_TYPE_ARM64) {
        return arm64PreferenceKeys(in: machO)
    }
    if machO.cpuType == UInt32(bitPattern: CPU_TYPE_X86_64) {
        return x86PreferenceKeys(in: machO)
    }
    return []
}

private func streamSandboxedDisassembledPreferenceKeys(
    in app: AppIdentity,
    didDiscover: @escaping ([String]) -> Void
) {
    let binaries = inspectableBinaries(in: app)
    for binary in binaries {
        guard let data = try? Data(contentsOf: binary, options: .mappedIfSafe) else { continue }
        let slices = thinMachOSlices(in: data)
        let keys = slices.reduce(into: Set<String>()) {
            $0.formUnion(disassembledPreferenceKeys(in: data, sliceBase: $1))
        }

        let sorted = keys.sorted()
        for start in stride(from: 0, to: sorted.count, by: 64) {
            didDiscover(Array(sorted[start..<min(start + 64, sorted.count)]))
        }
    }
}
#endif

private func bundledRegistrationDefaults(for app: AppIdentity) -> [String: Any] {
    let resources = app.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    let manifestNames = ["Defaults.plist", "DefaultPreferences.plist"]
    var result: [String: Any] = [:]

    for name in manifestNames {
        let url = resources.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let dictionary = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else { continue }
        for (key, value) in dictionary where looksLikePreferenceKey(key) {
            result[key] = normalizedForJSON(value)
        }
    }

    let settingsURL = resources.appendingPathComponent("Settings.bundle/Root.plist")
    if let data = try? Data(contentsOf: settingsURL),
       let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
       let specifiers = root["PreferenceSpecifiers"] as? [[String: Any]] {
        for specifier in specifiers {
            guard let key = specifier["Key"] as? String, looksLikePreferenceKey(key) else { continue }
            result[key] = normalizedForJSON(specifier["DefaultValue"] ?? NSNull())
        }
    }

    return result
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

#if DEBOOGEY_MCE
    guard let encodedBookmark = ProcessInfo.processInfo.environment["DEBOOGEY_LOUPE_APP_BOOKMARK"],
          let bookmark = Data(base64Encoded: encodedBookmark) else {
        throw LoupeError.defaultsFailed("The selected application permission is unavailable.")
    }
    var bookmarkIsStale = false
    let bookmarkedURL = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &bookmarkIsStale
    )
    guard !bookmarkIsStale else {
        throw LoupeError.defaultsFailed("The selected application permission has expired.")
    }
    let isAccessingApplication = bookmarkedURL.startAccessingSecurityScopedResource()
    defer {
        if isAccessingApplication { bookmarkedURL.stopAccessingSecurityScopedResource() }
    }
    let app = try AppIdentity(argument: bookmarkedURL.path)
#else
    let app = try AppIdentity(argument: arguments[1])
#endif
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeboogeyLoupe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
#if !DEBOOGEY_MCE
    let appDefaults = try readDefaults(domain: app.bundleIdentifier)
    try emitFlags(appDefaults, prefix: "defaults", source: "defaults", outputDirectory: outputDirectory)
    let globalDefaults = try readDefaults(domain: "NSGlobalDomain")
    try emitFlags(globalDefaults, prefix: "globalDefaults", source: "globalDefaults", outputDirectory: outputDirectory)
    let assignedKeys = Set(appDefaults.keys).union(globalDefaults.keys)
#else
    let bundledDefaults = bundledRegistrationDefaults(for: app)
    try emitFlags(
        bundledDefaults,
        prefix: "binaryFlags",
        source: "binaryFlags",
        outputDirectory: outputDirectory
    )
    let assignedKeys = Set(bundledDefaults.keys)
#endif
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
    var emissionError: Error?
    let emitDiscoveredNames: ([String]) -> Void = { names in
        guard emissionError == nil else { return }
        do {
            let flags = Dictionary(uniqueKeysWithValues: names.map { ($0, NSNull()) })
            try emitFlags(flags, prefix: "binaryFlags", source: "binaryFlags", outputDirectory: outputDirectory)
        } catch {
            emissionError = error
        }
    }
#if DEBOOGEY_MCE
    streamSandboxedDisassembledPreferenceKeys(in: app) { names in
        emitDiscoveredNames(names.filter { !assignedKeys.contains($0) })
    }
#else
    streamDisassembledPreferenceKeys(in: app, excluding: assignedKeys, didDiscover: emitDiscoveredNames)
#endif
    if let emissionError { throw emissionError }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
