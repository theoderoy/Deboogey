//
//  DiffsplitterView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 02/09/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
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

@MainActor
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

#endif


#if os(iOS)
private struct DiffsplitterExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.diffsplitterDocument, .diffsplitterXDocument, .plainText]
    }
    static var writableContentTypes: [UTType] {
        [.diffsplitterDocument, .diffsplitterXDocument, .plainText]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif

struct DiffsplitterView: View {
    let request: DiffsplitterWindowRequest
    @StateObject private var session = DiffsplitterSession()
    @State private var statusPriorityRaw = PersistentVariables.loadDiffsplitterStatusPriority()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardConfirmation = false
    @State private var exportDocument: DiffsplitterExportDocument?
    @State private var exportContentType: UTType = .diffsplitterDocument
    @State private var exportDefaultFilename = "Untitled"
    @State private var isExporting = false
    @State private var saveSucceededFlash = false
    @State private var saveSucceededResetTask: Task<Void, Never>?
#endif
    private var statusPriority: [DiffsplitterEngine.DirEntryStatus] {
        DiffsplitterEngine.statusPriority(fromRawValues: statusPriorityRaw)
    }
    private var needsInlineWindowChrome: Bool {
#if os(macOS)
        if #available(macOS 13.0, *) { return false }
        return true
#else
        return false
#endif
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
#if os(macOS)
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
#else
        .navigationTitle(L10n.t("Diffsplitter"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if showsDirectoryBackButton {
                        navigateDirectoryBack()
                    } else if session.hasUnsavedDocumentChanges {
                        showDiscardConfirmation = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Label(L10n.t("Back"), systemImage: "chevron.backward")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session.isReady {
                    documentToolbarControls
                    toolbarActionControls
                }
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { session.isPresentingSidePicker },
                set: {
                    session.isPresentingSidePicker = $0
                    if !$0 {
                        session.handleSidePickerDismissed()
                    }
                }
            ),
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                let url = urls.first
                if let url {
                    _ = url.startAccessingSecurityScopedResource()
                }
                session.handlePickedSideURL(url)
            case .failure(let error):
                session.setupError = error.localizedDescription
                session.handlePickedSideURL(nil)
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportDefaultFilename
        ) { result in
            session.consumePendingExportResult(result)
            exportDocument = nil
        }
        .onChange(of: session.pendingExport?.id) { _ in
            presentPendingExportIfNeeded()
        }
        .alert(
            L10n.t("Save changes to this Diffsplitter document?"),
            isPresented: $showDiscardConfirmation
        ) {
            Button(L10n.t("Save")) {
                session.saveDocument(forceSaveAs: false)
            }
            Button(L10n.t("Don't Save"), role: .destructive) {
                dismiss()
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("Your session pair will be lost if you don’t save it."))
        }
        .alert(L10n.t("Diffsplitter Document Error"), isPresented: Binding(
            get: { session.documentError != nil },
            set: { if !$0 { session.documentError = nil } }
        )) {
            Button(L10n.t("OK"), role: .cancel) {}
        } message: {
            Text(session.documentError ?? "")
        }
        .alert(L10n.t("Diffsplitter Error"), isPresented: Binding(
            get: { session.setupError != nil },
            set: { if !$0 { session.setupError = nil } }
        )) {
            Button(L10n.t("OK"), role: .cancel) {}
        } message: {
            Text(session.setupError ?? "")
        }
        .alert(
            L10n.t("Inspect Binary Dump?"),
            isPresented: Binding(
                get: { session.pendingBinaryDumpPrompt != nil },
                set: {
                    if !$0, let prompt = session.pendingBinaryDumpPrompt {
                        session.handleBinaryDumpPromptResult(.cancel, path: prompt.path, entry: prompt.entry)
                    }
                }
            ),
            presenting: session.pendingBinaryDumpPrompt
        ) { prompt in
            Button(L10n.t("Inspect Dump")) {
                session.handleBinaryDumpPromptResult(.inspectDump, path: prompt.path, entry: prompt.entry)
            }
            Button(L10n.t("Metadata Only")) {
                session.handleBinaryDumpPromptResult(.metadataOnly, path: prompt.path, entry: prompt.entry)
            }
            Button(L10n.t("Cancel"), role: .cancel) {
                session.handleBinaryDumpPromptResult(.cancel, path: prompt.path, entry: prompt.entry)
            }
        } message: { prompt in
            Text(prompt.estimate.promptDetail)
        }
        .sheet(item: Binding(
            get: { session.aeaKeyPrompt },
            set: {
                if $0 == nil, let prompt = session.aeaKeyPrompt {
                    session.handleAEAKeyPromptResult(.metadataOnly, prompt: prompt)
                }
            }
        )) { prompt in
            NavigationStack {
                Form {
                    Text(L10n.t(
                        "Enter the base64 or hex key for this Apple Encrypted Archive. Leave blank to compare metadata only."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    TextField(L10n.t("base64:… or hex:…"), text: $session.aeaKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle(L10n.t("AEA Decryption Key"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.t("Compare Metadata")) {
                            session.handleAEAKeyPromptResult(.metadataOnly, prompt: prompt)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t("Decrypt")) {
                            session.handleAEAKeyPromptResult(
                                .decrypt(session.aeaKeyDraft),
                                prompt: prompt
                            )
                        }
                    }
                }
                .onAppear {
                    session.aeaKeyDraft = session.aeaSessionKeys[prompt.path] ?? session.aeaKeyDraft
                }
            }
        }
#endif
        .onChange(of: session.ignoreWhitespace) { _ in
            session.applyIgnoreWhitespaceChange()
        }
        .onAppear {
            session.reduceMotion = reduceMotion
            session.handleDocumentRequest(request)
#if os(iOS)
            presentPendingExportIfNeeded()
#endif
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
#if os(macOS)
                            .controlSize(.large)
#endif
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
#if os(iOS)
    private func presentPendingExportIfNeeded() {
        guard let pending = session.pendingExport, !isExporting else { return }
        switch pending {
        case .saveDocument(let suggestedName):
            do {
                beginExport(
                    DiffsplitterExportDocument(data: try session.currentDocument.encoded()),
                    type: .diffsplitterDocument,
                    filename: suggestedName
                )
            } catch {
                session.documentError = error.localizedDescription
                session.consumePendingExportResult(.failure(error))
            }
        case .exportDiffsplitterX(let suggestedName, let data):
            beginExport(
                DiffsplitterExportDocument(data: data),
                type: .diffsplitterXDocument,
                filename: suggestedName
            )
        case .exportText(let suggestedName, let text):
            beginExport(
                DiffsplitterExportDocument(data: Data(text.utf8)),
                type: .plainText,
                filename: suggestedName
            )
        }
    }

    private func beginExport(
        _ document: DiffsplitterExportDocument,
        type: UTType,
        filename: String
    ) {
        let sanitized = DeboogeyAppDocuments.sanitizedFilename(filename)
        let base = (sanitized as NSString).deletingPathExtension
        exportDocument = document
        exportContentType = type
        exportDefaultFilename = base.isEmpty ? "Untitled" : base
        isExporting = true
    }
#endif
    private var setupView: some View {
        ZStack {
            DiffsplitterEmptyBackground()

            VStack(spacing: 28) {
                HStack(spacing: 14) {
                    Image("DiffsplitterIdent")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .environment(\.colorScheme, .dark)
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
        let tint = side == .left ? DiffsplitterPalette.leftAccent : DiffsplitterPalette.rightAccent
        let well = content()
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .overlay {
                shape
                    .strokeBorder(
                        isTargeted ? tint : tint.opacity(0.45),
                        style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: [9, 7])
                    )
            }
            .scaleEffect(isTargeted ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: isTargeted)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: binding(for: side)) { providers in
                session.handleDrop(providers, onto: side)
            }

#if os(macOS)
        if #available(macOS 26.0, *) {
            well
                .glassEffect(
                    .clear.tint(tint.opacity(isTargeted ? 0.28 : 0.16)).interactive(),
                    in: shape
                )
        } else {
            well
                .background(tint.opacity(isTargeted ? 0.18 : 0.10), in: shape)
        }
#else
        well
            .background(tint.opacity(isTargeted ? 0.18 : 0.10), in: shape)
#endif
    }

    @ViewBuilder
    private func dropWellContent(url: URL?, side: DiffsplitterSession.Side) -> some View {
        VStack(spacing: 12) {
            if let url {
                Image(systemName: session.isDirectoryLike(url) ? "folder" : "doc.text")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(.white.opacity(0.7))
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
                Image(importHintImageName(for: side))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text(L10n.t("Drop a file, folder, or archive here"))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            Button(L10n.t("Import…")) {
                session.presentOpenPanel(for: side)
            }
#if os(macOS)
            .controlSize(.large)
#endif
            .colorScheme(.dark)
        }
    }

    private func importHintImageName(for side: DiffsplitterSession.Side) -> String {
        let suffix = side == .left ? "Left" : "Right"
        switch ProcessInfo.processInfo.operatingSystemVersion.majorVersion {
        case 26:
            return "ImportDAssetHint26\(suffix)"
        case 27:
            return "ImportDAssetHint27\(suffix)"
        default:
            return "ImportDAssetHintRaw\(suffix)"
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
        .background(DiffsplitterPalette.windowBackground)
    }
    @ViewBuilder
    private var documentToolbarControls: some View {
#if os(iOS)
        Button {
            guard session.saveDocument(forceSaveAs: false) else { return }
            flashSaveSucceeded()
        } label: {
            Label(
                L10n.t("Save Diffsplitter Document"),
                systemImage: saveSucceededFlash ? "checkmark.circle.fill" : "square.and.arrow.down"
            )
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(saveSucceededFlash ? Color.green : Color.primary)
        .disabled(!session.hasBothSides || session.isTransferringDocument)
        .help(L10n.t("Save Diffsplitter Document"))
        .accessibilityLabel(
            saveSucceededFlash
                ? L10n.t("Diffsplitter Document Saved")
                : L10n.t("Save Diffsplitter Document")
        )
        Button {
            session.saveDocument(forceSaveAs: true)
        } label: {
            Label(L10n.t("Save Diffsplitter Document As…"), systemImage: "square.and.arrow.down.on.square")
        }
        .labelStyle(.iconOnly)
        .disabled(!session.hasBothSides || session.isTransferringDocument)
        .help(L10n.t("Save Diffsplitter Document As…"))
        .accessibilityLabel(L10n.t("Save Diffsplitter Document As…"))
        if isShowingFileDiffChrome {
            Button {
                session.exportDiffsplitterXDocument()
            } label: {
                Label(L10n.t("Export DiffsplitterX Document…"), systemImage: Self.diffsplitterXExportSymbolName)
            }
            .labelStyle(.iconOnly)
            .disabled(!session.canExportDiffsplitterX || session.isTransferringDocument)
            .help(L10n.t("Export DiffsplitterX Document…"))
            .accessibilityLabel(L10n.t("Export DiffsplitterX Document…"))
        }
#endif
    }
#if os(iOS)
    private func flashSaveSucceeded() {
        saveSucceededResetTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            saveSucceededFlash = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        saveSucceededResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                saveSucceededFlash = false
            }
        }
    }
#endif
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
#if os(macOS)
            Button {
                session.exportDiffsplitterXDocument()
            } label: {
                Image(systemName: Self.diffsplitterXExportSymbolName)
            }
            .disabled(!session.canExportDiffsplitterX || session.isTransferringDocument)
            .help(L10n.t("Export DiffsplitterX Document…"))
            .accessibilityLabel(L10n.t("Export DiffsplitterX Document…"))
#endif
        }
    }
    private static var diffsplitterXExportSymbolName: String {
#if os(macOS)
        if #available(macOS 13.0, *) {
            return "doc.badge.arrow.up"
        }
        return "arrow.up.doc"
#else
        return "doc.badge.arrow.up"
#endif
    }
    private func navigateDirectoryBack() {
        if session.selectedRelativePath != nil {
            session.leaveDirectoryDetail()
        } else {
            session.leaveDirectoryBrowseLevel()
        }
    }
    private var directoryBackButton: some View {
        Button(action: navigateDirectoryBack) {
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
                .fill(item.status.color)
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
                Text(item.status.title)
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
                : item.status.title
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
                            .fill(status.color.opacity(count == 0 ? 0.25 : (isActive ? 1 : 0.35)))
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
                .accessibilityLabel(status.title)
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
        L10n.f("%@ — %d", status.title, count)
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
                .disabled(!dump.canNavigateWindows)
            Button(L10n.t("Go")) {
                session.binaryDumpJumpToOffsetField()
            }
            .disabled(session.isComparing || !dump.canNavigateWindows)
            Button {
                session.binaryDumpPageUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help(L10n.t("Previous window"))
            .disabled(session.isComparing || !dump.canNavigateWindows || dump.windowStartLine <= 0)
            Button {
                session.binaryDumpPageDown()
            } label: {
                Image(systemName: "chevron.down")
            }
            .help(L10n.t("Next window"))
            .disabled(
                session.isComparing
                    || !dump.canNavigateWindows
                    || dump.windowEndLine >= dump.totalLines
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DiffsplitterPalette.controlBackground)
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
    private enum DiffHighlightKind {
        case equal, delete, insert, replace

        init(rowKind: DiffsplitterEngine.RowKind) {
            switch rowKind {
            case .equal: self = .equal
            case .delete: self = .delete
            case .insert: self = .insert
            case .replace: self = .replace
            }
        }

        init(hexKind: DiffsplitterBinaryDump.HexRow.Kind) {
            switch hexKind {
            case .equal: self = .equal
            case .delete: self = .delete
            case .insert: self = .insert
            case .replace: self = .replace
            }
        }
    }
    private func highlightColor(
        kind: DiffHighlightKind,
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
    private func binaryDumpHighlight(
        kind: DiffsplitterBinaryDump.HexRow.Kind,
        side: DiffsplitterSession.Side,
        hasText: Bool
    ) -> Color {
        highlightColor(kind: DiffHighlightKind(hexKind: kind), side: side, hasText: hasText)
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
                        ForEach(0..<session.visibleRowCount, id: \.self) { index in
                            let row = session.rows[index]
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
                        .background(DiffsplitterPalette.windowBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DiffsplitterPalette.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Swap Sides"))
                .accessibilityLabel(L10n.t("Swap Sides"))
            }
            .frame(width: 28)
            columnHeader(url: session.rightURL, side: .right)
        }
        .padding(.vertical, 6)
        .background(DiffsplitterPalette.controlBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Comparison"))
    }
    private var columnHairline: some View {
        Rectangle()
            .fill(DiffsplitterPalette.separator)
            .frame(width: 1)
    }
    private func columnHeader(url: URL?, side: DiffsplitterSession.Side) -> some View {
        let embeddedName = side == .left ? session.embeddedLeftName : session.embeddedRightName
        let title = url?.lastPathComponent
            ?? embeddedName
            ?? (side == .left ? L10n.t("Left") : L10n.t("Right"))
        let subtitle = columnSubtitle(for: url)
        return HStack(spacing: 10) {
#if os(macOS)
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
#else
            Image(systemName: url.map { session.isDirectoryLike($0) ? "folder" : "doc.text" } ?? "doc.text")
                .font(.title2)
                .frame(width: 28, height: 28)
#endif
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
#if os(macOS)
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
#else
                ContentUnavailableView {
                    Label {
                        EmptyView()
                    } icon: {
                        Image(systemName: "doc.slash")
                    }
                }
#endif
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
        highlightColor(kind: DiffHighlightKind(rowKind: kind), side: side, hasText: hasText)
    }
}

private struct DiffsplitterEmptyBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spawnInterval: TimeInterval = 0.16
    private let sweepDuration: TimeInterval = 0.55
    private var activeStripeSpan: Int { Int(ceil(sweepDuration / spawnInterval)) }

    var body: some View {
        ZStack {
            Color.black

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.55),
                    .init(color: DiffsplitterPalette.brandGreen.opacity(0.22), location: 0.82),
                    .init(color: DiffsplitterPalette.brandGreen.opacity(0.38), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if reduceMotion {
                Canvas { context, size in
                    drawStripe(
                        in: &context,
                        size: size,
                        color: DiffsplitterPalette.leftAccent,
                        progress: 0.4,
                        yFactor: 0.34,
                        goesRight: true,
                        peakOpacity: 0.10
                    )
                    drawStripe(
                        in: &context,
                        size: size,
                        color: DiffsplitterPalette.rightAccent,
                        progress: 0.62,
                        yFactor: 0.66,
                        goesRight: false,
                        peakOpacity: 0.10
                    )
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        drawActiveStripes(in: &context, size: size, at: t)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawActiveStripes(in context: inout GraphicsContext, size: CGSize, at time: TimeInterval) {
        let newest = Int(floor(time / spawnInterval))
        let oldest = newest - activeStripeSpan
        guard newest >= oldest else { return }

        for index in oldest...newest {
            let progress = (time - Double(index) * spawnInterval) / sweepDuration
            guard (0...1).contains(progress) else { continue }
            let traits = stripeTraits(for: index)
            drawStripe(
                in: &context,
                size: size,
                color: index & 1 == 0 ? DiffsplitterPalette.leftAccent : DiffsplitterPalette.rightAccent,
                progress: progress,
                yFactor: traits.yFactor,
                goesRight: traits.goesRight,
                peakOpacity: 0.15
            )
        }
    }

    private func stripeTraits(for index: Int) -> (yFactor: CGFloat, goesRight: Bool) {
        var hash = UInt64(bitPattern: Int64(index &+ 0x9E37))
        hash &*= 0x9E3779B97F4A7C15
        hash ^= hash &>> 32
        let unit = Double(hash % 10_000) / 10_000.0
        return (CGFloat(0.12 + unit * 0.76), (hash & 1) == 0)
    }

    private func drawStripe(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color,
        progress: Double,
        yFactor: CGFloat,
        goesRight: Bool,
        peakOpacity: Double
    ) {
        let stripeHeight = max(size.height * 0.1, 28)
        let stripeWidth = max(size.width * 0.36, 110)
        let travel = size.width + stripeWidth
        let eased = CGFloat(easeInOut(progress))
        let x = goesRight
            ? (-stripeWidth * 0.5 + eased * travel)
            : (size.width - stripeWidth * 0.5 - eased * travel)
        let y = size.height * yFactor - stripeHeight * 0.5
        let envelope = sin(progress * .pi)
        let opacity = peakOpacity * envelope * envelope
        let band = Path(CGRect(x: x, y: y, width: stripeWidth, height: stripeHeight))

        context.fill(
            band,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: color.opacity(opacity * 0.55), location: 0.22),
                    .init(color: color.opacity(opacity), location: 0.5),
                    .init(color: color.opacity(opacity * 0.55), location: 0.78),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: CGPoint(x: x, y: y + stripeHeight * 0.5),
                endPoint: CGPoint(x: x + stripeWidth, y: y + stripeHeight * 0.5)
            )
        )
    }

    private func easeInOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

private struct DirectoryListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        if #available(macOS 13.0, *) {
            content.listStyle(.inset(alternatesRowBackgrounds: true))
        } else {
            content
        }
#else
        content.listStyle(.insetGrouped)
#endif
    }
}

private struct DiffsplitterDirectoryBackToolbarModifier: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
#if os(macOS)
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
#else
        content
#endif
    }
}

private enum DiffsplitterPalette {
    static let leftAccent = Color(red: 1.0, green: 0.18, blue: 0.26)
    static let rightAccent = Color(red: 0.10, green: 0.88, blue: 0.42)
    static let brandGreen = Color(red: 0.0, green: 0.435, blue: 0.243)

    static var windowBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.systemBackground)
#endif
    }
    static var controlBackground: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(.secondarySystemBackground)
#endif
    }
    static var separator: Color {
#if os(macOS)
        Color(nsColor: .separatorColor)
#else
        Color(.separator)
#endif
    }
}

#if os(macOS)
private struct DiffsplitterWindowCoordinator: NSViewRepresentable {
    let hasUnsavedChanges: Bool
    let documentURL: URL?
    let commandActions: DiffsplitterCommandActions
    let saveDraft: (@escaping (Bool) -> Void) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = DocumentWindowAttachmentView()
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
        (nsView as? DocumentWindowAttachmentView)?.didMoveToWindowHandler = nil
        coordinator.removeQuitEventMonitor()
    }

    @MainActor
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
            quitEventMonitor = DocumentUnsavedChangesPrompt.installQuitMonitor(
                hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges == true },
                isKeyWindow: { [weak self] in self?.window?.isKeyWindow == true },
                prompt: { [weak self] onDiscardOrSave in
                    self?.promptToSave(in: self?.window, onDiscardOrSave: onDiscardOrSave)
                }
            )
        }
        fileprivate func removeQuitEventMonitor() {
            guard let quitEventMonitor else { return }
            NSEvent.removeMonitor(quitEventMonitor)
            self.quitEventMonitor = nil
        }
        private func promptToSave(in window: NSWindow?, onDiscardOrSave: @escaping () -> Void) {
            guard !isPrompting else { return }
            DocumentUnsavedChangesPrompt.present(
                in: window,
                messageText: L10n.t("Save changes to this Diffsplitter document?"),
                informativeText: L10n.t("Your session pair will be lost if you don’t save it."),
                setPrompting: { [weak self] value in self?.isPrompting = value },
                saveDraft: saveDraft,
                onDiscardOrSave: onDiscardOrSave
            )
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
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || previousDelegate?.responds(to: aSelector) == true
        }
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            previousDelegate?.responds(to: aSelector) == true ? previousDelegate : super.forwardingTarget(for: aSelector)
        }
    }
}

#endif

struct DiffsplitterEducationView: View {
    let onDismiss: () -> Void
    @StateObject private var vars = PersistentVariables()
    @State private var step = 0

#if os(macOS)
    private let stepCount = 4
#else
    private let stepCount = 3
#endif

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
#if os(macOS)
                    statusDotsStep
#else
                    EmptyView()
#endif
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )

            pageIndicators

            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step -= 1
                        }
                    } label: {
                        Text(L10n.t("Back"))
                            .deboogeyOnboardingButtonLabel()
                    }
                    .deboogeyButtonStyle(tint: .accentColor)
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
#if os(macOS)
        .frame(width: 520, height: 520)
#else
        .frame(maxWidth: 520, maxHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }

    private var introStep: some View {
        VStack(spacing: 8) {
            Image("DiffsplitterIdent")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)
                .padding(.bottom, 12)
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
#if os(iOS)
                Image(systemName: "platter.filled.top.and.arrow.up.iphone")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(L10n.t("Notify with Live Activity when Diffsplitter finishes"))
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("Live Activity when available, otherwise a banner. Plays a sound after the selected minimum duration."))
                    .padding(.top, 12)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
#else
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(L10n.t("Play a sound when Diffsplitter finishes a comparison"))
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("Notify with a sound and banner when a Diffsplitter comparison takes at least the selected duration."))
                    .padding(.top, 12)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
#endif
            }

            Toggle(isOn: $vars.playDiffsplitterDoneSound) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)

            if vars.playDiffsplitterDoneSound {
                DiffsplitterCompletionDurationControls(
                    minimumSeconds: $vars.diffsplitterNotifyMinimumSeconds,
                    notifyWhenBackgrounded: $vars.diffsplitterNotifyWhenBackgrounded,
                    stacksBackgroundControls: true,
                    footerUsesForegroundStyle: true
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

#if os(macOS)
    private var statusDotsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            educationStepHeader(
                title: L10n.t("Folder Status Dot Priority"),
                detail: L10n.t("Drag to reorder. Items nearer the top win when a folder contains mixed changes.")
            )
            DiffsplitterStatusPriorityEditor(order: $vars.diffsplitterStatusPriority)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
#endif

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


}

private struct DiffsplitterEducationContinueButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(L10n.t("Continue"))
                .deboogeyOnboardingButtonLabel()
        }
        .deboogeyProminentButtonStyle()
    }
}

