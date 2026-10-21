//
//  EntityTrackerView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 05/04/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct EntityTrackerView: View {
    @ObservedObject private var tracker = EntityTracker.shared
    @State private var selection = Set<UUID>()
    @State private var revertingID: UUID? = nil
    @State private var errorMessage: String? = nil
    @State private var cachedSupersededIDs = Set<UUID>()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("theoderoy.Deboogey.EntityTracker.rowScale") private var rowScale: Double = 1.0
    @AppStorage("theoderoy.Deboogey.EntityTracker.scaleTarget") private var scaleTarget: String = "system"
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
            case .dateNewest, .dateOldest: return "calendar.badge.clock"
            case .alphabeticalAction, .alphabeticalTarget: return "textformat.abc"
            case .alphabeticalTool: return "wrench.and.screwdriver"
            }
        }
    }

    private var systemDisplayScale: Double {
        switch dynamicTypeSize {
        case .xSmall: return 0.82
        case .small: return 0.88
        case .medium: return 0.94
        case .large: return 1.0
        case .xLarge: return 1.12
        case .xxLarge: return 1.23
        case .xxxLarge: return 1.35
        case .accessibility1: return 1.55
        case .accessibility2: return 1.75
        case .accessibility3: return 1.95
        case .accessibility4: return 2.15
        case .accessibility5: return 2.35
        @unknown default: return 1.0
        }
    }

    private func scale(excluding excluded: String) -> Double {
        switch scaleTarget {
        case "system": return systemDisplayScale
        case excluded: return 1.0
        default: return rowScale
        }
    }

    private var iconScale: Double { scale(excluding: "text") }
    private var textScale: Double { scale(excluding: "icon") }

    private var visibleEntities: [TrackedEntity] {
        tracker.entities.filter {
#if DEBOOGEY_MCE
            $0.source == .loupeMachine || $0.source == .deboogeyCDM || $0.source == .diffsplitter
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
                sortTarget(for: $0) < sortTarget(for: $1)
            }
        case .alphabeticalTool:
            return visibleEntities.sorted { $0.source.displayName < $1.source.displayName }
        }
    }

    private func sortTarget(for entity: TrackedEntity) -> String {
        switch entity.source {
        case .wsOverlay:
            return entity.overlayArgument ?? ""
        case .deboogeyCDM:
            return entity.deboogeyCDMDomain ?? ""
        case .loupeMachine:
            return entity.loupeApplicationIdentifier ?? entity.loupeActivityTarget ?? ""
        case .diffsplitter:
            return entity.diffsplitterActivityTarget ?? ""
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
#if os(macOS)
        .frame(width: AppWindowSizing.entityTracker.defaultSize.width, height: AppWindowSizing.entityTracker.defaultSize.height)
#endif
        .navigationTitle(L10n.t("Entity Tracker"))
        .onAppear { cachedSupersededIDs = computeSupersededIDs() }
        .onReceive(tracker.$entities) { _ in
            cachedSupersededIDs = computeSupersededIDs()
        }
        .modifier(ToolbarModifier(
            tracker: tracker,
            selection: $selection,
            revertingID: revertingID,
            supersededIDs: cachedSupersededIDs,
            dismiss: dismiss
        ))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary)
            Text(L10n.t("No modifications recorded yet."))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(L10n.t(emptyStateDetail))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateDetail: String {
        #if os(iOS)
        "Modifications made by Loupe View and Diffsplitter will appear here."
        #else
        DebugVariables.isMarketplaceCandidateEditionBuild
            ? "Modifications made via Cocoa Debug Menu, Loupe Machine, and Diffsplitter will appear here."
            : "Modifications made via Cocoa Debug Menu, SkyLight Diagnostics, Loupe Machine, and Diffsplitter will appear here."
        #endif
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

            List(selection: $selection) {
                ForEach(sortedEntities) { entity in
                    EntityRow(
                        entity: entity,
                        isReverting: revertingID == entity.id,
                        isSuperseded: cachedSupersededIDs.contains(entity.id),
                        iconScale: iconScale,
                        textScale: textScale,
                        onRevert: { revertEntity(entity) },
                        onRemoveFromLog: { tracker.remove(ids: [entity.id]) }
                    )
                    .tag(entity.id)
                }
                .onDelete(perform: deleteEntities)
            }
#if os(macOS)
            .onDeleteCommand {
                tracker.remove(ids: selection)
                selection.removeAll()
            }
#endif
        }
    }

    private func deleteEntities(at offsets: IndexSet) {
        let ids = Set(offsets.map { sortedEntities[$0].id })
        tracker.remove(ids: ids)
        selection.subtract(ids)
    }

    private func computeSupersededIDs() -> Set<UUID> {
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
            case .diffsplitter:
                continue
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

    private var canRevert: Bool {
#if DEBOOGEY_MCE
        false
#else
        entity.revertArguments != nil && !isSuperseded
#endif
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
                    if canRevert {
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
            if canRevert {
                Button(revertModificationLabel) { onRevert() }
            }
            Button(L10n.t("Remove from Log")) { onRemoveFromLog() }
        }
    }
}

private struct AppIconImage: View {
    let entity: TrackedEntity
    var iconScale: Double = 1.0
#if os(macOS)
    @State private var appIcon: NSImage? = nil
#endif

    var body: some View {
        Group {
#if os(macOS)
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackIconView
            }
#else
            fallbackIconView
#endif
        }
#if os(macOS)
        .onAppear(perform: loadIcon)
#endif
    }

    @ViewBuilder
    private var fallbackIconView: some View {
        let name = fallbackSystemImage
#if os(macOS)
        let hasAsset = NSImage(named: name) != nil
#else
        let hasAsset = UIImage(named: name) != nil
#endif
        if hasAsset {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22 * iconScale, height: 22 * iconScale)
                .foregroundColor(.accentColor)
        } else {
            Image(systemName: name)
                .font(.system(size: 22 * iconScale))
                .foregroundColor(.accentColor)
        }
    }

    private var fallbackSystemImage: String {
        if entity.source == .deboogeyCDM, entity.deboogeyCDMDomain == "global" {
            return "globe"
        }
        return entity.source.systemImage
    }

#if os(macOS)
    private func loadIcon() {
        let domain: String?
        switch entity.source {
        case .deboogeyCDM: domain = entity.deboogeyCDMDomain
        case .loupeMachine:
            domain = entity.loupeActivity == .applicationIndexed
                ? entity.loupeIndexedApplicationIdentifier
                : entity.loupeApplicationIdentifier
        case .wsOverlay, .diffsplitter: domain = nil
        }
        guard let domain,
              domain != "global" else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: domain) else { return }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async { appIcon = icon }
        }
    }
#endif
}

private struct ToolbarModifier: ViewModifier {
    let tracker: EntityTracker
    @Binding var selection: Set<UUID>
    let revertingID: UUID?
    let supersededIDs: Set<UUID>
    let dismiss: DismissAction
    @AppStorage("theoderoy.Deboogey.EntityTracker.sortOrder") private var sortOrder: EntityTrackerView.SortOrder = .dateNewest
    
    func body(content: Content) -> some View {
#if os(iOS)
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                sortMenu(iconOnly: true)
            }
            ToolbarItem(placement: .primaryAction) {
                actionsMenu(iconOnly: true)
            }
        }
#elseif os(macOS)
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
#endif
    }
    
    private var closeButton: some View {
        Button(L10n.t("Close")) { dismiss() }
            .disabled(revertingID != nil)
    }
    
    @ViewBuilder
    private func sortMenu(iconOnly: Bool) -> some View {
        let menu = Menu {
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
        .help(L10n.f("Sort by %@", sortOrder.displayName))
        .disabled(tracker.entities.isEmpty || revertingID != nil)

        if iconOnly {
            menu
        } else {
            menu.frame(width: 42)
        }
    }
    
    @ViewBuilder
    private func actionsMenu(iconOnly: Bool) -> some View {
        let menu = Menu {
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
            Image(systemName: "ellipsis.circle")
        }
        .help(iconOnly ? L10n.t("Actions") : L10n.t("Log actions"))
        .disabled(tracker.entities.isEmpty || revertingID != nil)

        if iconOnly {
            menu
        } else {
            menu.frame(width: 42)
        }
    }
}

#Preview {
#if os(macOS)
    if #available(macOS 13.0, *) {
        NavigationStack { EntityTrackerView() }
    } else {
        NavigationView { EntityTrackerView() }
    }
#else
    NavigationStack { EntityTrackerView() }
#endif
}
