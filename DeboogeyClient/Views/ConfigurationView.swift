//
//  ConfigurationView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 26/10/2025.
//

import SwiftUI
import Combine

private struct LegacyGroupedSection<Content: View>: View {
    let header: String
    let content: Content
    
    init(header: String, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(header))
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
}

private struct GeneralPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
#if !DEBOOGEY_MCE
    @Environment(\.sipSatisfied) private var sipSatisfied
#endif
    @State private var showResetAlert = false
    
    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                Form {
                    panels
                }
                .formStyle(.grouped)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        panels
                    }
                    .padding(.vertical)
                }
            }
        }
        .alert(isPresented: $showResetAlert) {
            Alert(
                title: Text(L10n.t("Delete Persistent Storage?")),
                message: Text(L10n.t("This will clear all preferences and then quit the app.")),
                primaryButton: .destructive(Text(L10n.t("Delete"))) {
                    vm.theThirdImpact()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    @ViewBuilder
    private var panels: some View {
        section(header: "Sounds") {
            Toggle(isOn: $vm.playIndexingDoneSound) {
                Text(L10n.t("Play a sound when indexing finishes"))
            }
            Text(L10n.t("Play a sound after an application is completely indexed."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Toggle(isOn: $vm.playToolCycleSound) {
#if DEBOOGEY_MCE
                Text(L10n.t("Play sounds when Cocoa Debug Menu finishes or fails"))
#else
                Text(L10n.t("Play sounds when Apple System Tools finish or fail"))
#endif
            }
#if DEBOOGEY_MCE
            Text(L10n.t("Play sounds when Cocoa Debug Menu completes successfully or halts due to an error."))
                .font(.subheadline)
                .foregroundColor(.secondary)
#else
            Text(L10n.t("Play sounds when Apple System Tools complete successfully or halt due to an error."))
                .font(.subheadline)
                .foregroundColor(.secondary)
#endif

            Toggle(isOn: $vm.playDiffsplitterDoneSound) {
                Text(L10n.t("Play a sound when Diffsplitter finishes a comparison"))
            }
            Text(L10n.t("Notify with a sound and banner when a Diffsplitter comparison takes at least the selected duration."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if vm.playDiffsplitterDoneSound {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("Minimum Duration"))
                        Spacer()
                        Text(
                            DiffsplitterCompletionFeedback.durationLabel(
                                for: vm.diffsplitterNotifyMinimumSeconds
                            )
                        )
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        diffsplitterSliderResetButton(
                            isDefault: Int(vm.diffsplitterNotifyMinimumSeconds.rounded())
                                == Int(DiffsplitterCompletionFeedback.defaultMinimumSeconds.rounded())
                        ) {
                            vm.diffsplitterNotifyMinimumSeconds =
                                DiffsplitterCompletionFeedback.defaultMinimumSeconds
                        }
                        Slider(
                            value: Binding(
                                get: {
                                    DiffsplitterCompletionFeedback.sliderIndex(
                                        forSeconds: vm.diffsplitterNotifyMinimumSeconds
                                    )
                                },
                                set: {
                                    vm.diffsplitterNotifyMinimumSeconds =
                                        DiffsplitterCompletionFeedback.seconds(forSliderIndex: $0)
                                }
                            ),
                            in: DiffsplitterCompletionFeedback.sliderIndexRange,
                            step: 1
                        )
                    }
                }
            }
        }

        section(header: "Diffsplitter") {
            Picker(
                L10n.t("Offload Large Dumps to Temporary Storage"),
                selection: $vm.diffsplitterPreferDiskTempForLargeFiles
            ) {
                Text(L10n.t("Session Disk Space")).tag(true)
                Text(L10n.t("Memory (RAM)")).tag(false)
            }
            Text(L10n.t("Choose where Diffsplitter stores large dumps while you inspect them. Storing on disk demands less horsepower, while memory (RAM) can be faster on powerful machines."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        
        section() {
            Toggle(isOn: $vm.diffsplitterIncludeHiddenFiles) {
                Text(L10n.t("Include Hidden Files"))
            }
            Text(L10n.t("When off, Diffsplitter skips hidden files while walking folders."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }

        section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("Hex Dump Window"))
                    Spacer()
                    Text(L10n.f("%d lines", Int(vm.diffsplitterHexWindowLines.rounded())))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    diffsplitterSliderResetButton(
                        isDefault: Int(vm.diffsplitterHexWindowLines.rounded())
                            == DiffsplitterSettings.defaultHexWindowLines
                    ) {
                        vm.diffsplitterHexWindowLines = Double(DiffsplitterSettings.defaultHexWindowLines)
                    }
                    Slider(
                        value: $vm.diffsplitterHexWindowLines,
                        in: Double(DiffsplitterSettings.hexWindowLinesRange.lowerBound)
                            ... Double(DiffsplitterSettings.hexWindowLinesRange.upperBound)
                    )
                }
            }
            Text(L10n.t("How many hex lines stay in memory for the visible dump window."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("Binary Size Threshold"))
                    Spacer()
                    Text(L10n.f("%d MB", Int(vm.diffsplitterMaxTextMegabytes.rounded())))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    diffsplitterSliderResetButton(
                        isDefault: Int(vm.diffsplitterMaxTextMegabytes.rounded())
                            == DiffsplitterSettings.defaultMaxTextMegabytes
                    ) {
                        vm.diffsplitterMaxTextMegabytes = Double(DiffsplitterSettings.defaultMaxTextMegabytes)
                    }
                    Slider(
                        value: $vm.diffsplitterMaxTextMegabytes,
                        in: Double(DiffsplitterSettings.maxTextMegabytesRange.lowerBound)
                            ... Double(DiffsplitterSettings.maxTextMegabytesRange.upperBound)
                    )
                }
            }
            Text(L10n.t("Files larger than this are treated as binary instead of text."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("Archive Nest Depth"))
                    Spacer()
                    Text(L10n.f("%d levels", Int(vm.diffsplitterMaxNestDepth.rounded())))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    diffsplitterSliderResetButton(
                        isDefault: Int(vm.diffsplitterMaxNestDepth.rounded())
                            == DiffsplitterSettings.defaultMaxNestDepth
                    ) {
                        vm.diffsplitterMaxNestDepth = Double(DiffsplitterSettings.defaultMaxNestDepth)
                    }
                    Slider(
                        value: $vm.diffsplitterMaxNestDepth,
                        in: Double(DiffsplitterSettings.maxNestDepthRange.lowerBound)
                            ... Double(DiffsplitterSettings.maxNestDepthRange.upperBound),
                        step: 1
                    )
                }
            }
            Text(L10n.t("Maximum nested archive depth Diffsplitter will expand."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("Archive Entry Limit"))
                    Spacer()
                    Text(L10n.f("%d entries", Int(vm.diffsplitterMaxEntries.rounded())))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    diffsplitterSliderResetButton(
                        isDefault: Int(vm.diffsplitterMaxEntries.rounded())
                            == DiffsplitterSettings.defaultMaxEntries
                    ) {
                        vm.diffsplitterMaxEntries = Double(DiffsplitterSettings.defaultMaxEntries)
                    }
                    Slider(
                        value: Binding(
                            get: {
                                Double(
                                    DiffsplitterSettings.maxEntriesStopIndex(
                                        for: Int(vm.diffsplitterMaxEntries.rounded())
                                    )
                                )
                            },
                            set: { index in
                                vm.diffsplitterMaxEntries = Double(
                                    DiffsplitterSettings.maxEntriesStop(atIndex: Int(index.rounded()))
                                )
                            }
                        ),
                        in: DiffsplitterSettings.maxEntriesStopIndexRange,
                        step: 1
                    )
                }
            }
            Text(L10n.t("Maximum files Diffsplitter will index from folders and archives."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }

        section {
            Text(L10n.t("Folder Status Dot Priority"))
            Text(L10n.t("Drag to reorder. Items nearer the top win when a folder contains mixed changes."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            List {
                ForEach(Array(vm.diffsplitterStatusPriority.enumerated()), id: \.element) { index, raw in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Circle()
                            .fill(diffsplitterStatusColor(raw))
                            .frame(width: 10, height: 10)
                        Text(diffsplitterStatusTitle(raw))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(diffsplitterStatusTitle(raw))
                    .accessibilityValue(L10n.f("Priority %d", index + 1))
                }
                .onMove(perform: vm.moveDiffsplitterStatusPriority)
            }
            .frame(height: CGFloat(vm.diffsplitterStatusPriority.count) * 28)
            .listStyle(.bordered)
            .modifier(DiffsplitterPriorityListScrollModifier())

            Button(L10n.t("Reset to Default")) {
                vm.resetDiffsplitterStatusPriority()
            }
            .disabled(vm.diffsplitterStatusPriority == PersistentVariables.defaultDiffsplitterStatusPriority)
        }
        
#if !DEBOOGEY_MCE
        section(header: "Notices") {
            Toggle(isOn: $vm.pesterMeWithSipping) {
                Text("System Integrity Protection")
            }
            .disabled(!sipSatisfied)
            if sipSatisfied {
                Text(
                    "Show a notice when utilities require security adjustments."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            } else {
                Text(
                    "These notices will not be shown until System Integrity Protection is adjusted."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Toggle(isOn: $vm.showNetworkNotices) {
                Text("Network Connection")
            }
            Text(
                "Show a notice when network connection is required for upgrades."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            Toggle(isOn: $vm.showCLTNotices) {
                Text("Command Line Tools for Xcode")
            }
            Text(
                "Show a notice when a feature requires Command Line Tools for Xcode to be installed."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            Toggle(isOn: $vm.showLoupeApplyVerification) {
                Text(L10n.t("Verify Loupe Machine Changes"))
            }
            Text(L10n.t("Ask for confirmation before Loupe Machine applies changes to an application."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        
        section(header: "Upgrades") {
            Picker("Upgrade Channel", selection: $vm.upgradeChannel) {
                Text("Release").tag("Release")
                Text("Internal").tag("Internal")
            }
            if vm.upgradeChannel == "Internal" {
                Text("Internal builds contain experimental features and are not notarised by Apple.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Toggle("Hide Automatic Notices", isOn: $vm.hideUpgradeAlerts)
            Toggle("Delete Backup on Startup", isOn: $vm.deleteBackupOnStartup)
        }
#endif

        section(header: "Maintenance") {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { showResetAlert = true }) {
                    Label("Delete Persistent Storage", systemImage: "trash")
                }
                Text("Clears all preferences and then quits the app.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func section<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 13.0, *) {
            if let header = header {
                Section(header: Text(L10n.t(header))) {
                    content()
                }
            } else {
                Section {
                    content()
                }
            }
        } else {
            if let header = header {
                LegacyGroupedSection(header: header) {
                    content()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
    }

    private func diffsplitterSliderResetButton(
        isDefault: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .disabled(isDefault)
        .help(L10n.t("Reset to Default"))
        .accessibilityLabel(L10n.t("Reset to Default"))
    }

    private func diffsplitterStatusTitle(_ raw: String) -> String {
        switch DiffsplitterEngine.DirEntryStatus(rawValue: raw) {
        case .added: return L10n.t("Added")
        case .removed: return L10n.t("Removed")
        case .modified: return L10n.t("Modified")
        case .binary: return L10n.t("Binary")
        case .identical, .none: return raw
        }
    }

    private func diffsplitterStatusColor(_ raw: String) -> Color {
        switch DiffsplitterEngine.DirEntryStatus(rawValue: raw) {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        case .binary: return .purple
        case .identical, .none: return .secondary
        }
    }
}

private struct DiffsplitterPriorityListScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollDisabled(true)
        } else {
            content
        }
    }
}

private struct EntityTrackerPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @AppStorage("theoderoy.Deboogey.EntityTracker.rowScale") private var rowScale: Double = 1.0
    @State private var displayScale: Double = {
        let stored = UserDefaults.standard.double(forKey: "theoderoy.Deboogey.EntityTracker.rowScale")
        return stored.isZero ? 1.0 : stored
    }()
    @AppStorage("theoderoy.Deboogey.EntityTracker.scaleTarget") private var scaleTarget: String = "both"
    
    private var preferenceBanner: some View {
        Image("EntityTrackerConfUnit")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .cornerRadius(10)
    }
    
    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                Form {
                    Section {
                        preferenceBanner
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    panels
                }
                .formStyle(.grouped)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        preferenceBanner
                            .padding(.horizontal)

                        VStack(spacing: 20) {
                            panels
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var panels: some View {
        section(header: "Entity Tracker") {
            Toggle("Auto-Delete", isOn: $vm.entityTrackerAutoDeleteEnabled)
            if vm.entityTrackerAutoDeleteEnabled {
                Picker("Trigger", selection: $vm.entityTrackerAutoDeleteTrigger) {
                    Text("On Login").tag("login")
                    Text("On Deboogey Launch").tag("launch")
                }
#if !DEBOOGEY_MCE
                Picker("Scope", selection: $vm.entityTrackerAutoDeleteScope) {
                    Text("Ephemerals Only").tag("ephemerals")
                    Text("All Entries").tag("all")
                }
#endif
                if DebugVariables.isMarketplaceCandidateEditionBuild
                    || vm.entityTrackerAutoDeleteScope == "all" {
                    Picker("File, compare, and indexing entries", selection: $vm.entityTrackerAutoDeleteLoupeActivities) {
                        Text("Remove these entries").tag(true)
                        Text("Leave these entries out").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                }
                Text(descriptionForAutoDelete)
                    .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        
        section {
            Picker("Display Scale", selection: $scaleTarget) {
                Text("Icon").tag("icon")
                Text("Text").tag("text")
                Text("Both").tag("both")
            }
            
            HStack {
                Text("Scale Size")
                Spacer()
                Text("\(Int((displayScale * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Stepper("", value: Binding(
                    get: { rowScale },
                    set: { newValue in
                        rowScale = newValue
                        displayScale = newValue
                    }
                ), in: 0.70...1.50, step: 0.05)
                    .labelsHidden()
            }
        }
    }
    
    private var descriptionForAutoDelete: String {
        let what = !DebugVariables.isMarketplaceCandidateEditionBuild
            && vm.entityTrackerAutoDeleteScope == "ephemerals"
            ? L10n.t(
                DebugVariables.isMarketplaceCandidateEditionBuild
                    ? "Removes ephemeral entries from the log"
                    : "Removes ephemeral entries (e.g. SkyLight Diagnostics) from the log"
            )
            : L10n.t(
                vm.entityTrackerAutoDeleteLoupeActivities
                    ? "Clears the entire Entity Tracker log"
                    : "Clears the Entity Tracker log except file, compare, and indexing entries"
            )
        let when = vm.entityTrackerAutoDeleteTrigger == "login"
            ? L10n.t("once per login session.")
            : L10n.t("on every app launch.")
        return "\(what) \(when)"
    }
    
    @ViewBuilder
    private func section<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 13.0, *) {
            if let header = header {
                Section(header: Text(L10n.t(header))) {
                    content()
                }
            } else {
                Section {
                    content()
                }
            }
        } else {
            if let header = header {
                LegacyGroupedSection(header: header) {
                    content()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
    }
}

private struct AcknowledgementsPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @State private var showResetAlert = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                Form {
                    panels
                }
                .formStyle(.grouped)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        panels
                    }
                    .padding(.vertical)
                }
            }
        }
    }
    
    @ViewBuilder
    private var panels: some View {
#if !DEBOOGEY_MCE
        section(header: "Sources") {
            Button(action: {
                openURL(
                    URL(
                        string:
                            "https://mjtsai.com/blog/2024/03/22/_eventfirstresponderchaindescription/"
                    )!)
            }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cocoa Debug Menu").font(.headline)
                        Text("Sourced Article").font(.subheadline).foregroundColor(
                            .secondary)
                    }
                } icon: {
                    Image(systemName: "link").foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: {
                openURL(
                    URL(
                        string:
                            "https://x.com/khanhduytran0/status/1951637277760999628?s=61")!)
            }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("enable_overlay").font(.headline)
                        Text("Sourced Article").font(.subheadline).foregroundColor(
                            .secondary)
                    }
                } icon: {
                    Image(systemName: "link").foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)
        }
#endif
        
        section(header: "Special Thanks") {
            Button(action: { openURL(URL(string: "https://github.com/ogui-775")!) }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Salty").font(.headline)
                        Text("Insight").font(.subheadline).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "star.fill").foregroundColor(.yellow)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: { openURL(URL(string: "https://github.com/1davi")!) }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1davi").font(.headline)
                        Text("Tester").font(.subheadline).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "gearshape").foregroundColor(.green)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: { openURL(URL(string: "https://github.com/aspauldingcode")!) }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alex Spaulding").font(.headline)
                        Text("Tester").font(.subheadline).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "gearshape").foregroundColor(.green)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: { openURL(URL(string: "https://github.com/MTACS")!) }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MTACS").font(.headline)
                        Text("Tester").font(.subheadline).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "gearshape").foregroundColor(.green)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: { openURL(URL(string: "https://github.com/oliviaiacovou")!) }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Olivia Iacovou").font(.headline)
                        Text("Tester").font(.subheadline).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "gearshape").foregroundColor(.green)
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func section<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 13.0, *) {
            if let header = header {
                Section(header: Text(L10n.t(header))) {
                    content()
                }
            } else {
                Section {
                    content()
                }
            }
        } else {
            if let header = header {
                LegacyGroupedSection(header: header) {
                    content()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
    }
}

enum Panel: CaseIterable, Identifiable, Hashable, Codable {
    case general
    case entityTracker
    case acknowledge
    
    var id: String {
        switch self {
        case .general: return "general"
        case .entityTracker: return "entityTracker"
        case .acknowledge: return "acknowledge"
        }
    }
    var title: String {
        switch self {
        case .general:
            return L10n.t("General")
        case .entityTracker:
            return L10n.t("Entity Tracker")
        case .acknowledge:
            return L10n.t("Acknowledgements")
        }
    }
    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .entityTracker: return "binoculars"
        case .acknowledge: return "star"
        }
    }
}

final class ConfigurationViewModel: ObservableObject {
    @Published var selection: Panel?
    @Published private(set) var backStack: [Panel] = []
    @Published private(set) var forwardStack: [Panel] = []
    private var isJumpingViaHistory = false
    
    @Published var pesterMeWithSipping: Bool {
        didSet { vars.pesterMeWithSipping = pesterMeWithSipping }
    }
    
    @Published var showNetworkNotices: Bool {
        didSet { vars.showNetworkNotices = showNetworkNotices }
    }

    @Published var showCLTNotices: Bool {
        didSet { vars.showCLTNotices = showCLTNotices }
    }

    @Published var showLoupeApplyVerification: Bool {
        didSet { vars.showLoupeApplyVerification = showLoupeApplyVerification }
    }
    
    @Published var upgradeChannel: String {
        didSet { vars.upgradeChannel = upgradeChannel }
    }
    
    @Published var hideUpgradeAlerts: Bool {
        didSet { vars.hideUpgradeAlerts = hideUpgradeAlerts }
    }
    
    @Published var deleteBackupOnStartup: Bool {
        didSet { vars.deleteBackupOnStartup = deleteBackupOnStartup }
    }

    @Published var entityTrackerAutoDeleteEnabled: Bool {
        didSet { vars.entityTrackerAutoDeleteEnabled = entityTrackerAutoDeleteEnabled }
    }

    @Published var entityTrackerAutoDeleteScope: String {
        didSet { vars.entityTrackerAutoDeleteScope = entityTrackerAutoDeleteScope }
    }

    @Published var entityTrackerAutoDeleteTrigger: String {
        didSet { vars.entityTrackerAutoDeleteTrigger = entityTrackerAutoDeleteTrigger }
    }

    @Published var entityTrackerAutoDeleteLoupeActivities: Bool {
        didSet { vars.entityTrackerAutoDeleteLoupeActivities = entityTrackerAutoDeleteLoupeActivities }
    }

    @Published var playIndexingDoneSound: Bool {
        didSet { vars.playIndexingDoneSound = playIndexingDoneSound }
    }

    @Published var playToolCycleSound: Bool {
        didSet { vars.playToolCycleSound = playToolCycleSound }
    }

    @Published var playDiffsplitterDoneSound: Bool {
        didSet { vars.playDiffsplitterDoneSound = playDiffsplitterDoneSound }
    }

    @Published var diffsplitterNotifyMinimumSeconds: Double {
        didSet { vars.diffsplitterNotifyMinimumSeconds = diffsplitterNotifyMinimumSeconds }
    }

    @Published var diffsplitterStatusPriority: [String] {
        didSet { vars.diffsplitterStatusPriority = diffsplitterStatusPriority }
    }

    @Published var diffsplitterIncludeHiddenFiles: Bool {
        didSet { vars.diffsplitterIncludeHiddenFiles = diffsplitterIncludeHiddenFiles }
    }

    @Published var diffsplitterPreferDiskTempForLargeFiles: Bool {
        didSet { vars.diffsplitterPreferDiskTempForLargeFiles = diffsplitterPreferDiskTempForLargeFiles }
    }

    @Published var diffsplitterHexWindowLines: Double {
        didSet { vars.diffsplitterHexWindowLines = diffsplitterHexWindowLines }
    }

    @Published var diffsplitterMaxTextMegabytes: Double {
        didSet { vars.diffsplitterMaxTextMegabytes = diffsplitterMaxTextMegabytes }
    }

    @Published var diffsplitterMaxNestDepth: Double {
        didSet { vars.diffsplitterMaxNestDepth = diffsplitterMaxNestDepth }
    }

    @Published var diffsplitterMaxEntries: Double {
        didSet { vars.diffsplitterMaxEntries = diffsplitterMaxEntries }
    }

    private let vars: PersistentVariables
    
    init(initialSelection: Panel? = .general, vars: PersistentVariables = PersistentVariables()) {
        self.vars = vars
        self.selection = initialSelection
        self.pesterMeWithSipping = vars.pesterMeWithSipping
        self.showNetworkNotices = vars.showNetworkNotices
        self.showCLTNotices = vars.showCLTNotices
        self.showLoupeApplyVerification = vars.showLoupeApplyVerification
        self.upgradeChannel = vars.upgradeChannel
        self.hideUpgradeAlerts = vars.hideUpgradeAlerts
        self.deleteBackupOnStartup = vars.deleteBackupOnStartup
        self.entityTrackerAutoDeleteEnabled = vars.entityTrackerAutoDeleteEnabled
        self.entityTrackerAutoDeleteScope = vars.entityTrackerAutoDeleteScope
        self.entityTrackerAutoDeleteTrigger = vars.entityTrackerAutoDeleteTrigger
        self.entityTrackerAutoDeleteLoupeActivities = vars.entityTrackerAutoDeleteLoupeActivities
        self.playIndexingDoneSound = vars.playIndexingDoneSound
        self.playToolCycleSound = vars.playToolCycleSound
        self.playDiffsplitterDoneSound = vars.playDiffsplitterDoneSound
        self.diffsplitterNotifyMinimumSeconds = vars.diffsplitterNotifyMinimumSeconds
        self.diffsplitterStatusPriority = vars.diffsplitterStatusPriority
        self.diffsplitterIncludeHiddenFiles = vars.diffsplitterIncludeHiddenFiles
        self.diffsplitterPreferDiskTempForLargeFiles = vars.diffsplitterPreferDiskTempForLargeFiles
        self.diffsplitterHexWindowLines = vars.diffsplitterHexWindowLines
        self.diffsplitterMaxTextMegabytes = vars.diffsplitterMaxTextMegabytes
        self.diffsplitterMaxNestDepth = vars.diffsplitterMaxNestDepth
        self.diffsplitterMaxEntries = vars.diffsplitterMaxEntries
    }

    func moveDiffsplitterStatusPriority(from source: IndexSet, to destination: Int) {
        var order = diffsplitterStatusPriority
        order.move(fromOffsets: source, toOffset: destination)
        diffsplitterStatusPriority = order
    }

    func resetDiffsplitterStatusPriority() {
        diffsplitterStatusPriority = PersistentVariables.defaultDiffsplitterStatusPriority
    }
    
    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = selection { forwardStack.append(current) }
        isJumpingViaHistory = true
        selection = previous
    }
    
    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = selection { backStack.append(current) }
        isJumpingViaHistory = true
        selection = next
    }
    
    func onSelectionChanged(oldValue: Panel?, newValue: Panel?) {
        guard !isJumpingViaHistory else {
            isJumpingViaHistory = false
            return
        }
        if let old = oldValue { backStack.append(old) }
        forwardStack.removeAll()
    }
    
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    
    func theThirdImpact() {
        vars.theThirdImpact()
    }
}

private struct PanelList: View {
    @Binding var selection: Panel?
    
    var body: some View {
        if #available(macOS 13.0, *) {
            List(selection: $selection) {
                NavigationLink(value: Panel.general) {
                    Label(Panel.general.title, systemImage: Panel.general.systemImage)
                }
                NavigationLink(value: Panel.entityTracker) {
                    Label(Panel.entityTracker.title, systemImage: Panel.entityTracker.systemImage)
                }
                NavigationLink(value: Panel.acknowledge) {
                    Label(Panel.acknowledge.title, systemImage: Panel.acknowledge.systemImage)
                }
            }
        } else {
            List {
                Button(action: { selection = .general }) {
                    Label(Panel.general.title, systemImage: Panel.general.systemImage)
                }
                .buttonStyle(.plain)
                Button(action: { selection = .entityTracker }) {
                    Label(Panel.entityTracker.title, systemImage: Panel.entityTracker.systemImage)
                }
                .buttonStyle(.plain)
                Button(action: { selection = .acknowledge }) {
                    Label(Panel.acknowledge.title, systemImage: Panel.acknowledge.systemImage)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PanelDetail: View {
    @ObservedObject var vm: ConfigurationViewModel
    
    var body: some View {
        Group {
            switch vm.selection {
            case .general:
                GeneralPanelView(vm: vm)
            case .entityTracker:
                EntityTrackerPanelView(vm: vm)
            case .acknowledge:
                AcknowledgementsPanelView(vm: vm)
            case .none:
                Text(L10n.t("Select a panel"))
            }
        }
        .navigationTitle(vm.selection?.title ?? L10n.t("Configuration"))
    }
}

struct ConfigurationRootView: View {
    @StateObject private var vm = ConfigurationViewModel()
    
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernNavigationView(vm: vm)
                .minimumWindowContentSize(AppWindowSizing.Configuration.modern)
        } else {
            TabView {
                GeneralPanelView(vm: vm)
                    .tabItem {
                        Label(Panel.general.title, systemImage: Panel.general.systemImage)
                    }
                
                EntityTrackerPanelView(vm: vm)
                    .tabItem {
                        Label(Panel.entityTracker.title, systemImage: Panel.entityTracker.systemImage)
                    }
                
                AcknowledgementsPanelView(vm: vm)
                    .tabItem {
                        Label(Panel.acknowledge.title, systemImage: Panel.acknowledge.systemImage)
                    }
            }
            .minimumWindowContentSize(AppWindowSizing.Configuration.legacy)
        }
    }
}

@available(macOS 13.0, *)
private struct ModernNavigationView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                PanelList(selection: $vm.selection)
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(AppWindowSizing.Configuration.sidebarWidth)
            } detail: {
                PanelDetail(vm: vm)
                    .frame(minWidth: AppWindowSizing.Configuration.detailWidth)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            HStack {
                                if columnVisibility == .detailOnly {
                                    Button(action: {
                                        columnVisibility = .all
                                    }) {
                                        Image(systemName: "sidebar.left")
                                    }
                                    .help(L10n.t("Show Sidebar"))
                                    .padding(.leading, 3)
                                    
                                    if #available(macOS 26.0, *) {
                                        Divider()
                                            .frame(height: 18)
                                    }
                                }
                                
                                Button(action: vm.goBack) {
                                    Image(systemName: "chevron.left")
                                }
                                .help(L10n.t("Go Back"))
                                .disabled(!vm.canGoBack)
                                .padding(.leading, columnVisibility == .detailOnly ? 0 : 3)
                                
                                if #available(macOS 26.0, *) {
                                    Divider()
                                        .frame(height: 18)
                                }
                                
                                Button(action: vm.goForward) {
                                    Image(systemName: "chevron.right")
                                }
                                .help(L10n.t("Go Forward"))
                                .disabled(!vm.canGoForward)
                                .padding(.trailing, 3)
                            }
                            .controlSize(.large)
                        }
                    }
                    .onChange(of: vm.selection) { oldValue, newValue in
                        vm.onSelectionChanged(oldValue: oldValue, newValue: newValue)
                    }
            }
        } else {
            NavigationSplitView {
                PanelList(selection: $vm.selection)
                    .navigationSplitViewColumnWidth(AppWindowSizing.Configuration.sidebarWidth)
            } detail: {
                PanelDetail(vm: vm)
                    .frame(minWidth: AppWindowSizing.Configuration.detailWidth)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            HStack {
                                Button(action: vm.goBack) {
                                    Image(systemName: "chevron.left")
                                }
                                .help(L10n.t("Go Back"))
                                .disabled(!vm.canGoBack)
                                .padding(.leading, 3)
                                
                                Button(action: vm.goForward) {
                                    Image(systemName: "chevron.right")
                                }
                                .help(L10n.t("Go Forward"))
                                .disabled(!vm.canGoForward)
                                .padding(.trailing, 3)
                            }
                            .controlSize(.large)
                        }
                    }
                    .onChange(of: vm.selection) { newValue in
                        vm.onSelectionChanged(oldValue: nil, newValue: newValue)
                    }
            }
        }
    }
}

#Preview {
    ConfigurationRootView()
}
