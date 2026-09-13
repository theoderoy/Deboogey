//
//  LoupeFlag.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation

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
        if let inlineValue { return inlineValue }
#if os(macOS)
        return valueFileURL.flatMap(DeboogeyLoupeLauncher.displayValue(at:))
            ?? L10n.t("DeboogeyLoupe returned an invalid result.")
#else
        return L10n.t("DeboogeyLoupe returned an invalid result.")
#endif
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
