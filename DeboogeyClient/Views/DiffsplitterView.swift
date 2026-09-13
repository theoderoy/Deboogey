//
//  DiffsplitterView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 02/09/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

struct DiffsplitterCommandActions {
    let canSave: Bool
    let canExportDiffsplitterX: Bool
    let save: () -> Void
    let saveAs: () -> Void
    let exportDiffsplitterX: () -> Void
}

@MainActor
final class DiffsplitterCommandRouter: ObservableObject {
    static let shared = DiffsplitterCommandRouter()
    @Published private(set) var canSave = false
    @Published private(set) var canExportDiffsplitterX = false
    private var actionsByWindow: [ObjectIdentifier: DiffsplitterCommandActions] = [:]
    func register(_ actions: DiffsplitterCommandActions, for window: NSWindow) {
        actionsByWindow[ObjectIdentifier(window)] = actions
        if NSApp.keyWindow === window {
            canSave = actions.canSave
            canExportDiffsplitterX = actions.canExportDiffsplitterX
            if canSave || canExportDiffsplitterX { LoupeMachineCommandRouter.shared.resignActiveSave() }
        }
    }
    func activate(_ window: NSWindow) {
        let actions = actionsByWindow[ObjectIdentifier(window)]
        canSave = actions?.canSave == true
        canExportDiffsplitterX = actions?.canExportDiffsplitterX == true
        LoupeMachineCommandRouter.shared.resignActiveSave()
    }
    func resignActiveSave() {
        canSave = false
        canExportDiffsplitterX = false
    }
    func unregister(_ window: NSWindow) {
        actionsByWindow.removeValue(forKey: ObjectIdentifier(window))
        if NSApp.keyWindow === window {
            canSave = false
            canExportDiffsplitterX = false
        }
    }
    @discardableResult
    func saveIfPossible(saveAs: Bool) -> Bool {
        guard let window = NSApp.keyWindow,
              let actions = actionsByWindow[ObjectIdentifier(window)],
              actions.canSave else { return false }
        saveAs ? actions.saveAs() : actions.save()
        return true
    }
    func save(saveAs: Bool) {
        _ = saveIfPossible(saveAs: saveAs)
    }
    @discardableResult
    func exportDiffsplitterXIfPossible() -> Bool {
        guard let window = NSApp.keyWindow,
              let actions = actionsByWindow[ObjectIdentifier(window)],
              actions.canExportDiffsplitterX else { return false }
        actions.exportDiffsplitterX()
        return true
    }
}

@MainActor

enum DocumentSaveDispatcher {
    static var canSave: Bool {
        LoupeMachineCommandRouter.shared.canSave || DiffsplitterCommandRouter.shared.canSave
    }
    static var canExportDiffsplitterX: Bool {
        DiffsplitterCommandRouter.shared.canExportDiffsplitterX
    }
    static func save(saveAs: Bool) {
        if DiffsplitterCommandRouter.shared.saveIfPossible(saveAs: saveAs) { return }
        LoupeMachineCommandRouter.shared.save(saveAs: saveAs)
    }
    static func exportDiffsplitterX() {
        _ = DiffsplitterCommandRouter.shared.exportDiffsplitterXIfPossible()
    }
}

final class DocumentSaveDispatcherBridge: ObservableObject {
    static let shared = DocumentSaveDispatcherBridge()
    private var loupeBag: AnyCancellable?
    private var diffBag: AnyCancellable?
    private var diffExportBag: AnyCancellable?
    @Published private(set) var canSave = false
    @Published private(set) var canExportDiffsplitterX = false
    private init() {
        loupeBag = LoupeMachineCommandRouter.shared.$canSave.sink { [weak self] _ in
            self?.refresh()
        }
        diffBag = DiffsplitterCommandRouter.shared.$canSave.sink { [weak self] _ in
            self?.refresh()
        }
        diffExportBag = DiffsplitterCommandRouter.shared.$canExportDiffsplitterX.sink { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }
    private func refresh() {
        canSave = DocumentSaveDispatcher.canSave
        canExportDiffsplitterX = DocumentSaveDispatcher.canExportDiffsplitterX
    }
}

struct DiffsplitterView: View {
    let request: DiffsplitterWindowRequest
    @StateObject private var session = DiffsplitterSession()
    @State private var statusPriorityRaw = PersistentVariables.loadDiffsplitterStatusPriority()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var statusPriority: [DiffsplitterEngine.DirEntryStatus] {
        DiffsplitterEngine.statusPriority(fromRawValues: statusPriorityRaw)
    }
    private var needsInlineWindowChrome: Bool {
        if #available(macOS 13.0, *) { return false }
        return true
    }
    var body: some View {
        VStack(spacing: 0) {
            if needsInlineWindowChrome, session.isReady {
                inlineWindowToolbar
                Divider()
            }
            Group {
                if session.isReady {
                    compareView
                } else {
                    setupView
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: PersistentVariables.diffsplitterStatusPriorityDidChange
            )
        ) { _ in
            statusPriorityRaw = PersistentVariables.loadDiffsplitterStatusPriority()
        }
        .minimumWindowContentSize(AppWindowSizing.diffsplitter)
        .background(
            DiffsplitterWindowCoordinator(
                hasUnsavedChanges: session.hasUnsavedDocumentChanges,
                documentURL: session.documentURL,
                commandActions: DiffsplitterCommandActions(
                    canSave: session.hasBothSides,
                    canExportDiffsplitterX: session.canExportDiffsplitterX,
                    save: { session.saveDocument(forceSaveAs: false) },
                    saveAs: { session.saveDocument(forceSaveAs: true) },
                    exportDiffsplitterX: { session.exportDiffsplitterXDocument() }
                ),
                saveDraft: session.saveDraftForClosing
            )
        )
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if session.isReady {
                    toolbarActionControls
                }
            }
        }
        .onChange(of: session.ignoreWhitespace) { _ in
            session.applyIgnoreWhitespaceChange()
        }
        .onChange(of: session.documentError) { message in
            session.presentMessageAlert(
                title: L10n.t("Diffsplitter Document Error"),
                message: message
            ) {
                session.documentError = nil
            }
        }
        .onChange(of: session.setupError) { message in
            session.presentMessageAlert(
                title: L10n.t("Diffsplitter Error"),
                message: message
            ) {
                session.setupError = nil
            }
        }
        .onChange(of: session.aeaKeyPrompt?.id) { _ in
            session.presentAEAKeyPromptIfNeeded()
        }
        .onAppear {
            session.reduceMotion = reduceMotion
            session.handleDocumentRequest(request)
        }
        .onDisappear {
            session.cancelAndClose()
        }
        .overlay {
            if let progress = session.documentTransferProgress {
                ZStack {
                    Color.primary.opacity(0.12)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(progress.status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(minWidth: 240)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(progress.status)
            }
        }
    }
    private var setupView: some View {
        ZStack {
            DiffsplitterEmptyBackground()

            VStack(spacing: 28) {
                HStack(spacing: 14) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 52, weight: .thin))
                        .foregroundStyle(.white.opacity(0.72))
                        .symbolRenderingMode(.hierarchical)
                    Text(L10n.t("Diffsplitter"))
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 20) {
                    dropWell(
                        title: L10n.t("Left"),
                        url: session.leftURL,
                        isTargeted: session.leftDropTargeted,
                        side: .left
                    )
                    dropWell(
                        title: L10n.t("Right"),
                        url: session.rightURL,
                        isTargeted: session.rightDropTargeted,
                        side: .right
                    )
                }
                .frame(maxWidth: 760)
                if session.isComparing {
                    indexingProgressChrome
                        .frame(maxWidth: 420)
                        .foregroundStyle(.white.opacity(0.75))
                        .tint(.white)
                } else {
                    Text(L10n.t("Drop two text files, or two folders or archives — one on each side — to compare them."))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }
            }
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var indexingProgressChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let indexProgress = session.indexProgress {
                ProgressView(value: indexProgress.fractionCompleted)
                    .progressViewStyle(.linear)
                Text(indexProgress.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let memberLoadProgress = session.memberLoadProgress {
                ProgressView(value: memberLoadProgress.fractionCompleted)
                    .progressViewStyle(.linear)
                Text(memberLoadProgress.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(L10n.t("Comparing…"))
            }
        }
    }
    private func dropWell(title: String, url: URL?, isTargeted: Bool, side: DiffsplitterSession.Side) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            dropWellGlass(isTargeted: isTargeted, side: side) {
                dropWellContent(url: url, side: side)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dropWellGlass<Content: View>(
        isTargeted: Bool,
        side: DiffsplitterSession.Side,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let well = content()
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(.clear, in: shape)
            .overlay {
                shape
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.white.opacity(0.35),
                        style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: [9, 7])
                    )
            }
            .scaleEffect(isTargeted ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: isTargeted)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: binding(for: side)) { providers in
                session.handleDrop(providers, onto: side)
            }

        if #available(macOS 26.0, *) {
            well
                .glassEffect(
                    .clear.tint(.accentColor.opacity(0.15)).interactive(),
                    in: shape
                )
        } else {
            well
        }
    }

    @ViewBuilder
    private func dropWellContent(url: URL?, side: DiffsplitterSession.Side) -> some View {
        VStack(spacing: 12) {
            Image(systemName: url.map { session.isDirectoryLike($0) ? "folder" : "doc.text" } ?? "plus.rectangle.on.folder")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.white.opacity(0.7))
            if let url {
                Text(url.lastPathComponent)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else {
                Text(L10n.t("Drop a file, folder, or archive here"))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            Button(L10n.t("Import…")) {
                session.presentOpenPanel(for: side)
            }
            .controlSize(.large)
            .colorScheme(.dark)
        }
    }
    private func binding(for side: DiffsplitterSession.Side) -> Binding<Bool> {
        switch side {
        case .left: return $session.leftDropTargeted
        case .right: return $session.rightDropTargeted
        }
    }
    private var compareView: some View {
        VStack(spacing: 0) {
            if session.indexProgress != nil
                || (session.memberLoadProgress != nil && session.selectedRelativePath == nil) {
                indexingProgressChrome
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }
            if session.isEmbeddedDocument {
                evenColumns
            } else if session.comparisonKind == .directories {
                directoryNavigationRoot
            } else {
                evenColumns
            }
        }
    }
    @ViewBuilder
    private var directoryNavigationRoot: some View {
        if let path = session.selectedRelativePath {
            directoryMemberDetail(path: path)
                .modifier(DiffsplitterDirectoryBackToolbarModifier {
                    session.leaveDirectoryDetail()
                })
        } else if session.directoryBrowsePrefix.isEmpty {
            directoryListRoot
        } else {
            directoryListRoot
                .modifier(DiffsplitterDirectoryBackToolbarModifier {
                    session.leaveDirectoryBrowseLevel()
                })
        }
    }
    private var isShowingDirectoryList: Bool {
        !session.isEmbeddedDocument
            && session.comparisonKind == .directories
            && session.selectedRelativePath == nil
    }
    private var isShowingFileDiffChrome: Bool {
        session.isEmbeddedDocument
            || session.comparisonKind == .files
            || session.selectedRelativePath != nil
    }
    private var showsDirectoryBackButton: Bool {
        !session.isEmbeddedDocument
            && session.comparisonKind == .directories
            && (session.selectedRelativePath != nil || !session.directoryBrowsePrefix.isEmpty)
    }
    private var inlineWindowToolbar: some View {
        HStack(spacing: 8) {
            if showsDirectoryBackButton {
                directoryBackButton
            }
            Spacer(minLength: 8)
            toolbarActionControls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    @ViewBuilder
    private var toolbarActionControls: some View {
        if isShowingDirectoryList {
            directoryStatusFilterCircles
        }
        Button {
            session.ignoreWhitespace.toggle()
        } label: {
            Image(systemName: session.ignoreWhitespace ? "textformat.size" : "textformat")
        }
        .help(L10n.t("Ignore Whitespace"))
        .accessibilityLabel(L10n.t("Ignore Whitespace"))
        .accessibilityValue(session.ignoreWhitespace ? L10n.t("On") : L10n.t("Off"))
        .accessibilityAddTraits(session.ignoreWhitespace ? .isSelected : [])
        .disabled(session.isBinaryDumpActive)
        if isShowingDirectoryList {
            Button {
                session.swapSides()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help(L10n.t("Swap Sides"))
            .accessibilityLabel(L10n.t("Swap Sides"))
        }
        if isShowingFileDiffChrome {
            Button {
                session.copyUnifiedDiff()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(session.rows.isEmpty)
            .help(L10n.t("Copy Unified Diff"))
            .accessibilityLabel(L10n.t("Copy Unified Diff"))
            Button {
                session.exportDiffsplitterXDocument()
            } label: {
                Image(systemName: Self.diffsplitterXExportSymbolName)
            }
            .disabled(!session.canExportDiffsplitterX || session.isTransferringDocument)
            .help(L10n.t("Export DiffsplitterX Document…"))
            .accessibilityLabel(L10n.t("Export DiffsplitterX Document…"))
        }
    }
    private static var diffsplitterXExportSymbolName: String {
        if #available(macOS 13.0, *) {
            return "doc.badge.arrow.up"
        }
        return "arrow.up.doc"
    }
    private var directoryBackButton: some View {
        Button {
            if session.selectedRelativePath != nil {
                session.leaveDirectoryDetail()
            } else {
                session.leaveDirectoryBrowseLevel()
            }
        } label: {
            Label(L10n.t("Back"), systemImage: "chevron.left")
        }
        .help(L10n.t("Back"))
    }
    private var directoryListRoot: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(L10n.t("Search paths"), text: $session.directoryFilter)
                    .textFieldStyle(.roundedBorder)
                Text(L10n.f("%d changed", directoryBrowserItemCount))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(10)
            if !session.directoryBrowsePrefix.isEmpty {
                Text(session.directoryBrowsePrefix)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .help(session.directoryBrowsePrefix)
            }
            Divider()
            List(directoryBrowserItems) { item in
                Button {
                    session.activateDirectoryBrowserItem(item)
                } label: {
                    directoryBrowserRow(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .modifier(DirectoryListStyleModifier())
        }
        .navigationTitle(directoryListNavigationTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var directoryListNavigationTitle: String {
        if session.directoryBrowsePrefix.isEmpty {
            return L10n.t("Changed Paths")
        }
        return (session.directoryBrowsePrefix as NSString).lastPathComponent
    }
    private var directoryBrowserItems: [DiffsplitterSession.DirectoryBrowserItem] {
        session.directoryBrowserItems(
            statusFilters: session.directoryStatusFilters,
            query: session.directoryFilter,
            statusPriority: statusPriority
        )
    }
    private var directoryBrowserItemCount: Int {
        if session.directoryFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return directoryBrowserItems.reduce(0) { partial, item in
                partial + (item.kind == .folder ? item.childCount : 1)
            }
        }
        return directoryBrowserItems.count
    }
    private func directoryBrowserRow(_ item: DiffsplitterSession.DirectoryBrowserItem) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(for: item.status))
                .frame(width: 8, height: 8)
            Image(systemName: item.kind == .folder ? "folder.fill" : "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(item.displayName)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if item.kind == .folder {
                Text(L10n.f("%d changed", item.childCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(title(for: item.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if item.kind == .folder {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(
            item.kind == .folder
                ? L10n.f("%d changed", item.childCount)
                : title(for: item.status)
        )
    }
    private func directoryMemberDetail(path: String) -> some View {
        VStack(spacing: 0) {
            if session.memberLoadProgress != nil || (session.isComparing && session.indexProgress == nil) {
                indexingProgressChrome
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }
            evenColumns
        }
        .navigationTitle((path as NSString).lastPathComponent)
        .onAppear {
            session.loadSelectedDirectoryFile()
        }
    }
    private func ensureSelectedPathVisibleInFilters() {
        guard let path = session.selectedRelativePath,
              let entry = session.directoryEntries.first(where: { $0.relativePath == path })
        else { return }
        if session.directoryStatusFilters.isEmpty
            || session.directoryStatusFilters.contains(entry.status) {
            return
        }
        session.leaveDirectoryDetail()
    }
    private var directoryStatusFilterCircles: some View {
        HStack(spacing: 6) {
            ForEach(statusPriority, id: \.self) { status in
                let count = session.directoryEntries.filter { $0.status == status }.count
                let isActive = session.directoryStatusFilters.isEmpty || session.directoryStatusFilters.contains(status)
                Button {
                    toggleDirectoryStatusFilter(status)
                } label: {
                    ZStack {
                        Circle()
                            .fill(color(for: status).opacity(count == 0 ? 0.25 : (isActive ? 1 : 0.35)))
                            .frame(width: 12, height: 12)
                        if session.directoryStatusFilters.contains(status) {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(count == 0)
                .help(directoryStatusFilterHelp(status, count: count))
                .accessibilityLabel(title(for: status))
                .accessibilityValue(session.directoryStatusFilters.contains(status) ? L10n.t("On") : L10n.t("Off"))
                .accessibilityAddTraits(session.directoryStatusFilters.contains(status) ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
    }
    private func toggleDirectoryStatusFilter(_ status: DiffsplitterEngine.DirEntryStatus) {
        if session.directoryStatusFilters.contains(status) {
            session.directoryStatusFilters.remove(status)
        } else {
            session.directoryStatusFilters.insert(status)
        }
        ensureSelectedPathVisibleInFilters()
    }
    private func directoryStatusFilterHelp(
        _ status: DiffsplitterEngine.DirEntryStatus,
        count: Int
    ) -> String {
        L10n.f("%@ — %d", title(for: status), count)
    }
    private func title(for status: DiffsplitterEngine.DirEntryStatus) -> String {
        switch status {
        case .added: return L10n.t("Added")
        case .removed: return L10n.t("Removed")
        case .modified: return L10n.t("Modified")
        case .binary: return L10n.t("Binary")
        case .identical: return L10n.t("Identical")
        }
    }
    private var evenColumns: some View {
        VStack(spacing: 0) {
            comparisonStrip
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if let dump = session.binaryDump {
                binaryDumpChrome(dump)
                Divider()
                binaryDumpRows(dump)
            } else {
                textDiffRows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func binaryDumpChrome(_ dump: DiffsplitterBinaryDump.Session) -> some View {
        HStack(spacing: 12) {
            Text(L10n.t("Hex dump"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                L10n.f(
                    "Window %@–%@ of %@ (%d lines in memory)",
                    DiffsplitterBinaryDump.byteCountString(dump.windowByteRange.lowerBound),
                    DiffsplitterBinaryDump.byteCountString(max(0, dump.windowByteRange.upperBound - 1)),
                    DiffsplitterBinaryDump.byteCountString(max(dump.leftByteCount, dump.rightByteCount)),
                    dump.rows.count
                )
            )
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 8)
            TextField(L10n.t("Offset"), text: $session.binaryDumpOffsetField)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .font(.caption.monospaced())
                .onSubmit { session.binaryDumpJumpToOffsetField() }
                .disabled(dump.isEmbeddedSnapshot)
            Button(L10n.t("Go")) {
                session.binaryDumpJumpToOffsetField()
            }
            .disabled(session.isComparing || dump.isEmbeddedSnapshot)
            Button {
                session.binaryDumpPageUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help(L10n.t("Previous window"))
            .disabled(session.isComparing || dump.isEmbeddedSnapshot || dump.windowStartLine <= 0)
            Button {
                session.binaryDumpPageDown()
            } label: {
                Image(systemName: "chevron.down")
            }
            .help(L10n.t("Next window"))
            .disabled(
                session.isComparing
                    || dump.isEmbeddedSnapshot
                    || dump.windowEndLine >= dump.totalLines
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    private func binaryDumpRows(_ dump: DiffsplitterBinaryDump.Session) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(dump.rows) { row in
                    HStack(alignment: .top, spacing: 0) {
                        binaryDumpCell(row.leftText, kind: row.kind, side: .left)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        columnHairline
                        binaryDumpCell(row.rightText, kind: row.kind, side: .right)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func binaryDumpCell(
        _ text: String?,
        kind: DiffsplitterBinaryDump.HexRow.Kind,
        side: DiffsplitterSession.Side
    ) -> some View {
        Text(text ?? "")
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(binaryDumpHighlight(kind: kind, side: side, hasText: text != nil))
            .textSelection(.enabled)
    }
    private func binaryDumpHighlight(
        kind: DiffsplitterBinaryDump.HexRow.Kind,
        side: DiffsplitterSession.Side,
        hasText: Bool
    ) -> Color {
        guard hasText else { return Color.clear }
        switch kind {
        case .equal:
            return Color.clear
        case .delete:
            return side == .left ? Color.red.opacity(0.18) : Color.clear
        case .insert:
            return side == .right ? Color.green.opacity(0.18) : Color.clear
        case .replace:
            return (side == .left ? Color.orange : Color.blue).opacity(0.16)
        }
    }
    private var textDiffRows: some View {
        Group {
            if session.rows.isEmpty {
                HStack(spacing: 0) {
                    emptyColumnMessage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    columnHairline
                    emptyColumnMessage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.rows.prefix(session.visibleRowCount))) { row in
                            HStack(alignment: .top, spacing: 0) {
                                rowView(row, side: .left)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                columnHairline
                                rowView(row, side: .right)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.12)
                            : .spring(response: 0.38, dampingFraction: 0.86),
                        value: session.visibleRowCount
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var comparisonStrip: some View {
        HStack(spacing: 0) {
            columnHeader(url: session.leftURL, side: .left)
            ZStack {
                columnHairline
                Button {
                    session.swapSides()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Swap Sides"))
                .accessibilityLabel(L10n.t("Swap Sides"))
            }
            .frame(width: 28)
            columnHeader(url: session.rightURL, side: .right)
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Comparison"))
    }
    private var columnHairline: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
    }
    private func columnHeader(url: URL?, side: DiffsplitterSession.Side) -> some View {
        let embeddedName = side == .left ? session.embeddedLeftName : session.embeddedRightName
        let title = url?.lastPathComponent
            ?? embeddedName
            ?? (side == .left ? L10n.t("Left") : L10n.t("Right"))
        let subtitle = columnSubtitle(for: url)
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: side == .left ? "doc.text" : "doc.text", accessibilityDescription: nil)
        return HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(side == .left ? L10n.t("Left") : L10n.t("Right"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .help(url?.path ?? title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            Spacer(minLength: 8)
            if session.selectedRelativePath == nil {
                Button {
                    session.presentOpenPanel(for: side)
                } label: {
                    Image(systemName: "folder")
                }
                .help(L10n.t("Replace…"))
                .accessibilityLabel(L10n.t("Replace…"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.f(
                "%@ — %@",
                side == .left ? L10n.t("Left") : L10n.t("Right"),
                title
            )
        )
    }
    private func columnSubtitle(for url: URL?) -> String? {
        if session.comparisonKind == .directories, let path = session.selectedRelativePath {
            return path
        }
        guard let url else { return nil }
        let parent = url.deletingLastPathComponent().path
        return parent == "/" ? nil : parent
    }
    @ViewBuilder
    private var emptyColumnMessage: some View {
        if session.aeaKeyPrompt != nil {
            Text(L10n.t("Enter a decryption key to expand this Apple Encrypted Archive."))
                .foregroundStyle(.secondary)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Group {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView {
                        Label {
                            EmptyView()
                        } icon: {
                            Image(systemName: "doc.slash")
                        }
                    }
                } else {
                    Image(systemName: "doc.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(L10n.t("No differences."))
        }
    }
    private func rowView(_ row: DiffsplitterEngine.AlignedRow, side: DiffsplitterSession.Side) -> some View {
        let text: String? = side == .left ? row.leftText : row.rightText
        let lineNumber: Int? = side == .left ? row.leftLineNumber : row.rightLineNumber
        let highlight = highlightColor(for: row.kind, side: side, hasText: text != nil)
        return HStack(alignment: .top, spacing: 8) {
            Text(lineNumber.map(String.init) ?? " ")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(text ?? " ")
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(highlight)
    }
    private func highlightColor(
        for kind: DiffsplitterEngine.RowKind,
        side: DiffsplitterSession.Side,
        hasText: Bool
    ) -> Color {
        guard hasText else { return Color.clear }
        switch kind {
        case .equal:
            return Color.clear
        case .delete:
            return side == .left ? Color.red.opacity(0.18) : Color.clear
        case .insert:
            return side == .right ? Color.green.opacity(0.18) : Color.clear
        case .replace:
            return (side == .left ? Color.orange : Color.blue).opacity(0.16)
        }
    }
    private func color(for status: DiffsplitterEngine.DirEntryStatus) -> Color {
        switch status {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        case .binary: return .purple
        case .identical: return .secondary
        }
    }
}

private struct DiffsplitterEmptyBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cycleDuration = 8.5

    var body: some View {
        ZStack {
            Color.black

            if reduceMotion {
                orbs(primaryProgress: 0.58, secondaryProgress: 0.42)
            } else {
                TimelineView(.animation) { timeline in
                    let cycle = timeline.date.timeIntervalSinceReferenceDate / cycleDuration
                    let primary = cycle.truncatingRemainder(dividingBy: 1)
                    let secondary = (cycle + 0.5).truncatingRemainder(dividingBy: 1)
                    orbs(primaryProgress: primary, secondaryProgress: secondary)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func orbs(primaryProgress: Double, secondaryProgress: Double) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let baseSize = max(width, height) * 1.05

            orb(
                color: Color(red: 1.0, green: 0.12, blue: 0.22),
                progress: primaryProgress,
                size: baseSize,
                x: width * 0.26,
                height: height
            )
            orb(
                color: Color(red: 0.08, green: 0.92, blue: 0.38),
                progress: secondaryProgress,
                size: baseSize,
                x: width * 0.74,
                height: height
            )
        }
        .drawingGroup(opaque: false)
    }

    private func orb(
        color: Color,
        progress: Double,
        size: CGFloat,
        x: CGFloat,
        height: CGFloat
    ) -> some View {
        let travel = smoothstep(progress)
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.9),
                        color.opacity(0.4),
                        color.opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .scaleEffect(0.22 + travel * 1.05)
            .opacity(orbOpacity(progress))
            .position(
                x: x,
                y: height * (1.2 - travel * 0.7)
            )
    }

    private func orbOpacity(_ progress: Double) -> Double {
        let wave = sin(progress * .pi)
        return pow(wave, 2.2) * 0.88
    }

    private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

private struct DirectoryListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.listStyle(.inset(alternatesRowBackgrounds: true))
        } else {
            content
        }
    }
}

private struct DiffsplitterDirectoryBackToolbarModifier: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: action) {
                        Label(L10n.t("Back"), systemImage: "chevron.left")
                    }
                    .help(L10n.t("Back"))
                }
            }
        } else {
            content
        }
    }
}

private struct DiffsplitterWindowCoordinator: NSViewRepresentable {
    let hasUnsavedChanges: Bool
    let documentURL: URL?
    let commandActions: DiffsplitterCommandActions
    let saveDraft: (@escaping (Bool) -> Void) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView()
        view.didMoveToWindowHandler = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.hasUnsavedChanges = hasUnsavedChanges
        coordinator.commandActions = commandActions
        coordinator.saveDraft = saveDraft
        coordinator.updateDocumentPresentation(url: documentURL, isEdited: hasUnsavedChanges)
        coordinator.attach(to: nsView.window)
        if let window = nsView.window {
            DiffsplitterCommandRouter.shared.register(commandActions, for: window)
        }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? WindowAttachmentView)?.didMoveToWindowHandler = nil
        coordinator.removeQuitEventMonitor()
    }

    private final class WindowAttachmentView: NSView {
        var didMoveToWindowHandler: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            didMoveToWindowHandler?(window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        var previousDelegate: NSWindowDelegate?
        var hasUnsavedChanges = false
        var documentURL: URL?
        var commandActions = DiffsplitterCommandActions(
            canSave: false,
            canExportDiffsplitterX: false,
            save: {},
            saveAs: {},
            exportDiffsplitterX: {}
        )
        var saveDraft: ((@escaping (Bool) -> Void) -> Void)?
        private var closeApproved = false
        private var isPrompting = false
        private var quitEventMonitor: Any?
        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            previousDelegate = window.delegate
            window.delegate = self
            installQuitEventMonitor()
            DiffsplitterCommandRouter.shared.register(commandActions, for: window)
            updateDocumentPresentation(url: documentURL, isEdited: hasUnsavedChanges)
        }
        func updateDocumentPresentation(url: URL?, isEdited: Bool) {
            documentURL = url
            guard let window else { return }
            window.representedURL = url
            window.title = url.map {
                L10n.f("%@ — Diffsplitter", $0.lastPathComponent)
            } ?? L10n.t("Untitled — Diffsplitter")
            window.isDocumentEdited = isEdited
        }
        private func installQuitEventMonitor() {
            guard quitEventMonitor == nil else { return }
            quitEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      self.hasUnsavedChanges,
                      self.window?.isKeyWindow == true,
                      event.charactersIgnoringModifiers?.lowercased() == "q",
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                else { return event }
                self.promptToSave(in: self.window) {
                    NSApp.terminate(nil)
                }
                return nil
            }
        }
        fileprivate func removeQuitEventMonitor() {
            guard let quitEventMonitor else { return }
            NSEvent.removeMonitor(quitEventMonitor)
            self.quitEventMonitor = nil
        }
        private func promptToSave(in window: NSWindow?, onDiscardOrSave: @escaping () -> Void) {
            guard let window, !isPrompting else { return }
            isPrompting = true
            let alert = NSAlert()
            alert.messageText = L10n.t("Save changes to this Diffsplitter document?")
            alert.informativeText = L10n.t("Your session pair will be lost if you don’t save it.")
            alert.addButton(withTitle: L10n.t("Save"))
            alert.addButton(withTitle: L10n.t("Don’t Save"))
            alert.addButton(withTitle: L10n.t("Cancel"))
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                self.isPrompting = false
                switch response {
                case .alertFirstButtonReturn:
                    self.saveDraft? { saved in
                        if saved { onDiscardOrSave() }
                    }
                case .alertSecondButtonReturn:
                    onDiscardOrSave()
                default:
                    break
                }
            }
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if closeApproved { return true }
            guard hasUnsavedChanges else {
                closeApproved = true
                return true
            }
            promptToSave(in: sender) { [weak self, weak sender] in
                guard let self, let sender else { return }
                self.closeApproved = true
                sender.close()
            }
            return false
        }
        func windowWillClose(_ notification: Notification) {
            if let window { DiffsplitterCommandRouter.shared.unregister(window) }
            removeQuitEventMonitor()
            closeApproved = false
            previousDelegate?.windowWillClose?(notification)
        }
        func windowDidBecomeKey(_ notification: Notification) {
            if let window { DiffsplitterCommandRouter.shared.activate(window) }
            previousDelegate?.windowDidBecomeKey?(notification)
        }
        func windowDidResignKey(_ notification: Notification) {
            previousDelegate?.windowDidResignKey?(notification)
        }
    }
}


struct DiffsplitterEducationView: View {
    let onDismiss: () -> Void
    @StateObject private var vars = PersistentVariables()
    @State private var step = 0

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 24) {
            Group {
                switch step {
                case 0:
                    introStep
                case 1:
                    offloadStep
                case 2:
                    completionSoundStep
                default:
                    statusDotsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            pageIndicators

            HStack(spacing: 12) {
                if step > 0 {
                    Button(L10n.t("Back")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                DiffsplitterEducationContinueButton {
                    if step < stepCount - 1 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step += 1
                        }
                    } else {
                        onDismiss()
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .padding(.top, 40)
        .frame(width: 520, height: 520)
    }

    private var introStep: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(L10n.t("Diffsplitter"))
                .font(.title2)
                .fontWeight(.medium)
            Text(L10n.t("Diffsplitter compares two text files, or two folders or archives side by side. Select a nested archive in the path list to expand it. Save a session to reopen the same pair later."))
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .multilineTextAlignment(.center)
        }
    }

    private var offloadStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(L10n.t("Offload Large Dumps to Temporary Storage"))
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                Text(L10n.t("Choose where Diffsplitter stores large dumps while you inspect them. Storing on disk demands less horsepower, while memory (RAM) can be faster on powerful machines."))
                    .padding(.top, 12)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Picker(selection: $vars.diffsplitterPreferDiskTempForLargeFiles) {
                Text(L10n.t("Session Disk Space")).tag(true)
                Text(L10n.t("Memory (RAM)")).tag(false)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private var completionSoundStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(L10n.t("Play a sound when Diffsplitter finishes a comparison"))
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                Text(L10n.t("Notify with a sound and banner when a Diffsplitter comparison takes at least the selected duration."))
                    .padding(.top, 12)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Toggle(isOn: $vars.playDiffsplitterDoneSound) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            if vars.playDiffsplitterDoneSound {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("Minimum Duration"))
                        Spacer()
                        Text(
                            DiffsplitterCompletionFeedback.durationLabel(
                                for: vars.diffsplitterNotifyMinimumSeconds
                            )
                        )
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: {
                                DiffsplitterCompletionFeedback.sliderIndex(
                                    forSeconds: vars.diffsplitterNotifyMinimumSeconds
                                )
                            },
                            set: {
                                vars.diffsplitterNotifyMinimumSeconds =
                                    DiffsplitterCompletionFeedback.seconds(forSliderIndex: $0)
                            }
                        ),
                        in: DiffsplitterCompletionFeedback.sliderIndexRange,
                        step: 1
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private var statusDotsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            educationStepHeader(
                title: L10n.t("Folder Status Dot Priority"),
                detail: L10n.t("Drag to reorder. Items nearer the top win when a folder contains mixed changes.")
            )
            List {
                ForEach(Array(vars.diffsplitterStatusPriority.enumerated()), id: \.element) { index, raw in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Circle()
                            .fill(statusColor(raw))
                            .frame(width: 10, height: 10)
                        Text(statusTitle(raw))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(statusTitle(raw))
                    .accessibilityValue(L10n.f("Priority %d", index + 1))
                }
                .onMove(perform: moveStatusPriority)
            }
            .frame(height: CGFloat(vars.diffsplitterStatusPriority.count) * 28)
            .listStyle(.bordered)
            .modifier(DiffsplitterEducationPriorityListScrollModifier())

            Button(L10n.t("Reset to Default")) {
                vars.diffsplitterStatusPriority = PersistentVariables.defaultDiffsplitterStatusPriority
            }
            .disabled(vars.diffsplitterStatusPriority == PersistentVariables.defaultDiffsplitterStatusPriority)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: index == step ? 8 : 6, height: index == step ? 8 : 6)
                    .accessibilityLabel(L10n.f("Step %d of %d", index + 1, stepCount))
                    .accessibilityAddTraits(index == step ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.f("Step %d of %d", step + 1, stepCount))
    }

    private func educationStepHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.medium)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moveStatusPriority(from source: IndexSet, to destination: Int) {
        var order = vars.diffsplitterStatusPriority
        order.move(fromOffsets: source, toOffset: destination)
        vars.diffsplitterStatusPriority = order
    }

    private func statusTitle(_ raw: String) -> String {
        switch DiffsplitterEngine.DirEntryStatus(rawValue: raw) {
        case .added: return L10n.t("Added")
        case .removed: return L10n.t("Removed")
        case .modified: return L10n.t("Modified")
        case .binary: return L10n.t("Binary")
        case .identical, .none: return raw
        }
    }

    private func statusColor(_ raw: String) -> Color {
        switch DiffsplitterEngine.DirEntryStatus(rawValue: raw) {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        case .binary: return .purple
        case .identical, .none: return .secondary
        }
    }
}

private struct DiffsplitterEducationContinueButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(L10n.t("Continue"))
                .font(.headline)
                .padding(8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .diffsplitterEducationButtonStyle()
    }
}

private struct DiffsplitterEducationPriorityListScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollDisabled(true)
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func diffsplitterEducationButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.accentColor)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.large)
                .tint(.accentColor)
        }
    }
}
