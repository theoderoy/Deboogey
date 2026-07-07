//
//  TrackedEntity.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 05/04/2026.
//

import Foundation
import Combine

struct TrackedEntity: Identifiable, Codable, Equatable {
    let id: UUID
    let source: Source
    let timestamp: Date
    let arguments: [String]

    enum Source: String, Codable {
        case deboogeyCDM
        case wsOverlay

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            switch value {
            case Self.deboogeyCDM.rawValue, ["lady", "bug"].joined():
                self = .deboogeyCDM
            case Self.wsOverlay.rawValue:
                self = .wsOverlay
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
            }
        }

        var systemImage: String {
            switch self {
            case .deboogeyCDM:   return "wrench.and.screwdriver"
            case .wsOverlay: return "macwindow"
            }
        }

        var isEphemeral: Bool { self == .wsOverlay }
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

    var summary: String {
        switch source {
        case .deboogeyCDM:
            let action = localizedDeboogeyCDMAction ?? "?"
            let domain = deboogeyCDMDomain.map { $0 == "global" ? L10n.t("Global") : $0 } ?? "?"
            return "\(action) — \(domain)"
        case .wsOverlay:
            return L10n.f("Mask: %@", overlayArgument ?? "?")
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

    private let defaultsKey = "deboogey.entityTracker.entities"

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

    func removeAll() {
        entities.removeAll()
        save()
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
