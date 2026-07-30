//
//  DebugVariables.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 15/06/2026.
//

import Foundation

enum DebugVariables {
    enum VersionType: String, CaseIterable {
        case release = "Release"
        case `internal` = "Internal"
        case development = "Development"
#if DEBOOGEY_MCE
        case marketplaceCandidateEdition = "Marketplace Candidate Edition"
#endif

        var localizedName: String {
            L10n.t(rawValue)
        }

        init?(marketingVersion: String) {
            let value = marketingVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = Self.allCases.first(where: {
                value.caseInsensitiveCompare($0.rawValue) == .orderedSame
                    || value.lowercased().hasPrefix("\($0.rawValue.lowercased()) ")
            }) else {
                return nil
            }
            self = match
        }
    }

    enum Language: String {
        case en = "en-GB"
        case fr

        nonisolated var localeIdentifier: String {
            switch self {
            case .en: return "en_GB"
            case .fr: return "fr_FR"
            }
        }
    }

    static var auxiliaryUpgrades = false
    static var alwaysShowWhatsNewView = false
    static var alwaysShowLMEducation = false
    static var pseudoSystemIntegrityProtection = false
    nonisolated(unsafe) static var forcedLanguage: Language? = nil
    static var forcedVersionType: VersionType? = nil

    static var bundledVersionType: VersionType? {
        let marketingVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        return VersionType(marketingVersion: marketingVersion)
    }

    static var effectiveVersionType: VersionType? {
        forcedVersionType ?? bundledVersionType
    }

    static var isMarketplaceCandidateEditionBuild: Bool {
#if DEBOOGEY_MCE
        true
#else
        false
#endif
    }
}
