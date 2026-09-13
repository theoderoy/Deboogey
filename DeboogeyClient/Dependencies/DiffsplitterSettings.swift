//
//  DiffsplitterSettings.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation

nonisolated enum DiffsplitterSettings {
    enum Keys {
        static let includeHiddenFiles = "theoderoy.Deboogey.Diffsplitter.includeHiddenFiles"
        static let preferDiskTempForLargeFiles = "theoderoy.Deboogey.Diffsplitter.preferDiskTempForLargeFiles"
        static let hexWindowLines = "theoderoy.Deboogey.Diffsplitter.hexWindowLines"
        static let maxTextMegabytes = "theoderoy.Deboogey.Diffsplitter.maxTextMegabytes"
        static let maxNestDepth = "theoderoy.Deboogey.Diffsplitter.maxNestDepth"
        static let maxEntries = "theoderoy.Deboogey.Diffsplitter.maxEntries"
    }

    static let defaultIncludeHiddenFiles = false
    static let defaultPreferDiskTempForLargeFiles = true
    static let defaultHexWindowLines = 96
    static let hexWindowLinesRange = 32...192
    static let defaultMaxTextMegabytes = 5
    static let maxTextMegabytesRange = 1...64
    static let defaultMaxNestDepth = 8
    static let maxNestDepthRange = 2...16
    static let defaultMaxEntries = 100_000
    static let maxEntriesRange = 10_000...500_000
    static let maxEntriesStops: [Int] = [
        10_000, 50_000, 100_000, 150_000, 200_000,
        250_000, 300_000, 350_000, 400_000, 500_000
    ]
    static var maxEntriesStopIndexRange: ClosedRange<Double> {
        0...Double(maxEntriesStops.count - 1)
    }

    static func includeHiddenFiles(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: Keys.includeHiddenFiles) == nil {
            return defaultIncludeHiddenFiles
        }
        return defaults.bool(forKey: Keys.includeHiddenFiles)
    }

    static func preferDiskTempForLargeFiles(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: Keys.preferDiskTempForLargeFiles) == nil {
            return defaultPreferDiskTempForLargeFiles
        }
        return defaults.bool(forKey: Keys.preferDiskTempForLargeFiles)
    }

    static func hexWindowLines(defaults: UserDefaults = .standard) -> Int {
        clampedInt(
            defaults.object(forKey: Keys.hexWindowLines) as? Int,
            default: defaultHexWindowLines,
            range: hexWindowLinesRange
        )
    }

    static func maxTextMegabytes(defaults: UserDefaults = .standard) -> Int {
        clampedInt(
            defaults.object(forKey: Keys.maxTextMegabytes) as? Int,
            default: defaultMaxTextMegabytes,
            range: maxTextMegabytesRange
        )
    }

    static func maxTextBytes(defaults: UserDefaults = .standard) -> Int {
        maxTextMegabytes(defaults: defaults) * 1024 * 1024
    }

    static func maxNestDepth(defaults: UserDefaults = .standard) -> Int {
        clampedInt(
            defaults.object(forKey: Keys.maxNestDepth) as? Int,
            default: defaultMaxNestDepth,
            range: maxNestDepthRange
        )
    }

    static func maxEntries(defaults: UserDefaults = .standard) -> Int {
        nearestMaxEntriesStop(defaults.object(forKey: Keys.maxEntries) as? Int ?? defaultMaxEntries)
    }

    static func nearestMaxEntriesStop(_ value: Int) -> Int {
        maxEntriesStops.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultMaxEntries
    }

    static func maxEntriesStopIndex(for value: Int) -> Int {
        let stop = nearestMaxEntriesStop(value)
        return maxEntriesStops.firstIndex(of: stop) ?? maxEntriesStops.firstIndex(of: defaultMaxEntries) ?? 0
    }

    static func maxEntriesStop(atIndex index: Int) -> Int {
        let clamped = min(max(index, 0), maxEntriesStops.count - 1)
        return maxEntriesStops[clamped]
    }

    private static func clampedInt(_ value: Int?, default defaultValue: Int, range: ClosedRange<Int>) -> Int {
        let candidate = value ?? defaultValue
        return min(max(candidate, range.lowerBound), range.upperBound)
    }
}
