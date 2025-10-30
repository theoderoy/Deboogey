//
//  PersistentVariables.swift
//  Deboogey
//
//  Created by Théo De Roy on 26/10/2025.
//

import Foundation
import AppKit
import Combine

public final class PersistentVariables: ObservableObject {
    private enum Keys {
        static let pesterMeWithSipping = "pesterMeWithSipping"
    }

    private let defaults: UserDefaults

    private static let registeredDefaults: [String: Any] = [
        Keys.pesterMeWithSipping: true
    ]

    @Published public var pesterMeWithSipping: Bool {
        didSet { defaults.set(pesterMeWithSipping, forKey: Keys.pesterMeWithSipping) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaults.register(defaults: Self.registeredDefaults)
        self.pesterMeWithSipping = self.defaults.bool(forKey: Keys.pesterMeWithSipping)
    }
    
    public func theThirdImpact() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: bundleID)
        defaults.synchronize()

        let alert = NSAlert()
        alert.messageText = "Deboogey has been reset."
        alert.informativeText = "The app will now quit."
        alert.addButton(withTitle: "OK")

        alert.runModal()
        NSApp.terminate(nil)
    }
}
