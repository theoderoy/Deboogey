//
//  Localization.swift
//  Deboogey
//
//  Created by Codex on 16/06/2026.
//

import Foundation

enum L10n {
    static var locale: Locale {
        guard let language = DebugVariables.forcedLanguage else {
            return .current
        }

        return Locale(identifier: language.localeIdentifier)
    }

    static func t(_ key: String) -> String {
        guard let language = DebugVariables.forcedLanguage else {
            return NSLocalizedString(key, comment: "")
        }

        guard let bundle = bundle(for: language) else {
            return language == .en ? key : NSLocalizedString(key, comment: "")
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: arguments)
    }

    private static func bundle(for language: DebugVariables.Language) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }

        return Bundle(path: path)
    }
}
