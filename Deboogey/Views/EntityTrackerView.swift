//
//  EntityTrackerView.swift
//  Deboogey
//
//  Created by Théo De Roy on 05/04/2026.
//

import AppKit
import SwiftUI

struct EntityTrackerView: View {
    @ObservedObject private var tracker = EntityTracker.shared
    @State private var selection = Set<UUID>()
    @State private var revertingID: UUID? = nil
    @State private var errorMessage: String? = nil
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage("deboogey.entityTracker.rowScale") private var rowScale: Double = 1.0
    @AppStorage("deboogey.entityTracker.scaleTarget") private var scaleTarget: String = "both"
    @AppStorage("deboogey.entityTracker.sortOrder") private var sortOrder: SortOrder = .dateNewest
    
    enum SortOrder: String, CaseIterable, Codable {
        case dateNewest = "date_newest"
        case dateOldest = "date_oldest"
        case alphabeticalAction = "alphabetical_action"
        case alphabeticalTarget = "alphabetical_target"
        case alphabeticalTool = "alphabetical_tool"
        
        var displayName: String {
            switch self {
            case .dateNewest: return "Date (Newest First)"
            case .dateOldest: return "Date (Oldest First)"
            case .alphabeticalAction: return "Alphabetical (Action)"
            case .alphabeticalTarget: return "Alphabetical (Target)"
            case .alphabeticalTool: return "Alphabetical (Tool)"
            }
        }
        
        var icon: String {
            switch self {
            case .dateNewest: return "calendar.badge.clock"
            case .dateOldest: return "calendar.badge.clock"
            case .alphabeticalAction: return "textformat.abc"
            case .alphabeticalTarget: return "textformat.abc"
            case .alphabeticalTool: return "wrench.and.screwdriver"
            }
        }
    }

    private var iconScale: Double { scaleTarget != "text" ? rowScale : 1.0 }
    private var textScale: Double { scaleTarget != "icon" ? rowScale : 1.0 }
    
    private var sortedEntities: [TrackedEntity] {
        switch sortOrder {
        case .dateNewest:
            return tracker.entities.sorted { $0.timestamp > $1.timestamp }
        case .dateOldest:
            return tracker.entities.sorted { $0.timestamp < $1.timestamp }
        case .alphabeticalAction:
            return tracker.entities.sorted { $0.summary < $1.summary }
        case .alphabeticalTarget:
            return tracker.entities.sorted { 
                let leftTarget: String
                let rightTarget: String

                switch $0.source {
                case .wsOverlay:
                    leftTarget = $0.overlayArgument ?? ""
                case .ladybug:
                    leftTarget = $0.ladybugDomain ?? ""
                }
                
                switch $1.source {
                case .wsOverlay:
                    rightTarget = $1.overlayArgument ?? ""
                case .ladybug:
                    rightTarget = $1.ladybugDomain ?? ""
                }
                
                return leftTarget < rightTarget
            }
        case .alphabeticalTool:
            return tracker.entities.sorted { $0.source.displayName < $1.source.displayName }
        }
    }

    var body: some View {
        Group {
            if tracker.entities.isEmpty {
                emptyState
            } else {
                entityList
            }
        }
        .frame(width: 560, height: 480)
        .navigationTitle("Entity Tracker")
        .modifier(ToolbarModifier(
            tracker: tracker,
            selection: $selection,
            revertingID: revertingID,
            supersededIDs: supersededIDs,
            presentationMode: presentationMode
        ))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "binoculars")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary)
            Text("No modifications recorded yet.")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Modifications made via Cocoa Debug Menu and SkyLight Diagnostics will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entityList: some View {
        VStack(spacing: 0) {
            if let msg = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button {
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.06))

                Divider()
            }

            List(sortedEntities, selection: $selection) { entity in
                EntityRow(
                    entity: entity,
                    isReverting: revertingID == entity.id,
                    isSuperseded: supersededIDs.contains(entity.id),
                    iconScale: iconScale,
                    textScale: textScale,
                    onRevert: { revertEntity(entity) },
                    onRemoveFromLog: { tracker.remove(ids: [entity.id]) }
                )
                .tag(entity.id)
            }
            .onDeleteCommand {
                tracker.remove(ids: selection)
                selection.removeAll()
            }
        }
    }

    private var supersededIDs: Set<UUID> {
        var seenDomains = Set<String>()
        var seenWsOverlay = false
        var result = Set<UUID>()
        for entity in tracker.entities {
            switch entity.source {
            case .ladybug:
                let domain = entity.ladybugDomain ?? ""
                if seenDomains.contains(domain) {
                    result.insert(entity.id)
                } else {
                    seenDomains.insert(domain)
                }
            case .wsOverlay:
                if seenWsOverlay {
                    result.insert(entity.id)
                } else {
                    seenWsOverlay = true
                }
            }
        }
        return result
    }
    
    private func revertEntity(_ entity: TrackedEntity) {
        guard let args = entity.revertArguments else { return }
        revertingID = entity.id
        errorMessage = nil

        Task {
            do {
                _ = try await MainActor.run { try ladybugLauncher.runLadybugHelper(arguments: args) }
                EntityTracker.shared.record(source: .ladybug, arguments: args)
                revertingID = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                revertingID = nil
            }
        }
    }
}

private struct EntityRow: View {
    let entity: TrackedEntity
    let isReverting: Bool
    let isSuperseded: Bool
    var iconScale: Double = 1.0
    var textScale: Double = 1.0
    let onRevert: () -> Void
    let onRemoveFromLog: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var revertLabel: String {
        entity.ladybugAction == "enable" ? "Revert" : "Swap"
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconImage(entity: entity, iconScale: iconScale)
                .frame(width: 28 * iconScale, height: 28 * iconScale)
                .opacity(isSuperseded ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(entity.summary)
                    .font(.system(size: 13 * textScale))

                HStack(spacing: 6) {
                    Text(entity.source.displayName)
                        .font(.system(size: 11 * textScale))
                        .foregroundColor(.secondary)
                    Text("·")
                        .font(.system(size: 11 * textScale))
                        .foregroundColor(.secondary)
                    Text(Self.dateFormatter.string(from: entity.timestamp))
                        .font(.system(size: 11 * textScale))
                        .foregroundColor(.secondary)
                    if entity.source.isEphemeral {
                        Text("Ephemeral")
                            .font(.system(size: 9 * textScale, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(3)
                    }
                    if isSuperseded {
                        Text("Superseded")
                            .font(.system(size: 9 * textScale, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
            }
            .opacity(isSuperseded ? 0.35 : 1)

            Spacer()

            if isReverting {
                ProgressView()
                    .scaleEffect(0.75)
                    .frame(width: 60)
            } else {
                HStack(spacing: 8) {
                    if entity.revertArguments != nil && !isSuperseded {
                        Button(revertLabel) { onRevert() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Button {
                        onRemoveFromLog()
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help(entity.source.isEphemeral
                        ? "Remove from log (resets automatically on next login)"
                        : "Remove from log")
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if entity.revertArguments != nil && !isSuperseded {
                Button("\(revertLabel) Modification") { onRevert() }
            }
            Button("Remove from Log") { onRemoveFromLog() }
        }
    }
}

private struct AppIconImage: View {
    let entity: TrackedEntity
    var iconScale: Double = 1.0
    @State private var appIcon: NSImage? = nil

    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 22 * iconScale))
                    .foregroundColor(.accentColor)
            }
        }
        .onAppear(perform: loadIcon)
    }

    private var fallbackSystemImage: String {
        switch entity.source {
        case .wsOverlay: return entity.source.systemImage
        case .ladybug:   return entity.ladybugDomain == "global" ? "globe" : entity.source.systemImage
        }
    }

    private func loadIcon() {
        guard entity.source == .ladybug,
              let domain = entity.ladybugDomain,
              domain != "global" else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: domain) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async { appIcon = icon }
        }
    }
}

private struct ToolbarModifier: ViewModifier {
    let tracker: EntityTracker
    @Binding var selection: Set<UUID>
    let revertingID: UUID?
    let supersededIDs: Set<UUID>
    let presentationMode: Binding<PresentationMode>
    @AppStorage("deboogey.entityTracker.sortOrder") private var sortOrder: EntityTrackerView.SortOrder = .dateNewest
    
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
                ToolbarItem(placement: .automatic) {
                    sortMenu(iconOnly: true)
                }
                ToolbarItem(placement: .primaryAction) {
                    actionsMenu(iconOnly: true)
                }
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 4) {
                        sortMenu(iconOnly: false)
                        actionsMenu(iconOnly: false)
                    }
                }
            }
        }
    }
    
    private var closeButton: some View {
        Button("Close") { presentationMode.wrappedValue.dismiss() }
            .disabled(revertingID != nil)
    }
    
    private func sortMenu(iconOnly: Bool) -> some View {
        Menu {
            ForEach(EntityTrackerView.SortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrder = order
                } label: {
                    HStack {
                        Text(order.displayName)
                        if sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            if iconOnly {
                Label("Sort", systemImage: sortOrder.icon)
            } else {
                Image(systemName: sortOrder.icon)
            }
        }
        .if(!iconOnly) { view in
            view.frame(width: 42)
        }
        .help("Sort by \(sortOrder.displayName)")
        .disabled(tracker.entities.isEmpty || revertingID != nil)
    }
    
    private func actionsMenu(iconOnly: Bool) -> some View {
        Menu {
            if !selection.isEmpty {
                Button("Remove \(selection.count) Selected from Log") {
                    tracker.remove(ids: selection)
                    selection.removeAll()
                }
            }
            if !supersededIDs.isEmpty {
                Button("Remove \(supersededIDs.count) Superseded") {
                    tracker.remove(ids: supersededIDs)
                    selection.subtract(supersededIDs)
                }
            }
            if !tracker.entities.isEmpty {
                Button("Clear Entire Log…") {
                    tracker.removeAll()
                    selection.removeAll()
                }
            }
        } label: {
            if iconOnly {
                Image(systemName: "ellipsis.circle")
            } else {
                Image(systemName: "ellipsis.circle")
            }
        }
        .if(!iconOnly) { view in
            view.frame(width: 42)
        }
        .help(iconOnly ? "Actions" : "Log actions")
        .disabled(tracker.entities.isEmpty || revertingID != nil)
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        NavigationStack { EntityTrackerView() }
    } else {
        NavigationView { EntityTrackerView() }
    }
}
