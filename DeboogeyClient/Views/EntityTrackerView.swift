//
//  EntityTrackerView.swift
//  DeboogeyClient
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
    @AppStorage("theoderoy.Deboogey.EntityTracker.rowScale") private var rowScale: Double = 1.0
    @AppStorage("theoderoy.Deboogey.EntityTracker.scaleTarget") private var scaleTarget: String = "both"
    @AppStorage("theoderoy.Deboogey.EntityTracker.sortOrder") private var sortOrder: SortOrder = .dateNewest
    
    enum SortOrder: String, CaseIterable, Codable {
        case dateNewest = "date_newest"
        case dateOldest = "date_oldest"
        case alphabeticalAction = "alphabetical_action"
        case alphabeticalTarget = "alphabetical_target"
        case alphabeticalTool = "alphabetical_tool"
        
        var displayName: String {
            switch self {
            case .dateNewest: return L10n.t("Date (Newest First)")
            case .dateOldest: return L10n.t("Date (Oldest First)")
            case .alphabeticalAction: return L10n.t("Alphabetical (Action)")
            case .alphabeticalTarget: return L10n.t("Alphabetical (Target)")
            case .alphabeticalTool: return L10n.t("Alphabetical (Tool)")
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

    private var visibleEntities: [TrackedEntity] {
        tracker.entities.filter {
#if DEBOOGEY_MCE
            $0.source == .loupeMachine
#else
            true
#endif
        }
    }
    
    private var sortedEntities: [TrackedEntity] {
        switch sortOrder {
        case .dateNewest:
            return visibleEntities.sorted { $0.timestamp > $1.timestamp }
        case .dateOldest:
            return visibleEntities.sorted { $0.timestamp < $1.timestamp }
        case .alphabeticalAction:
            return visibleEntities.sorted { $0.summary < $1.summary }
        case .alphabeticalTarget:
            return visibleEntities.sorted {
                let leftTarget: String
                let rightTarget: String

                switch $0.source {
                case .wsOverlay:
                    leftTarget = $0.overlayArgument ?? ""
                case .deboogeyCDM:
                    leftTarget = $0.deboogeyCDMDomain ?? ""
                case .loupeMachine:
                    leftTarget = $0.loupeApplicationIdentifier ?? $0.loupeActivityTarget ?? ""
                }
                
                switch $1.source {
                case .wsOverlay:
                    rightTarget = $1.overlayArgument ?? ""
                case .deboogeyCDM:
                    rightTarget = $1.deboogeyCDMDomain ?? ""
                case .loupeMachine:
                    rightTarget = $1.loupeApplicationIdentifier ?? $1.loupeActivityTarget ?? ""
                }
                
                return leftTarget < rightTarget
            }
        case .alphabeticalTool:
            return visibleEntities.sorted { $0.source.displayName < $1.source.displayName }
        }
    }

    var body: some View {
        Group {
            if visibleEntities.isEmpty {
                emptyState
            } else {
                entityList
            }
        }
        .frame(width: 560, height: 480)
        .navigationTitle(L10n.t("Entity Tracker"))
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
            Text(L10n.t("No modifications recorded yet."))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(
                L10n.t(
                    DebugVariables.isMarketplaceCandidateEditionBuild
                        ? "Modifications made via Loupe Machine will appear here."
                        : "Modifications made via Cocoa Debug Menu, SkyLight Diagnostics, and Loupe Machine will appear here."
                )
            )
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
        var seenLoupeTargets = Set<String>()
        var seenDeboogeySD = false
        var result = Set<UUID>()
        for entity in tracker.entities {
            switch entity.source {
            case .deboogeyCDM:
                let domain = entity.deboogeyCDMDomain ?? ""
                if seenDomains.contains(domain) {
                    result.insert(entity.id)
                } else {
                    seenDomains.insert(domain)
                }
            case .wsOverlay:
                if seenDeboogeySD {
                    result.insert(entity.id)
                } else {
                    seenDeboogeySD = true
                }
            case .loupeMachine:
                guard entity.loupeActivity == nil else { continue }
                let target = [entity.loupeApplicationIdentifier ?? "", entity.loupeFlagName ?? ""]
                    .joined(separator: "\u{0}")
                if seenLoupeTargets.contains(target) {
                    result.insert(entity.id)
                } else {
                    seenLoupeTargets.insert(target)
                }
            }
        }
        return result
    }
    
    private func revertEntity(_ entity: TrackedEntity) {
#if DEBOOGEY_MCE
        return
#else
        guard let args = entity.revertArguments else { return }
        revertingID = entity.id
        errorMessage = nil

        Task {
            do {
                _ = try await MainActor.run { try DeboogeyCDMLauncher.runDeboogeyCDMHelper(arguments: args) }
                EntityTracker.shared.record(source: .deboogeyCDM, arguments: args)
                revertingID = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                revertingID = nil
            }
        }
#endif
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
        entity.deboogeyCDMAction == "enable" ? L10n.t("Revert") : L10n.t("Swap")
    }

    private var revertModificationLabel: String {
        entity.deboogeyCDMAction == "enable" ? L10n.t("Revert Modification") : L10n.t("Swap Modification")
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
                        Text(L10n.t("Ephemeral"))
                            .font(.system(size: 9 * textScale, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(3)
                    }
                    if isSuperseded {
                        Text(L10n.t("Superseded"))
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
                        ? L10n.t("Remove from log (resets automatically on next login)")
                        : L10n.t("Remove from log"))
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if entity.revertArguments != nil && !isSuperseded {
                Button(revertModificationLabel) { onRevert() }
            }
            Button(L10n.t("Remove from Log")) { onRemoveFromLog() }
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
        case .deboogeyCDM:   return entity.deboogeyCDMDomain == "global" ? "globe" : entity.source.systemImage
        case .loupeMachine: return entity.source.systemImage
        }
    }

    private func loadIcon() {
        let domain: String?
        switch entity.source {
        case .deboogeyCDM: domain = entity.deboogeyCDMDomain
        case .loupeMachine:
            domain = entity.loupeActivity == .applicationIndexed
                ? entity.loupeIndexedApplicationIdentifier
                : entity.loupeApplicationIdentifier
        case .wsOverlay: domain = nil
        }
        guard let domain,
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
    @AppStorage("theoderoy.Deboogey.EntityTracker.sortOrder") private var sortOrder: EntityTrackerView.SortOrder = .dateNewest
    
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.toolbar {
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
        Button(L10n.t("Close")) { presentationMode.wrappedValue.dismiss() }
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
                Label(L10n.t("Sort"), systemImage: sortOrder.icon)
            } else {
                Image(systemName: sortOrder.icon)
            }
        }
        .if(!iconOnly) { view in
            view.frame(width: 42)
        }
        .help(L10n.f("Sort by %@", sortOrder.displayName))
        .disabled(tracker.entities.isEmpty || revertingID != nil)
    }
    
    private func actionsMenu(iconOnly: Bool) -> some View {
        Menu {
            if !selection.isEmpty {
                Button(L10n.f("Remove %d Selected from Log", selection.count)) {
                    tracker.remove(ids: selection)
                    selection.removeAll()
                }
            }
            if !supersededIDs.isEmpty {
                Button(L10n.f("Remove %d Superseded", supersededIDs.count)) {
                    tracker.remove(ids: supersededIDs)
                    selection.subtract(supersededIDs)
                }
            }
            if !tracker.entities.isEmpty {
                Button(L10n.t("Clear Entire Log…")) {
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
        .help(iconOnly ? L10n.t("Actions") : L10n.t("Log actions"))
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
