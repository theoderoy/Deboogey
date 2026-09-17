//
//  LoupeMachineView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 27/07/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
#if canImport(AppKit)
import AppKit
#endif

#if os(macOS)
struct LoupeMachineCommandActions {
    let canSave: Bool
    let save: () -> Void
    let saveAs: () -> Void
}

@MainActor
final class LoupeMachineCommandRouter: ObservableObject {
    static let shared = LoupeMachineCommandRouter()

    @Published private(set) var canSave = false
    private var actionsByWindow: [ObjectIdentifier: LoupeMachineCommandActions] = [:]

    func register(_ actions: LoupeMachineCommandActions, for window: NSWindow) {
        actionsByWindow[ObjectIdentifier(window)] = actions
        if NSApp.keyWindow === window {
            canSave = actions.canSave
            if canSave { DiffsplitterCommandRouter.shared.resignActiveSave() }
        }
    }

    func activate(_ window: NSWindow) {
        canSave = actionsByWindow[ObjectIdentifier(window)]?.canSave == true
        DiffsplitterCommandRouter.shared.resignActiveSave()
    }

    func resignActiveSave() {
        canSave = false
    }

    func unregister(_ window: NSWindow) {
        actionsByWindow.removeValue(forKey: ObjectIdentifier(window))
        if NSApp.keyWindow === window { canSave = false }
    }

    func save(saveAs: Bool) {
        guard let window = NSApp.keyWindow,
              let actions = actionsByWindow[ObjectIdentifier(window)],
              actions.canSave else { return }
        saveAs ? actions.saveAs() : actions.save()
    }
}
#endif

private final class LoupeFlagStore: ObservableObject {
    @Published private(set) var names: [String] = []
    private(set) var revision = 0
    private var values: [String: LoupeFlag] = [:]

    var isEmpty: Bool { names.isEmpty }
    var flags: [LoupeFlag] { names.compactMap { values[$0] } }

    func flag(named name: String?) -> LoupeFlag? {
        guard let name else { return nil }
        return values[name]
    }

    func replace(with flags: [LoupeFlag]) {
        removeTemporaryFiles(excluding: Set(flags.compactMap(\.valueFileURL)))
        values = Dictionary(flags.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        revision += 1
        names = values.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func append(_ flags: [LoupeFlag]) {
        var appendedNames: [String] = []
        for flag in flags {
            if values[flag.id] == nil { appendedNames.append(flag.id) }
            values[flag.id] = flag
        }
        if !appendedNames.isEmpty {
            revision += 1
            names.append(contentsOf: appendedNames)
            names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    func apply(_ value: String, to name: String) {
        guard let flag = values[name] else { return }
        if let url = flag.valueFileURL { try? FileManager.default.removeItem(at: url) }
        values[name] = flag.replacingValue(with: value)
    }

    func reset() { removeTemporaryFiles(); values.removeAll(); revision += 1; names.removeAll() }

    private func removeTemporaryFiles(excluding retainedFiles: Set<URL> = []) {
        let directories = Set(values.values.compactMap(\.valueFileURL).filter { !retainedFiles.contains($0) }
            .map { $0.deletingLastPathComponent() })
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
    }
}

private final class LoupeDraftStore: ObservableObject {
    @Published private(set) var dirtyIDs: Set<String> = []
    private var values: [String: String] = [:]
    private var savedSnapshot: [String: String] = [:]

    var hasChanges: Bool { !dirtyIDs.isEmpty }
    var allValues: [String: String] { values }
    func value(for id: String) -> String? { values[id] }

    func update(_ value: String, for id: String, originalValue: String) {
        if value == originalValue {
            values.removeValue(forKey: id)
        } else {
            values[id] = value
        }
        refreshDirty(for: id)
    }

    func removeValue(for id: String) {
        values.removeValue(forKey: id)
        refreshDirty(for: id)
    }

    func replace(with values: [String: String]) {
        self.values = values
        savedSnapshot = [:]
        dirtyIDs = Set(values.keys)
    }

    func markSaved() {
        savedSnapshot = values
        dirtyIDs = []
    }

    func reset() {
        values.removeAll()
        savedSnapshot.removeAll()
        dirtyIDs.removeAll()
    }

    private func refreshDirty(for id: String) {
        var next = dirtyIDs
        if values[id] != savedSnapshot[id] {
            next.insert(id)
        } else {
            next.remove(id)
        }
        if next != dirtyIDs {
            dirtyIDs = next
        }
    }
}

#if os(iOS)
private struct LoupeMachineExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.loupeMachineDocument] }
    static var writableContentTypes: [UTType] { [.loupeMachineDocument] }

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

struct LoupeMachineView: View {
    @AppStorage("showLoupeApplyVerification") private var showLoupeApplyVerification = true
    let request: LoupeMachineWindowRequest
    @State private var isImporting = false
    @State private var isOpeningDocument = false
    @State private var showDiscardConfirmation = false
    @State private var isDropTargeted = false
    @State private var selectedProgramURL: URL?
    @State private var sourceApplicationDisplayName: String?
    @State private var importError: String?
    @StateObject private var flagStore = LoupeFlagStore()
    @StateObject private var draftStore = LoupeDraftStore()
    @State private var hasFlags = false
    @State private var selectedFlagID: String?
    @State private var isInspecting = false
    @State private var documentURL: URL?
    @State private var savedDocumentData: Data?
    @State private var documentError: String?
    @State private var reconciliation: Reconciliation?
    @State private var unlockAllCategories = false
#if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsSidebar = true
    @State private var isExportingDocument = false
    @State private var exportDocument: LoupeMachineExportDocument?
    @State private var exportCompletion: ((Bool) -> Void)?

    private var usesColumnLayout: Bool {
        horizontalSizeClass == .regular
    }
#endif
#if os(macOS)
    @State private var inspection: DeboogeyLoupeInspection?
#endif

    private struct Reconciliation: Identifiable {
        let id = UUID()
        let document: LoupeMachineDocument
        let upstreamFlags: [LoupeFlag]
        let changedFlagIDs: Set<String>
    }

    var body: some View {
        Group {
            if hasFlags {
                flagBrowser
            } else {
                importView
            }
        }
#if os(iOS)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(sourceApplicationDisplayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !usesColumnLayout && selectedFlagID != nil {
                    Button {
                        selectedFlagID = nil
                    } label: {
                        Label(L10n.t("Flags"), systemImage: "chevron.backward")
                    }
                } else {
                    Button {
                        if hasUnsavedDocumentChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Label(L10n.t("Back"), systemImage: "chevron.backward")
                    }
                }
            }
            if usesColumnLayout {
                ToolbarItem(placement: .topBarLeading) {
                    sidebarVisibilityButton
                }
            }
            if hasFlags {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveDocument(forceSaveAs: false)
                    } label: {
                        Label(L10n.t("Save Change Set"), systemImage: "square.and.arrow.down")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!hasUnsavedDocumentChanges)
                }
            }
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            guard usesColumnLayout, hasFlags, selectedFlagID == nil else { return }
            selectedFlagID = flagStore.names.first
        }
        .fileImporter(
            isPresented: $isOpeningDocument,
            allowedContentTypes: [.loupeMachineDocument],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                openPickedDocument(at: url)
            case .failure(let error):
                documentError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExportingDocument,
            document: exportDocument,
            contentType: .loupeMachineDocument,
            defaultFilename: documentExportDefaultFilename
        ) { result in
            handleDocumentExport(result)
        }
        .alert(
            L10n.t("Save changes to this Loupe Machine document?"),
            isPresented: $showDiscardConfirmation
        ) {
            Button(L10n.t("Save")) {
                saveDocument(forceSaveAs: false)
            }
            Button(L10n.t("Don't Save"), role: .destructive) {
                dismiss()
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("Your unapplied drafted value changes will be lost if you don’t save them."))
        }
#else
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectProgram(at: url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .background(
            LoupeWindowCloseCoordinator(
                hasUnappliedChanges: hasUnsavedDocumentChanges,
                documentURL: documentURL,
                applicationURL: selectedProgramURL,
                commandActions: LoupeMachineCommandActions(
                    canSave: hasFlags,
                    save: { saveDocument(forceSaveAs: false) },
                    saveAs: { saveDocument(forceSaveAs: true) }
                ),
                saveDraft: saveDraftForClosing,
                didClose: { inspection?.cancel() }
            )
        )
#endif
        .alert(L10n.t("Loupe Machine Document Error"), isPresented: Binding(
            get: { documentError != nil },
            set: { if !$0 { documentError = nil } }
        )) {
            Button(L10n.t("OK"), role: .cancel) {}
        } message: {
            Text(documentError ?? "")
        }
#if os(macOS)
        .alert(item: $reconciliation) { reconciliation in
            Alert(
                title: Text(L10n.t("Local values have changed")),
                message: Text(L10n.f(
                    "%d value(s) changed outside Loupe Machine after this document was saved.",
                    reconciliation.changedFlagIDs.count
                )),
                primaryButton: .default(Text(L10n.t("Keep Local Changes"))) {
                    resolve(reconciliation, revertingToDocument: false)
                },
                secondaryButton: .default(Text(L10n.t("Revert to Document Values"))) {
                    resolve(reconciliation, revertingToDocument: true)
                }
            )
        }
#endif
        .onAppear(perform: handleDocumentRequest)
    }

    private var importView: some View {
#if os(iOS)
        Color.clear
#else
        ZStack {
            LoupeMachineRippleEffect()

            VStack(spacing: 30) {
                HStack {
                    Image("LoupeMachineIdent")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)

                    Text(L10n.t("Loupe Machine"))
                        .font(.largeTitle.weight(.semibold))
                }

                dropArea

                Text(L10n.t("Drop a program here to inspect its flags."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(48)
            .frame(maxWidth: 680)
        }
#endif
    }

    @ViewBuilder
    private var flagBrowser: some View {
#if os(iOS)
        if usesColumnLayout {
            HStack(spacing: 0) {
                if showsSidebar {
                    flagSidebar
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 340)
                        .frame(maxHeight: .infinity)
                    Divider()
                }
                flagDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Group {
                if selectedFlagID != nil {
                    flagDetail
                } else {
                    flagSidebar
                }
            }
        }
#else
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                flagSidebar
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            } detail: {
                flagDetail
            }
        } else {
            NavigationView {
                flagSidebar
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
                flagDetail
                    .frame(minWidth: 520)
            }
        }
#endif
    }

    private var flagSidebar: some View {
#if os(iOS)
        LoupeFlagSidebar(
            store: flagStore,
            drafts: draftStore,
            selection: $selectedFlagID,
            unlockAllCategories: unlockAllCategories,
            usesColumnLayout: usesColumnLayout
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isInspecting {
                VStack(spacing: 0) {
                    Divider()
                    ProgressView(L10n.t("Inspecting flags…"))
                        .padding()
                }
                .background(.bar)
            }
        }
#else
        VStack(spacing: 0) {
            LoupeFlagSidebar(
                store: flagStore,
                drafts: draftStore,
                selection: $selectedFlagID,
                unlockAllCategories: unlockAllCategories
            )
            if isInspecting {
                Divider()
                ProgressView(L10n.t("Inspecting flags…"))
                    .padding()
            }
        }
        .navigationTitle(L10n.t("Flags"))
#endif
    }

#if os(iOS)
    private var sidebarVisibilityButton: some View {
        Button {
            showsSidebar.toggle()
        } label: {
            Label(L10n.t("Show Sidebar"), systemImage: "sidebar.left")
        }
        .labelStyle(.iconOnly)
    }
#endif

    @ViewBuilder
    private var flagDetail: some View {
        if let selectedFlag {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedFlag.name)
                    .font(.title2.weight(.semibold))
                LoupeValueEditor(
                    flag: selectedFlag,
                    initialValue: draftStore.value(for: selectedFlag.id),
                    hasPendingValues: draftStore.hasChanges,
                    updateDraft: { updateDraft($0, for: selectedFlag) },
                    applyCurrent: applyCurrentlyViewed,
                    applyAll: applyAllPending
                )
                .id(selectedFlag.id)
            }
#if os(iOS)
            .padding(16)
#else
            .padding(24)
#endif
        } else {
            Text(L10n.t("Select a flag to inspect its value."))
                .foregroundStyle(.secondary)
        }
    }

    private var selectedFlag: LoupeFlag? {
        flagStore.flag(named: selectedFlagID)
    }

    private func updateDraft(_ newValue: String, for flag: LoupeFlag) {
        if newValue == flag.value {
            draftStore.removeValue(for: flag.id)
        } else { draftStore.update(newValue, for: flag.id, originalValue: flag.value) }
    }

#if DEBOOGEY_MCE
    private func applyCurrentlyViewed() {}
    private func applyAllPending() {
#if os(iOS)
        saveDocument(forceSaveAs: false)
#else
        saveDocument(forceSaveAs: documentURL == nil)
#endif
    }
#else
    private func applyCurrentlyViewed() {
        guard let selectedFlagID, let value = draftStore.value(for: selectedFlagID) else { return }
        apply([selectedFlagID: value])
    }

    private func applyAllPending() {
        apply(draftStore.allValues)
    }

    private func apply(_ values: [String: String]) {
        guard !values.isEmpty else { return }
        let flagValues = Dictionary(uniqueKeysWithValues: values.compactMap { id, value in
            flagStore.flag(named: id).map { ($0, value) }
        })
        guard flagValues.count == values.count else { return }
        if showLoupeApplyVerification {
            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = L10n.t("Apply changes to application data?")
            confirmation.informativeText = L10n.f("Loupe Machine will apply %d value(s) to the selected application.", values.count)
            confirmation.addButton(withTitle: L10n.t("Apply"))
            confirmation.addButton(withTitle: L10n.t("Cancel"))
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        }

        let result: Result<Void, Error> = Result {
            guard let selectedProgramURL else { throw LoupeApplicationDataError.applicationUnavailable }
            try LoupeApplicationData.apply(flagValues, to: selectedProgramURL)
        }

        let alert = NSAlert()
        switch result {
        case .success:
            for (id, value) in values {
                flagStore.apply(value, to: id)
                draftStore.removeValue(for: id)
            }
            alert.alertStyle = .informational
            alert.messageText = L10n.t("Changes Applied")
            alert.informativeText = L10n.f("Loupe Machine applied %d value(s) successfully.", values.count)
        case .failure(let error):
            alert.alertStyle = .critical
            alert.messageText = L10n.t("Changes Could Not Be Applied")
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: L10n.t("OK"))
        alert.runModal()
    }
#endif

    private func handleDocumentRequest() {
        guard let url = request.documentURL else {
            resetSession()
#if os(macOS)
            if request.action == .importApplication {
                DispatchQueue.main.async { presentApplicationImporter() }
            }
#endif
            return
        }
        openExistingDocument(at: url, allowReinspect: true)
    }

    private func openPickedDocument(at url: URL) {
        openExistingDocument(at: url, allowReinspect: false)
    }

    private func openExistingDocument(at url: URL, allowReinspect: Bool) {
        do {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let document = try LoupeMachineDocument.read(from: url)
            documentURL = url
            importError = nil
            unlockAllCategories = document.containsNonMCECategories
#if os(iOS)
            try adopt(document)
            draftStore.markSaved()
            return
#else
            guard allowReinspect, !document.containsNonMCECategories else {
                try adopt(document)
                return
            }
            guard let sourceURL = sourceApplicationURL(in: document, relativeTo: url) else {
                try adopt(document)
                return
            }
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                try adopt(document)
                return
            }

            try adopt(document, sourceApplicationURL: sourceURL)
            isInspecting = true
            inspection?.cancel()
            let currentInspection = DeboogeyLoupeInspection()
            inspection = currentInspection
            let hasSourceAccess = sourceURL.startAccessingSecurityScopedResource()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result {
                    try DeboogeyLoupeLauncher.inspect(
                        appURL: sourceURL,
                        inspection: currentInspection
                    )
                }
                if hasSourceAccess { sourceURL.stopAccessingSecurityScopedResource() }
                DispatchQueue.main.async {
                    isInspecting = false
                    switch result {
                    case .success(let upstreamFlags):
                        recordCompletedIndex(for: sourceURL)
                        reconcileIfNeeded(document: document, upstreamFlags: upstreamFlags)
                    case .failure(let error):
                        try? adopt(document, sourceApplicationURL: sourceURL)
                        documentError = error.localizedDescription
                    }
                }
            }
#endif
        } catch {
            resetSession()
            documentError = error.localizedDescription
        }
    }

    private func adopt(
        _ document: LoupeMachineDocument,
        sourceApplicationURL: URL? = nil
    ) throws {
        load(document, sourceApplicationURL: sourceApplicationURL)
        savedDocumentData = try currentDocument.encoded()
    }

    private func reconcileIfNeeded(document: LoupeMachineDocument, upstreamFlags: [LoupeFlag]) {
        let documentValues = Dictionary(uniqueKeysWithValues: document.flags.map { ($0.name, $0.value) })
        let changedFlagIDs = Set(upstreamFlags.compactMap { flag -> String? in
            guard document.draftedValues[flag.id] == nil,
                  let documentValue = documentValues[flag.id],
                  documentValue != flag.value else { return nil }
            return flag.id
        })

        guard !changedFlagIDs.isEmpty else {
            load(document, using: upstreamFlags)
            savedDocumentData = try? currentDocument.encoded()
            return
        }
        reconciliation = Reconciliation(
            document: document,
            upstreamFlags: upstreamFlags,
            changedFlagIDs: changedFlagIDs
        )
    }

    private func resolve(_ reconciliation: Reconciliation, revertingToDocument: Bool) {
        let documentValues = Dictionary(
            uniqueKeysWithValues: reconciliation.document.flags.map { ($0.name, $0.value) }
        )
        var drafts = reconciliation.document.draftedValues
        if revertingToDocument {
            for id in reconciliation.changedFlagIDs {
                drafts[id] = documentValues[id]
            }
        }
        load(reconciliation.document, using: reconciliation.upstreamFlags, draftedValues: drafts)
        savedDocumentData = try? currentDocument.encoded()
    }

    private func load(
        _ document: LoupeMachineDocument,
        using loadedFlags: [LoupeFlag]? = nil,
        draftedValues: [String: String]? = nil,
        sourceApplicationURL: URL? = nil
    ) {
        flagStore.replace(with: loadedFlags ?? document.flags.map {
            LoupeFlag(
                name: $0.name,
                value: $0.value,
                source: $0.source,
                keyPath: $0.keyPath,
                backingFilePath: $0.backingFilePath
            )
        })
        let drafts = (draftedValues ?? document.draftedValues).filter { name, _ in
            flagStore.flag(named: name) != nil
        }
        draftStore.replace(with: drafts)
        hasFlags = !flagStore.isEmpty
#if os(iOS)
        selectedFlagID = usesColumnLayout ? flagStore.names.first : nil
#else
        selectedFlagID = flagStore.names.first
#endif
        selectedProgramURL = sourceApplicationURL
            ?? selectedProgramURL
            ?? document.sourceApplication.map(URL.init(fileURLWithPath:))
        sourceApplicationDisplayName =
            Self.applicationDisplayName(for: selectedProgramURL)
            ?? Self.applicationDisplayName(forPath: document.sourceApplication)
    }

    private static func applicationDisplayName(for url: URL?) -> String? {
        guard let url else { return nil }
        return applicationDisplayName(forPath: url.path)
    }

    private static func applicationDisplayName(forPath path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }

    private func saveDraftForClosing(completion: @escaping (Bool) -> Void) {
        saveDocument(forceSaveAs: documentURL == nil, completion: completion)
    }

    private func saveDocument(
        forceSaveAs: Bool,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
#if os(iOS)
        if !forceSaveAs {
            if let documentURL, documentURL.pathExtension.lowercased() == "loum" {
                writeDocument(to: documentURL, completion: completion)
            } else {
                let preferredName = documentURL?.lastPathComponent ?? L10n.t("Untitled.loum")
                let name = preferredName.lowercased().hasSuffix(".loum")
                    ? preferredName
                    : "\(preferredName).loum"
                writeDocument(
                    to: DeboogeyAppDocuments.uniqueURL(preferredFilename: name),
                    completion: completion
                )
            }
            return
        }
        presentDocumentExporter(completion: completion)
#else
        if !forceSaveAs, let documentURL {
            writeDocument(to: documentURL, completion: completion)
            return
        }

        let panel = NSSavePanel()
        panel.title = L10n.t("Save Loupe Machine Document")
        panel.allowedContentTypes = [.loupeMachineDocument]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = documentURL?.lastPathComponent ?? L10n.t("Untitled.loum")

        panel.begin { response in
            guard response == .OK, var url = panel.url else {
                completion(false)
                return
            }
            if url.pathExtension.lowercased() != "loum" {
                url.appendPathExtension("loum")
            }
            writeDocument(to: url, completion: completion)
        }
#endif
    }

#if os(iOS)
    private var documentExportDefaultFilename: String {
        documentURL?.deletingPathExtension().lastPathComponent ?? L10n.t("Untitled")
    }

    private func presentDocumentExporter(completion: @escaping (Bool) -> Void) {
        do {
            let data = try currentDocument.encoded()
            exportDocument = LoupeMachineExportDocument(data: data)
            exportCompletion = completion
            isExportingDocument = true
        } catch {
            documentError = error.localizedDescription
            completion(false)
        }
    }

    private func handleDocumentExport(_ result: Result<URL, Error>) {
        let completion = exportCompletion ?? { _ in }
        let data = exportDocument?.data
        exportCompletion = nil
        exportDocument = nil

        switch result {
        case .success(let url):
            guard let data else {
                completion(false)
                return
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let activity: TrackedEntity.LoupeActivity =
                documentURL?.standardizedFileURL == url.standardizedFileURL
                    ? .documentModified
                    : .documentCreated
            documentURL = url
            savedDocumentData = data
            draftStore.markSaved()
            EntityTracker.shared.record(
                source: .loupeMachine,
                arguments: [activity.rawValue, url.lastPathComponent]
            )
            completion(true)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                completion(false)
                return
            }
            documentError = error.localizedDescription
            completion(false)
        }
    }
#endif

    private func writeDocument(to url: URL, completion: @escaping (Bool) -> Void) {
        do {
            let activity: TrackedEntity.LoupeActivity = FileManager.default.fileExists(atPath: url.path)
                ? .documentModified
                : .documentCreated
            let data = try currentDocument(relativeTo: url).encoded()
            try data.write(to: url, options: .atomic)
            documentURL = url
            savedDocumentData = data
#if os(iOS)
            draftStore.markSaved()
#endif
            EntityTracker.shared.record(
                source: .loupeMachine,
                arguments: [activity.rawValue, url.lastPathComponent]
            )
            completion(true)
        } catch {
            documentError = error.localizedDescription
            completion(false)
        }
    }

    private var currentDocument: LoupeMachineDocument {
        currentDocument(relativeTo: documentURL)
    }

    private func currentDocument(relativeTo documentURL: URL?) -> LoupeMachineDocument {
        LoupeMachineDocument(
            sourceApplication: selectedProgramURL?.path,
            sourceApplicationBookmark: sourceApplicationBookmark(relativeTo: documentURL),
            flags: flagStore.flags,
            draftedValues: draftStore.allValues
        )
    }

    private func sourceApplicationBookmark(relativeTo documentURL: URL?) -> Data? {
#if os(macOS) && DEBOOGEY_MCE
        guard let selectedProgramURL, let documentURL else { return nil }
        return try? selectedProgramURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: documentURL
        )
#else
        return nil
#endif
    }

    private func sourceApplicationURL(
        in document: LoupeMachineDocument,
        relativeTo documentURL: URL
    ) -> URL? {
#if os(macOS) && DEBOOGEY_MCE
        if let bookmark = document.sourceApplicationBookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: documentURL,
                bookmarkDataIsStale: &stale
            ), !stale {
                return url
            }
        }
#endif
        return document.sourceApplication.map(URL.init(fileURLWithPath:))
    }

    private var hasUnsavedDocumentChanges: Bool {
        guard hasFlags else { return false }
        return (try? currentDocument.encoded()) != savedDocumentData
    }

    private func resetSession() {
        selectedProgramURL = nil
        sourceApplicationDisplayName = nil
        flagStore.reset()
        hasFlags = false
        selectedFlagID = nil
        draftStore.reset()
        documentURL = nil
        savedDocumentData = nil
        importError = nil
        isInspecting = false
        reconciliation = nil
        unlockAllCategories = false
    }

#if os(macOS)
    @ViewBuilder
    private var dropArea: some View {
        if #available(macOS 26.0, *) {
            dropAreaContent
                .glassEffect(
                    .clear.tint(.accentColor.opacity(0.15)).interactive(),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        } else {
            dropAreaContent
        }
    }

    private var dropAreaContent: some View {
        VStack(spacing: 20) {
            Image(importHintImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            Button(L10n.t("Import…")) {
                presentApplicationImporter()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isInspecting)

            if isInspecting {
                ProgressView(L10n.t("Inspecting flags…"))
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(38)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 1.5, dash: [9, 7])
                )
        }
        .scaleEffect(isDropTargeted ? 1.015 : 1)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: importDroppedPrograms)
    }

    private var importHintImageName: String {
        switch ProcessInfo.processInfo.operatingSystemVersion.majorVersion {
        case 26:
            "ImportLMAppHint26"
        case 27:
            "ImportLMAppHint27"
        default:
            "ImportLMAppHintRaw"
        }
    }

    private func presentApplicationImporter() {
        if #available(macOS 13.0, *) {
            isImporting = true
        } else {
            let panel = NSOpenPanel()
            panel.title = L10n.t("Import macOS Application")
            panel.prompt = L10n.t("Import")
            panel.allowedContentTypes = [.applicationBundle]
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.treatsFilePackagesAsDirectories = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                selectProgram(at: url)
            }
        }
    }

    private func importDroppedPrograms(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            DispatchQueue.main.async {
                if let error {
                    importError = error.localizedDescription
                    return
                }

                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }

                guard let url else {
                    importError = L10n.t("The dropped item could not be opened.")
                    return
                }
                selectProgram(at: url)
            }
        }
        return true
    }

    private func selectProgram(at url: URL) {
        guard url.pathExtension.lowercased() == "app" else {
            selectedProgramURL = nil
            importError = L10n.t("Choose a macOS application bundle ending in .app.")
            return
        }

        selectedProgramURL = url
        importError = nil
        isInspecting = true
        flagStore.reset()
        hasFlags = false
        draftStore.reset()
        selectedFlagID = nil
        unlockAllCategories = false

        inspection?.cancel()
        let currentInspection = DeboogeyLoupeInspection()
        inspection = currentInspection
        let hasAccess = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try DeboogeyLoupeLauncher.inspect(appURL: url, inspection: currentInspection) { batch in
                    DispatchQueue.main.async {
                        flagStore.append(batch)
                        if !hasFlags, !flagStore.isEmpty { hasFlags = true }
                        if selectedFlagID == nil { selectedFlagID = flagStore.names.first }
                    }
                }
            }
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                isInspecting = false
                switch result {
                case .success(let inspectedFlags):
                    flagStore.replace(with: inspectedFlags)
                    hasFlags = !flagStore.isEmpty
                    if selectedFlagID == nil { selectedFlagID = inspectedFlags.first?.id }
                    if inspectedFlags.isEmpty {
                        discardSelectedApplication()
                        presentNoFlagsAlert()
                    } else {
                        recordCompletedIndex(for: url)
                    }
                case .failure(let error):
                    discardSelectedApplication()
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func discardSelectedApplication() {
        inspection = nil
        selectedProgramURL = nil
        flagStore.reset()
        hasFlags = false
        selectedFlagID = nil
        draftStore.reset()
        importError = nil
        unlockAllCategories = false
    }

    private func presentNoFlagsAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("No Flags Found")
        alert.informativeText = L10n.t("No flags were found for this application.")
        alert.addButton(withTitle: L10n.t("OK"))
        alert.runModal()
    }

    private func recordCompletedIndex(for applicationURL: URL) {
        let bundle = Bundle(url: applicationURL)
        let applicationName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let identifier = bundle?.bundleIdentifier ?? ""
        EntityTracker.shared.record(
            source: .loupeMachine,
            arguments: [
                TrackedEntity.LoupeActivity.applicationIndexed.rawValue,
                applicationName,
                identifier
            ]
        )
        IndexCompletionFeedback.playSoundIfEnabled()
        IndexCompletionFeedback.notifyIndexingFinished(for: applicationName)
    }
#endif
}

private struct LoupeMachineRippleEffect: View {
    private let rippleDuration = 4.8
    private let rippleCount = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate / rippleDuration

            ZStack {
                rippleImage
                    .scaleEffect(1.4)
                    .rotationEffect(.degrees(cycle * 105))
                    .opacity(0.3)

                ForEach(0..<rippleCount, id: \.self) { index in
                    let progress = (cycle + Double(index) / Double(rippleCount))
                        .truncatingRemainder(dividingBy: 1)
                    let visibility = sin(progress * .pi)

                    rippleImage
                        .scaleEffect(1.08 + progress * 0.5)
                        .rotationEffect(.degrees(
                            cycle * (index.isMultiple(of: 2) ? 165 : -125)
                        ))
                        .opacity(0.28 * visibility)
                        .blur(radius: 1.5 + progress * 4)
                        .mask {
                            LiquidWavefront(
                                progress: progress,
                                phase: cycle * .pi * 2 + Double(index) * 1.7
                            )
                            .stroke(
                                style: StrokeStyle(
                                    lineWidth: 100 - progress * 34,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .rotationEffect(.degrees(
                                cycle * (index.isMultiple(of: 2) ? -70 : 90)
                            ))
                            .blur(radius: 40)
                        }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var rippleImage: some View {
        Image("LoupeMachineSpinGraphic")
            .resizable()
            .scaledToFill()
    }
}

private struct LiquidWavefront: Shape {
    let progress: Double
    let phase: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maximumRadius = hypot(rect.width, rect.height) * 0.62
        let radius = maximumRadius * (0.05 + progress * 0.95)
        let amplitude = 8 + 18 * sin(progress * .pi)
        let pointCount = 180
        var path = Path()

        for point in 0...pointCount {
            let angle = Double(point) / Double(pointCount) * .pi * 2
            let liquidOffset = sin(angle * 3 + phase) * amplitude
                + sin(angle * 7 - phase * 1.35) * amplitude * 0.38
                + sin(angle * 11 + phase * 0.55) * amplitude * 0.16
            let waveRadius = max(0, radius + liquidOffset)
            let position = CGPoint(
                x: center.x + cos(angle) * waveRadius,
                y: center.y + sin(angle) * waveRadius
            )

            if point == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        return path
    }
}

private enum LoupeFlagCategory: Int, CaseIterable, Identifiable {
    case all
    case defaults
    case globalDefaults
    case featureFlags
    case disassembled
    case other

    var id: Int { rawValue }

    static func visibleCases(unlockAll: Bool) -> [Self] {
#if DEBOOGEY_MCE
        return unlockAll ? Array(allCases) : [.all, .featureFlags, .disassembled]
#else
        _ = unlockAll
        return Array(allCases)
#endif
    }

    static func initialSelection(unlockAll: Bool) -> Self {
        visibleCases(unlockAll: unlockAll).first ?? .all
    }

    var title: String {
        switch self {
        case .all: return L10n.t("All")
        case .defaults: return L10n.t("Defaults")
        case .globalDefaults: return L10n.t("Global Defaults")
        case .featureFlags: return L10n.t("Feature Flags")
        case .disassembled: return L10n.t("Disassembled")
        case .other: return L10n.t("Other")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .defaults: return "slider.horizontal.3"
        case .globalDefaults: return "globe"
        case .featureFlags: return "flag.2.crossed"
        case .disassembled: return "cpu"
        case .other: return "ellipsis"
        }
    }

    func contains(_ name: String) -> Bool {
        switch self {
        case .all: return true
        case .defaults: return name.hasPrefix("defaults.")
        case .globalDefaults: return name.hasPrefix("globalDefaults.")
        case .featureFlags: return name.hasPrefix("systemFeatureFlags.")
        case .disassembled: return name.hasPrefix("binaryFlags.")
        case .other:
            return ![Self.defaults, .globalDefaults, .featureFlags, .disassembled]
                .contains { $0.contains(name) }
        }
    }
}

#if os(macOS)
private struct LoupeFlagSearchableModifier: ViewModifier {
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.searchable(
                text: $text,
                placement: .toolbar,
                prompt: L10n.t("Search Flags")
            )
        } else {
            content.searchable(
                text: $text,
                prompt: L10n.t("Search Flags")
            )
        }
    }
}

private struct LoupeCategoryPicker: NSViewRepresentable {
    @Binding var selection: LoupeFlagCategory
    var unlockAllCategories: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let control = NSSegmentedControl(
            labels: Array(repeating: "", count: visibleCases.count),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectCategory(_:))
        )
        control.segmentDistribution = .fillEqually
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(L10n.t("Flag category"))
        configure(control)

        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.control = control
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        guard let control = context.coordinator.control else { return }
        if control.segmentCount != visibleCases.count {
            control.segmentCount = visibleCases.count
            configure(control)
        }
        control.selectedSegment = visibleCases.firstIndex(of: selection) ?? 0
    }

    private var visibleCases: [LoupeFlagCategory] {
        LoupeFlagCategory.visibleCases(unlockAll: unlockAllCategories)
    }

    private func configure(_ control: NSSegmentedControl) {
        for (segment, option) in visibleCases.enumerated() {
            control.setImage(
                NSImage(
                    systemSymbolName: option.systemImage,
                    accessibilityDescription: option.title
                ),
                forSegment: segment
            )
            control.setToolTip(option.title, forSegment: segment)
        }
    }

    final class Coordinator: NSObject {
        var parent: LoupeCategoryPicker
        weak var control: NSSegmentedControl?

        init(_ parent: LoupeCategoryPicker) { self.parent = parent }

        @objc func selectCategory(_ sender: NSSegmentedControl) {
            let cases = LoupeFlagCategory.visibleCases(unlockAll: parent.unlockAllCategories)
            guard cases.indices.contains(sender.selectedSegment) else { return }
            parent.selection = cases[sender.selectedSegment]
        }
    }
}

#endif

private struct LoupeFlagSidebar: View {
    @ObservedObject var store: LoupeFlagStore
    @ObservedObject var drafts: LoupeDraftStore
    @Binding var selection: String?
    var unlockAllCategories: Bool
#if os(iOS)
    var usesColumnLayout: Bool = false
#endif
    @State private var category: LoupeFlagCategory = .all
    @State private var searchText = ""

    private var visibleCases: [LoupeFlagCategory] {
        LoupeFlagCategory.visibleCases(unlockAll: unlockAllCategories)
    }

    private var names: [String] { names(for: category) }

    var body: some View {
#if os(iOS)
        let rowNames = names
        let dirtyIDs = drafts.dirtyIDs
        let countLabel = itemCountLabel
        Group {
            if usesColumnLayout {
                List(selection: $selection) {
                    iosFlagSection(rowNames: rowNames, countLabel: countLabel) { name in
                        flagRow(name: name, dirtyIDs: dirtyIDs, showsChevron: false)
                            .tag(name)
                    }
                }
            } else {
                List {
                    iosFlagSection(rowNames: rowNames, countLabel: countLabel) { name in
                        Button {
                            selection = name
                        } label: {
                            flagRow(name: name, dirtyIDs: dirtyIDs, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0)
        .searchable(text: $searchText, prompt: L10n.t("Search Flags"))
        .onAppear {
            clampCategoryIfNeeded()
            refreshSelectionForVisibleFlags()
        }
        .onChange(of: unlockAllCategories) { _, _ in
            clampCategoryIfNeeded()
            refreshSelectionForVisibleFlags()
        }
        .onChange(of: category) { _, _ in refreshSelectionForVisibleFlags() }
        .onChange(of: searchText) { _, _ in refreshSelectionForVisibleFlags() }
        .onChange(of: store.revision) { _, _ in refreshSelectionForVisibleFlags() }
        .onChange(of: usesColumnLayout) { _, _ in refreshSelectionForVisibleFlags() }
#else
        VStack(spacing: 0) {
            LoupeCategoryPicker(selection: $category, unlockAllCategories: unlockAllCategories)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            Divider()

            flagList(for: category)

            Divider()

            Text(itemCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(LoupeFlagSearchableModifier(text: $searchText))
        .onAppear {
            clampCategoryIfNeeded()
            selectVisibleFlagIfNeeded()
        }
        .onChange(of: unlockAllCategories) { _ in
            clampCategoryIfNeeded()
            selectVisibleFlagIfNeeded()
        }
        .onChange(of: category) { _ in selectVisibleFlagIfNeeded() }
        .onChange(of: searchText) { _ in selectVisibleFlagIfNeeded() }
        .onChange(of: store.revision) { _ in selectVisibleFlagIfNeeded() }
#endif
    }

    private func clampCategoryIfNeeded() {
        guard !visibleCases.contains(category) else { return }
        category = LoupeFlagCategory.initialSelection(unlockAll: unlockAllCategories)
    }

#if os(macOS)
    @ViewBuilder
    private func flagList(for option: LoupeFlagCategory) -> some View {
        let optionNames = names(for: option)
        if optionNames.isEmpty {
            emptyFlagList
        } else {
            LoupeFlagTable(
                names: optionNames,
                version: LoupeFlagListVersion(
                    storeRevision: store.revision,
                    category: option,
                    searchText: searchText
                ),
                dirtyIDs: drafts.dirtyIDs,
                selection: $selection
            )
        }
    }
#endif

    @ViewBuilder
    private var emptyFlagList: some View {
        let title = searchText.isEmpty ? L10n.t("No Flags") : L10n.t("No Results")
        let systemImage = searchText.isEmpty ? "flag.slash" : "magnifyingglass"

        Group {
            if #available(iOS 17.0, macOS 14.0, *) {
                ContentUnavailableView(title, systemImage: systemImage)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.title2)
                    Text(title)
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func names(for option: LoupeFlagCategory) -> [String] {
        store.names.filter { name in
            option.contains(name)
                && (searchText.isEmpty || name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var itemCountLabel: String {
        searchText.isEmpty
            ? L10n.f("%d indexed item(s)", names.count)
            : L10n.f("%d item(s)", names.count)
    }

    private func selectVisibleFlagIfNeeded() {
        if let selection, names.contains(selection) { return }
        selection = names.first
    }

#if os(iOS)
    @ViewBuilder
    private func iosFlagSection<Row: View>(
        rowNames: [String],
        countLabel: String,
        @ViewBuilder row: @escaping (String) -> Row
    ) -> some View {
        Section {
            categoryPicker

            if rowNames.isEmpty {
                emptyFlagList
                    .listRowBackground(Color.clear)
            } else {
                ForEach(rowNames, id: \.self) { name in
                    row(name)
                }
            }
        } footer: {
            Text(countLabel)
        }
    }

    private var categoryPicker: some View {
        Picker(L10n.t("Flag category"), selection: $category) {
            ForEach(visibleCases) { option in
                Image(systemName: option.systemImage)
                    .accessibilityLabel(option.title)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func flagRow(name: String, dirtyIDs: Set<String>, showsChevron: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if dirtyIDs.contains(name) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel(L10n.t("Pending change"))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func refreshSelectionForVisibleFlags() {
        if usesColumnLayout {
            selectVisibleFlagIfNeeded()
        } else {
            clearSelectionIfNotVisible()
        }
    }

    private func clearSelectionIfNotVisible() {
        guard let selection, !names.contains(selection) else { return }
        self.selection = nil
    }
#endif
}

#if os(macOS)
private struct LoupeFlagListVersion: Equatable {
    let storeRevision: Int
    let category: LoupeFlagCategory
    let searchText: String
}

private struct LoupeFlagTable: NSViewRepresentable {
    let names: [String]
    let version: LoupeFlagListVersion
    let dirtyIDs: Set<String>
    @Binding var selection: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Flag"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 32
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.usesAlternatingRowBackgroundColors = false
        table.allowsEmptySelection = true
        table.style = .sourceList
        table.backgroundColor = .clear
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        context.coordinator.names = names
        context.coordinator.indexByName = Dictionary(
            uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) }
        )
        context.coordinator.version = version
        context.coordinator.dirtyIDs = dirtyIDs

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = table
        context.coordinator.tableView = table
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.version != version {
            coordinator.names = names
            coordinator.indexByName = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) })
            coordinator.version = version
            coordinator.dirtyIDs = dirtyIDs
            coordinator.tableView?.reloadData()
        } else if coordinator.dirtyIDs != dirtyIDs {
            coordinator.dirtyIDs = dirtyIDs
            coordinator.tableView?.reloadData(forRowIndexes: IndexSet(integersIn: 0..<names.count), columnIndexes: IndexSet(integer: 0))
        }
        coordinator.selectRow(named: selection)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: LoupeFlagTable
        weak var tableView: NSTableView?
        var names: [String] = []
        var indexByName: [String: Int] = [:]
        var version: LoupeFlagListVersion?
        var dirtyIDs: Set<String> = []
        private var isUpdatingSelection = false

        init(_ parent: LoupeFlagTable) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { names.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("FlagCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? FlagCellView ?? {
                let cell = FlagCellView()
                cell.identifier = identifier
                return cell
            }()
            let name = names[row]
            cell.configure(name: name, isDirty: dirtyIDs.contains(name))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection, let tableView else { return }
            let row = tableView.selectedRow
            parent.selection = names.indices.contains(row) ? names[row] : nil
        }

        func selectRow(named name: String?) {
            guard let tableView else { return }
            let desiredRow = name.flatMap { indexByName[$0] } ?? -1
            guard tableView.selectedRow != desiredRow else { return }
            isUpdatingSelection = true
            if desiredRow >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: desiredRow), byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
            isUpdatingSelection = false
        }
    }

    private final class FlagCellView: NSTableCellView {
        private let dirtyIndicator = NSImageView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            let title = NSTextField(labelWithString: "")
            title.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            title.lineBreakMode = .byTruncatingMiddle
            title.translatesAutoresizingMaskIntoConstraints = false
            textField = title

            dirtyIndicator.image = NSImage(
                systemSymbolName: "exclamationmark.circle.fill",
                accessibilityDescription: L10n.t("Pending change")
            )
            dirtyIndicator.contentTintColor = .systemRed
            dirtyIndicator.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            dirtyIndicator.translatesAutoresizingMaskIntoConstraints = false
            dirtyIndicator.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(title)
            addSubview(dirtyIndicator)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                title.trailingAnchor.constraint(equalTo: dirtyIndicator.leadingAnchor, constant: -8),
                title.centerYAnchor.constraint(equalTo: centerYAnchor),
                dirtyIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                dirtyIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                dirtyIndicator.widthAnchor.constraint(equalToConstant: 14),
                dirtyIndicator.heightAnchor.constraint(equalToConstant: 14)
            ])
        }

        required init?(coder: NSCoder) { nil }

        func configure(name: String, isDirty: Bool) {
            textField?.stringValue = name
            dirtyIndicator.isHidden = !isDirty
        }
    }
}

#endif

private struct LoupeValueEditor: View {
    let flag: LoupeFlag
    let initialValue: String?
    let hasPendingValues: Bool
    let updateDraft: (String) -> Void
    let applyCurrent: () -> Void
    let applyAll: () -> Void
    @State private var value: String

    init(
        flag: LoupeFlag,
        initialValue: String?,
        hasPendingValues: Bool,
        updateDraft: @escaping (String) -> Void,
        applyCurrent: @escaping () -> Void,
        applyAll: @escaping () -> Void
    ) {
        self.flag = flag
        self.initialValue = initialValue
        self.hasPendingValues = hasPendingValues
        self.updateDraft = updateDraft
        self.applyCurrent = applyCurrent
        self.applyAll = applyAll
        _value = State(initialValue: initialValue ?? flag.value)
    }

    var body: some View {
        TextEditor(text: $value)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
#if os(iOS)
            .background(Color(.secondarySystemBackground))
#else
            .background(Color(nsColor: .textBackgroundColor))
#endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: value) { newValue in
                updateDraft(newValue)
            }

#if !os(iOS) && DEBOOGEY_MCE
        HStack {
            Text(L10n.t("Save pending edits as a portable Loupe Machine change set."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(L10n.t("Save Change Set")) {
                flushDraft()
                applyAll()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasPendingValues && value == flag.value)
        }
#elseif !DEBOOGEY_MCE
        HStack {
            Spacer()
            Button(L10n.t("Apply Currently Viewed")) {
                flushDraft()
                applyCurrent()
            }
            .disabled(value == flag.value)
            Button(L10n.t("Apply All Pending")) {
                flushDraft()
                applyAll()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasPendingValues && value == flag.value)
        }
#endif
    }

    private func flushDraft() {
        updateDraft(value)
    }
}

#if os(macOS)
private struct LoupeWindowCloseCoordinator: NSViewRepresentable {
    private static let applicationAccessoryIdentifier = NSUserInterfaceItemIdentifier(
        "theoderoy.Deboogey.LoupeMachine.application-accessory"
    )
    let hasUnappliedChanges: Bool
    let documentURL: URL?
    let applicationURL: URL?
    let commandActions: LoupeMachineCommandActions
    let saveDraft: (@escaping (Bool) -> Void) -> Void
    let didClose: () -> Void

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
        coordinator.hasUnappliedChanges = hasUnappliedChanges
        coordinator.commandActions = commandActions
        coordinator.updateDocumentPresentation(
            url: documentURL,
            isEdited: hasUnappliedChanges
        )
        coordinator.updateApplicationPresentation(url: applicationURL)
        coordinator.saveDraft = saveDraft
        coordinator.didClose = didClose
        coordinator.attach(to: nsView.window)
        if let window = nsView.window {
            LoupeMachineCommandRouter.shared.register(commandActions, for: window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? DocumentWindowAttachmentView)?.didMoveToWindowHandler = nil
        coordinator.removeQuitEventMonitor()
        coordinator.removeApplicationAccessory()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        var previousDelegate: NSWindowDelegate?
        var hasUnappliedChanges = false
        var documentURL: URL?
        var applicationURL: URL?
        var commandActions = LoupeMachineCommandActions(canSave: false, save: {}, saveAs: {})
        var saveDraft: ((@escaping (Bool) -> Void) -> Void)?
        var didClose: (() -> Void)?
        private var closeApproved = false
        private var isPrompting = false
        private var quitEventMonitor: Any?
        private var applicationAccessory: NSTitlebarAccessoryViewController?
        private var displayedApplicationURL: URL?
        private var isApplicationPresentationCurrent = false

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            previousDelegate = window.delegate
            window.delegate = self
            installQuitEventMonitor()
            LoupeMachineCommandRouter.shared.register(commandActions, for: window)
            updateDocumentPresentation(url: documentURL, isEdited: hasUnappliedChanges)
            updateApplicationPresentation(url: applicationURL)
        }

        func updateDocumentPresentation(url: URL?, isEdited: Bool) {
            documentURL = url
            guard let window else { return }
            window.representedURL = url
            window.title = url.map {
                L10n.f("%@ — Loupe Machine", $0.lastPathComponent)
            } ?? L10n.t("Untitled — Loupe Machine")
            window.isDocumentEdited = isEdited
        }

        func updateApplicationPresentation(url: URL?) {
            applicationURL = url
            guard let window else { return }

            if isApplicationPresentationCurrent,
               displayedApplicationURL == url,
               url == nil || window.titlebarAccessoryViewControllers.contains(where: {
                   $0 === applicationAccessory
               }) {
                return
            }

            removeApplicationAccessory()
            for index in window.titlebarAccessoryViewControllers.indices.reversed()
            where window.titlebarAccessoryViewControllers[index].view.identifier
                == LoupeWindowCloseCoordinator.applicationAccessoryIdentifier {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            displayedApplicationURL = url
            guard let url else {
                isApplicationPresentationCurrent = true
                return
            }

            let name = url.deletingPathExtension().lastPathComponent
            let label = NSTextField(labelWithString: name)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1

            let imageView = NSImageView()
            imageView.image = NSWorkspace.shared.icon(forFile: url.path)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.setFrameSize(NSSize(width: 24, height: 24))
            imageView.setContentHuggingPriority(.required, for: .horizontal)

            let stack = NSStackView(views: [label, imageView])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 7
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.setAccessibilityLabel(L10n.f("Imported application: %@", name))
            stack.toolTip = url.lastPathComponent

            let labelWidth = min(max(label.intrinsicContentSize.width, 40), 220)
            let container = NSView(frame: NSRect(
                origin: .zero,
                size: NSSize(width: labelWidth + 49, height: 38)
            ))
            container.identifier = LoupeWindowCloseCoordinator.applicationAccessoryIdentifier
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                label.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24),
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])

            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .right
            accessory.view = container
            accessory.view.frame.size = container.frame.size
            window.addTitlebarAccessoryViewController(accessory)
            applicationAccessory = accessory
            isApplicationPresentationCurrent = true
        }

        func removeApplicationAccessory() {
            guard let window, let applicationAccessory else { return }
            if let index = window.titlebarAccessoryViewControllers.firstIndex(of: applicationAccessory) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            self.applicationAccessory = nil
        }

        private func installQuitEventMonitor() {
            guard quitEventMonitor == nil else { return }
            quitEventMonitor = DocumentUnsavedChangesPrompt.installQuitMonitor(
                hasUnsavedChanges: { [weak self] in self?.hasUnappliedChanges == true },
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
                messageText: L10n.t("Save changes to this Loupe Machine document?"),
                informativeText: L10n.t("Your unapplied drafted value changes will be lost if you don’t save them."),
                setPrompting: { [weak self] value in self?.isPrompting = value },
                saveDraft: saveDraft,
                onDiscardOrSave: onDiscardOrSave
            )
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if closeApproved { return true }
            guard hasUnappliedChanges else {
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
            if let window { LoupeMachineCommandRouter.shared.unregister(window) }
            removeQuitEventMonitor()
            didClose?()
            closeApproved = false
            previousDelegate?.windowWillClose?(notification)
        }

        func windowDidBecomeKey(_ notification: Notification) {
            if let window { LoupeMachineCommandRouter.shared.activate(window) }
            previousDelegate?.windowDidBecomeKey?(notification)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || previousDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            previousDelegate?.responds(to: aSelector) == true ? previousDelegate : super.forwardingTarget(for: aSelector)
        }
    }
}

#Preview {
    LoupeMachineView(request: LoupeMachineWindowRequest(action: .create))
}

#endif
