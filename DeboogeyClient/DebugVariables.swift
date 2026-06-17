//
//  DebugVariables.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 15/06/2026.
//

enum DebugVariables {
    enum Language: String {
        case en = "en-GB"
        case fr

        var localeIdentifier: String {
            switch self {
            case .en: return "en_GB"
            case .fr: return "fr_FR"
            }
        }
    }

    static var auxiliaryUpgrades = false
    static var alwaysShowWhatsNewView = false
    static var forcedLanguage: Language? = nil
}
