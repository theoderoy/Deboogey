//
//  TrackedEntity.swift
//  Deboogey
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
        case ladybug
        case wsOverlay

        var displayName: String {
            switch self {
            case .ladybug:   return "Cocoa Debug Menu"
            case .wsOverlay: return "SkyLight Diagnostics"
            }
        }

        var systemImage: String {
            switch self {
            case .ladybug:   return "ladybug"
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

    var ladybugAction: String? {
        source == .ladybug ? arguments.first : nil
    }

    var ladybugDomain: String? {
        source == .ladybug && arguments.count > 1 ? arguments[1] : nil
    }

    var overlayArgument: String? {
        source == .wsOverlay ? arguments.first : nil
    }

    var summary: String {
        switch source {
        case .ladybug:
            let action = ladybugAction.map { $0.capitalized } ?? "?"
            let domain = ladybugDomain.map { $0 == "global" ? "Global" : $0 } ?? "?"
            return "\(action) — \(domain)"
        case .wsOverlay:
            return "Mask: \(overlayArgument ?? "?")"
        }
    }

    var revertArguments: [String]? {
        guard source == .ladybug,
              let action = ladybugAction,
              let domain = ladybugDomain else { return nil }
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
