//
//  TrackedEntity.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 05/04/2026.
//

import Foundation
import Combine
import Darwin

struct TrackedEntity: Identifiable, Codable, Equatable {
    let id: UUID
    let source: Source
    let timestamp: Date
    let arguments: [String]

    enum Source: String, Codable {
        case deboogeyCDM
        case wsOverlay
        case loupeMachine

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            switch value {
            case Self.deboogeyCDM.rawValue, ["lady", "bug"].joined():
                self = .deboogeyCDM
            case Self.wsOverlay.rawValue:
                self = .wsOverlay
            case Self.loupeMachine.rawValue:
                self = .loupeMachine
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown tracked entity source: \(value)"
                )
            }
        }

        var displayName: String {
            switch self {
            case .deboogeyCDM:   return L10n.t("Cocoa Debug Menu")
            case .wsOverlay: return L10n.t("SkyLight Diagnostics")
            case .loupeMachine: return L10n.t("Loupe Machine")
            }
        }

        var systemImage: String {
            switch self {
            case .deboogeyCDM:   return "wrench.and.screwdriver"
            case .wsOverlay: return "macwindow"
            case .loupeMachine: return "scope"
            }
        }

        var isEphemeral: Bool { self == .wsOverlay }
    }

    enum LoupeActivity: String {
        case documentCreated = "__loumDocumentCreated"
        case documentModified = "__loumDocumentModified"
        case applicationIndexed = "__applicationCompletelyIndexed"

        var summaryFormat: String {
            switch self {
            case .documentCreated: return L10n.t(".loum file was created — %@")
            case .documentModified: return L10n.t(".loum file was modified — %@")
            case .applicationIndexed: return L10n.t("%@ was completely indexed")
            }
        }
    }

    init(source: Source, arguments: [String]) {
        self.id = UUID()
        self.source = source
        self.timestamp = Date()
        self.arguments = arguments
    }

    var deboogeyCDMAction: String? {
        source == .deboogeyCDM ? arguments.first : nil
    }

    var deboogeyCDMDomain: String? {
        source == .deboogeyCDM && arguments.count > 1 ? arguments[1] : nil
    }

    var overlayArgument: String? {
        source == .wsOverlay ? arguments.first : nil
    }

    var loupeFlagName: String? {
        source == .loupeMachine ? arguments.first : nil
    }

    var loupeApplicationIdentifier: String? {
        source == .loupeMachine && loupeActivity == nil && arguments.count > 1 ? arguments[1] : nil
    }

    var loupeActivity: LoupeActivity? {
        guard source == .loupeMachine, let marker = arguments.first else { return nil }
        return LoupeActivity(rawValue: marker)
    }

    var loupeActivityTarget: String? {
        loupeActivity != nil && arguments.count > 1 ? arguments[1] : nil
    }

    var loupeIndexedApplicationIdentifier: String? {
        guard loupeActivity == .applicationIndexed else { return nil }
        return arguments.count > 2 ? arguments[2] : loupeActivityTarget
    }

    var summary: String {
        switch source {
        case .deboogeyCDM:
            let action = localizedDeboogeyCDMAction ?? "?"
            let domain = deboogeyCDMDomain.map { $0 == "global" ? L10n.t("Global") : $0 } ?? "?"
            return "\(action) — \(domain)"
        case .wsOverlay:
            return L10n.f("Mask: %@", overlayArgument ?? "?")
        case .loupeMachine:
            if let activity = loupeActivity {
                return String(format: activity.summaryFormat, loupeActivityTarget ?? "?")
            }
            return "\(loupeFlagName ?? "?") — \(loupeApplicationIdentifier ?? "?")"
        }
    }

    private var localizedDeboogeyCDMAction: String? {
        switch deboogeyCDMAction {
        case "enable": return L10n.t("Enable")
        case "disable": return L10n.t("Disable")
        case let action?: return action.capitalized
        case nil: return nil
        }
    }

    var revertArguments: [String]? {
        guard source == .deboogeyCDM,
              let action = deboogeyCDMAction,
              let domain = deboogeyCDMDomain else { return nil }
        let inverse = action == "enable" ? "disable" : "enable"
        var args = [inverse, domain]
        if arguments.contains("--autokill") { args.append("--autokill") }
        return args
    }
}

final class EntityTracker: ObservableObject {
    static let shared = EntityTracker()

    @Published private(set) var entities: [TrackedEntity] = []

    private let defaultsKey = "theoderoy.Deboogey.EntityTracker.entities"

    private init() { load() }

    func record(source: TrackedEntity.Source, arguments: [String]) {
        let entity = TrackedEntity(source: source, arguments: arguments)
        entities.insert(entity, at: 0)
        save()
    }

    func remove(ids: Set<UUID>) {
        entities.removeAll { ids.contains($0.id) }
        save()
    }

    func removeEphemerals() {
        entities.removeAll { $0.source.isEphemeral }
        save()
    }

    func removeAll(includingLoupeActivities: Bool = true) {
        if includingLoupeActivities {
            entities.removeAll()
        } else {
            entities.removeAll { $0.loupeActivity == nil }
        }
        save()
    }

    func performConfiguredAutoRemoval(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: "theoderoy.Deboogey.EntityTracker.autoDeleteEnabled") else { return }

        let trigger = defaults.string(forKey: "theoderoy.Deboogey.EntityTracker.autoDeleteTrigger") ?? "login"
        let shouldDelete: Bool
        if trigger == "launch" {
            shouldDelete = true
        } else {
            let sessionKey = "theoderoy.Deboogey.EntityTracker.lastKnownSessionID"
            let currentSession = Self.loginSessionID()
            shouldDelete = defaults.string(forKey: sessionKey) != currentSession
            if shouldDelete { defaults.set(currentSession, forKey: sessionKey) }
        }
        guard shouldDelete else { return }

        let includeLoupeActivities = defaults.bool(
            forKey: "theoderoy.Deboogey.EntityTracker.autoDeleteLoupeActivities"
        )
#if DEBOOGEY_MCE
        removeAll(includingLoupeActivities: includeLoupeActivities)
#else
        switch defaults.string(forKey: "theoderoy.Deboogey.EntityTracker.autoDeleteScope") ?? "ephemerals" {
        case "ephemerals": removeEphemerals()
        case "all": removeAll(includingLoupeActivities: includeLoupeActivities)
        default: break
        }
#endif
    }

    private static func loginSessionID() -> String {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        let bootTimestamp = sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0
            ? bootTime.tv_sec
            : Int(Date().timeIntervalSince1970)
        return "\(bootTimestamp)-\(getuid())-\(getsid(0))"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entities) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([TrackedEntity].self, from: data) else { return }
        entities = decoded
    }
}
