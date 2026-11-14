//
//  DiffsplitterBatchComposer.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 09/11/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct DiffsplitterBatchComposer: View {
    @Environment(\.dismiss) private var dismiss

    @State private var leftPick: ScopedPick?
    @State private var rightPick: ScopedPick?
    @State private var leftTargeted = false
    @State private var rightTargeted = false
    @State private var ignoreWhitespace = false
    @State private var openOnCreation = true
#if os(iOS)
    @State private var pickingSide: Side?
    @State private var isPicking = false
#endif
    @State private var dropFailure: String?

    private var batchIssue: String? {
        guard let leftPick, let rightPick else { return nil }
        do {
            let kind = try DiffsplitterEngine.resolveComparisonKind(left: leftPick.url, right: rightPick.url)
            guard kind == .directories else {
                return L10n.t("A Diffsplitter Batch compares two folders or archives.")
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canCreate: Bool {
        leftPick != nil && rightPick != nil && batchIssue == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
#if os(macOS)
                    titleHeader
#endif
                    VStack(spacing: 16) {
                        sourcesSection
                        optionsSection
                        if let message = dropFailure ?? batchIssue {
                            Text(message)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            HelperToolSheetFooter(
                runTitle: "Create Batch…",
                isRunning: false,
                runDisabled: !canCreate,
                onCancel: { dismiss() },
                onRun: createBatch
            )
        }
        .navigationTitle(L10n.t("Batch Composer"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleHeader
            }
        }
#endif
        .onDisappear(perform: releaseUnusedAccess)
#if os(macOS)
        .frame(
            width: AppWindowSizing.batchComposer.defaultSize.width,
            height: AppWindowSizing.batchComposer.defaultSize.height
        )
#endif
#if os(iOS)
        .fileImporter(
            isPresented: $isPicking,
            allowedContentTypes: [.folder, .item],
            allowsMultipleSelection: false
        ) { result in
            let side = pickingSide
            pickingSide = nil
            switch result {
            case .success(let urls):
                guard let side, let url = urls.first else { return }
                do {
                    assign(try DeboogeyDocumentLifecycle.prepareSideItem(url), to: side)
                } catch {
                    dropFailure = error.localizedDescription
                }
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                    return
                }
                dropFailure = error.localizedDescription
            }
        }
#endif
    }

    private var titleHeader: some View {
        HStack(spacing: 10) {
            Image("DiffsplitterIconIPOSF")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: titleMarkSize, height: titleMarkSize)
            Text(L10n.t("Batch Composer"))
                .font(titleMarkFont)
                .lineLimit(1)
        }
#if os(macOS)
        .frame(maxWidth: .infinity)
#endif
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(L10n.t("Batch Composer"))
    }

    private var titleMarkSize: CGFloat {
#if os(iOS)
        20
#else
        28
#endif
    }

    private var titleMarkFont: Font {
#if os(iOS)
        .headline
#else
        .title2.weight(.semibold)
#endif
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("SOURCES"))
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 8)

            sideRow(title: L10n.t("Left"), pick: leftPick, isTargeted: leftTargeted, side: .left)
            sideRow(title: L10n.t("Right"), pick: rightPick, isTargeted: rightTargeted, side: .right)

            Divider().opacity(0.5)

            Button {
                let left = leftPick
                leftPick = rightPick
                rightPick = left
                dropFailure = nil
            } label: {
                Label(L10n.t("Swap Sides"), systemImage: "arrow.left.arrow.right")
            }
            .disabled(leftPick == nil && rightPick == nil)
        }
        .helperToolSectionThing()
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("OPTIONS"))
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 8)

            optionToggle(
                title: L10n.t("Ignore Whitespace"),
                subtitle: L10n.t("Treat whitespace-only differences as identical"),
                isOn: $ignoreWhitespace
            )

            Divider().opacity(0.5)

            optionToggle(
                title: L10n.t("Open on Creation"),
                subtitle: L10n.t("Open the batch after it is created"),
                isOn: $openOnCreation
            )
        }
        .helperToolSectionThing()
    }

    private func optionToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue(isOn.wrappedValue ? L10n.t("On") : L10n.t("Off"))
                .accessibilityHint(subtitle)
        }
    }

    private func sideRow(title: String, pick: ScopedPick?, isTargeted: Bool, side: Side) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: sideIconName(for: pick))
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                if let pick {
                    Text(pick.url.lastPathComponent)
                        .font(.body)
                        .lineLimit(1)
                    Text(pick.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(L10n.t("Drop a folder or archive here"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if pick != nil {
                Button {
                    clear(side)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .help(L10n.t("Remove"))
                .accessibilityLabel(L10n.t("Remove"))
            }

            Button(L10n.t("Import…")) {
                presentImporter(for: side)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(isTargeted ? 0.12 : 0.05))
        .cornerRadius(6)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onDrop(of: dropTypeIdentifiers, isTargeted: targetedBinding(for: side)) { providers in
            handleDrop(providers, onto: side)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private func sideIconName(for pick: ScopedPick?) -> String {
        guard let pick else { return "folder.badge.plus" }
        return ((try? DiffsplitterEngine.sideKind(at: pick.url)) == .directory) ? "folder" : "doc.text"
    }

    private func createBatch() {
        guard let leftPick, let rightPick, canCreate else { return }
        DiffsplitterBatchCreation.shared.beginFromComposer(
            left: leftPick.url,
            right: rightPick.url,
            ignoreWhitespace: ignoreWhitespace,
            openOnCreation: openOnCreation
        )
    }

    private func presentImporter(for side: Side) {
#if os(macOS)
        let title = side == .left ? L10n.t("Choose Left Item") : L10n.t("Choose Right Item")
        DiffsplitterFileAccess.chooseSideItem(title: title) { url in
            guard let url else { return }
            assign(url, to: side)
        }
#else
        pickingSide = side
        isPicking = true
#endif
    }

    private func assign(_ url: URL, to side: Side) {
        clear(side)
        let accessing = url.startAccessingSecurityScopedResource()
        let pick = ScopedPick(url: url, accessing: accessing)
        switch side {
        case .left: leftPick = pick
        case .right: rightPick = pick
        }
        dropFailure = nil
    }

    private func clear(_ side: Side) {
        switch side {
        case .left:
            release(leftPick)
            leftPick = nil
        case .right:
            release(rightPick)
            rightPick = nil
        }
    }

    private func releaseUnusedAccess() {
        release(leftPick)
        release(rightPick)
        leftPick = nil
        rightPick = nil
    }

    private func release(_ pick: ScopedPick?) {
        guard let pick, pick.accessing else { return }
        pick.url.stopAccessingSecurityScopedResource()
    }

    private func targetedBinding(for side: Side) -> Binding<Bool> {
        switch side {
        case .left: return $leftTargeted
        case .right: return $rightTargeted
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], onto side: Side) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url {
                        assign(url, to: side)
                    } else {
                        dropFailure = L10n.t("The dropped item could not be opened.")
                    }
                }
            }
            return true
        }
        guard let representationType = [UTType.folder.identifier, UTType.item.identifier]
            .first(where: provider.hasItemConformingToTypeIdentifier)
        else { return false }
        provider.loadFileRepresentation(forTypeIdentifier: representationType) { url, error in
            if let error {
                DispatchQueue.main.async { dropFailure = error.localizedDescription }
                return
            }
            guard let url else {
                DispatchQueue.main.async {
                    dropFailure = L10n.t("The dropped item could not be opened.")
                }
                return
            }
            do {
                let durableURL = try DeboogeyDocumentLifecycle.durableCopy(of: url)
                DispatchQueue.main.async { assign(durableURL, to: side) }
            } catch {
                DispatchQueue.main.async { dropFailure = error.localizedDescription }
            }
        }
        return true
    }

    private var dropTypeIdentifiers: [String] {
#if os(macOS)
        [UTType.fileURL.identifier]
#else
        [UTType.item.identifier, UTType.folder.identifier, UTType.fileURL.identifier]
#endif
    }
}

private extension DiffsplitterBatchComposer {
    enum Side {
        case left
        case right
    }

    struct ScopedPick {
        let url: URL
        let accessing: Bool
    }
}

#if DEBUG
#Preview("Batch Composer") {
    if #available(macOS 13.0, *) {
        NavigationStack { DiffsplitterBatchComposer() }
    } else {
        NavigationView { DiffsplitterBatchComposer() }
    }
}
#endif
