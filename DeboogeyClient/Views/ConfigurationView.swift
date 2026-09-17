//
//  ConfigurationView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 26/10/2025.
//

import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if os(iOS)
private var configurationShowsDiffsplitter: Bool {
    MCEIOSFeatureSupport.diffsplitter
}
#else
private var configurationShowsDiffsplitter: Bool { true }
#endif

private var platformGroupedBackground: Color {
#if canImport(AppKit)
    Color(NSColor.controlBackgroundColor)
#elseif canImport(UIKit)
    Color(.secondarySystemBackground)
#else
    Color.secondary.opacity(0.12)
#endif
}

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
            .background(platformGroupedBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
}

@ViewBuilder
private func configurationSection<Content: View>(
    header: String? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
    if #available(macOS 13.0, *) {
        if let header {
            Section(header: Text(L10n.t(header))) {
                content()
            }
        } else {
            Section {
                content()
            }
        }
    } else if let header {
        LegacyGroupedSection(header: header) {
            content()
        }
    } else {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(platformGroupedBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

private struct ConfigurationPanelContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if #available(iOS 16.0, macOS 13.0, *) {
                Form {
                    content()
                }
#if os(macOS)
                .formStyle(.grouped)
#endif
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        content()
                    }
                    .padding(.vertical)
                }
            }
        }
    }
}

private struct ConfigurationPreferenceBannerPanel<Content: View>: View {
    let imageName: String
    @ViewBuilder let content: () -> Content

    private var banner: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .cornerRadius(10)
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, macOS 13.0, *) {
                Form {
                    Section { banner }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    content()
                }
#if os(macOS)
                .formStyle(.grouped)
#endif
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        banner.padding(.horizontal)
                        VStack(spacing: 20) { content() }
                            .padding(.vertical)
                    }
                }
            }
        }
    }
}

@ViewBuilder
private func configurationSecondaryCaption(_ text: String) -> some View {
    Text(text)
        .font(.subheadline)
        .foregroundColor(.secondary)
}

private enum ConfigurationMaintenanceAction {
    case resetPreferences
    case deleteStorage

    var title: String {
        switch self {
        case .resetPreferences: return L10n.t("Reset Preference Values?")
        case .deleteStorage: return L10n.t("Delete Persistent Storage?")
        }
    }

    var message: String {
        switch self {
        case .resetPreferences:
            return L10n.t("This will restore settings to their defaults without clearing other stored data, then quit the app.")
        case .deleteStorage:
            return L10n.t("This will clear all preferences and then quit the app.")
        }
    }

    var confirmTitle: String {
        switch self {
        case .resetPreferences: return L10n.t("Reset")
        case .deleteStorage: return L10n.t("Delete")
        }
    }
}

private struct ConfigurationMaintenanceRows: View {
    let onSelect: (ConfigurationMaintenanceAction) -> Void

    var body: some View {
        maintenanceRow(
            title: L10n.t("Reset Preference Values"),
            systemImage: "arrow.counterclockwise",
            detail: L10n.t("Restores settings defaults without clearing other stored data, then quits the app."),
            action: { onSelect(.resetPreferences) }
        )
        maintenanceRow(
            title: L10n.t("Delete Persistent Storage"),
            systemImage: "trash",
            detail: L10n.t("Clears all preferences and then quits the app."),
            action: { onSelect(.deleteStorage) }
        )
    }

    private func maintenanceRow(
        title: String,
        systemImage: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            configurationSecondaryCaption(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func configurationMaintenanceAlert(
        pending: Binding<ConfigurationMaintenanceAction?>,
        onConfirm: @escaping (ConfigurationMaintenanceAction) -> Void
    ) -> some View {
        modifier(ConfigurationMaintenanceAlertModifier(pending: pending, onConfirm: onConfirm))
    }
}

private struct ConfigurationMaintenanceAlertModifier: ViewModifier {
    @Binding var pending: ConfigurationMaintenanceAction?
    let onConfirm: (ConfigurationMaintenanceAction) -> Void

    func body(content: Content) -> some View {
        content.alert(
            pending?.title ?? "",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            presenting: pending
        ) { action in
            Button(action.confirmTitle, role: .destructive) {
                onConfirm(action)
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
    }
}

private struct GeneralPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
#if !DEBOOGEY_MCE
    @Environment(\.sipSatisfied) private var sipSatisfied
#endif
    @State private var pendingMaintenanceAction: ConfigurationMaintenanceAction?

    var body: some View {
        ConfigurationPanelContainer {
            panels
        }
        .configurationMaintenanceAlert(pending: $pendingMaintenanceAction) {
            vm.performMaintenance($0)
        }
    }
    
    @ViewBuilder
    private var panels: some View {
#if os(macOS)
        section(header: "Sounds") {
            Toggle(isOn: $vm.playIndexingDoneSound) {
                Text(L10n.t("Play a sound when indexing finishes"))
            }
            configurationSecondaryCaption(L10n.t("Play a sound after an application is completely indexed."))

            Toggle(isOn: $vm.playToolCycleSound) {
#if DEBOOGEY_MCE
                Text(L10n.t("Play sounds when Cocoa Debug Menu finishes or fails"))
#else
                Text(L10n.t("Play sounds when Apple System Tools finish or fail"))
#endif
            }
#if DEBOOGEY_MCE
            configurationSecondaryCaption(
                L10n.t("Play sounds when Cocoa Debug Menu completes successfully or halts due to an error.")
            )
#else
            configurationSecondaryCaption(
                L10n.t("Play sounds when Apple System Tools complete successfully or halt due to an error.")
            )
#endif

            diffsplitterSoundControls
        }
#else
        if configurationShowsDiffsplitter {
            section(header: "Live Activity") {
                diffsplitterSoundControls
            }
        }
#endif
        
#if !DEBOOGEY_MCE
        section(header: "Notices") {
            Toggle(isOn: $vm.pesterMeWithSipping) {
                Text("System Integrity Protection")
            }
            .disabled(!sipSatisfied)
            if sipSatisfied {
                configurationSecondaryCaption(
                    "Show a notice when utilities require security adjustments."
                )
            } else {
                configurationSecondaryCaption(
                    "These notices will not be shown until System Integrity Protection is adjusted."
                )
            }

            Toggle(isOn: $vm.showNetworkNotices) {
                Text("Network Connection")
            }
            configurationSecondaryCaption(
                "Show a notice when network connection is required for upgrades."
            )

            Toggle(isOn: $vm.showCLTNotices) {
                Text("Command Line Tools for Xcode")
            }
            configurationSecondaryCaption(
                "Show a notice when a feature requires Command Line Tools for Xcode to be installed."
            )

            Toggle(isOn: $vm.showLoupeApplyVerification) {
                Text(L10n.t("Verify Loupe Machine Changes"))
            }
            configurationSecondaryCaption(
                L10n.t("Ask for confirmation before Loupe Machine applies changes to an application.")
            )
        }
        
        if !DebugVariables.areUpdatesDisabled {
            section(header: "Upgrades") {
                Picker("Upgrade Channel", selection: $vm.upgradeChannel) {
                    Text("Release").tag("Release")
                    Text("Internal").tag("Internal")
                }
                if vm.upgradeChannel == "Internal" {
                    configurationSecondaryCaption(
                        "Internal builds contain experimental features and are not notarised by Apple."
                    )
                }

                Toggle("Hide Automatic Notices", isOn: $vm.hideUpgradeAlerts)
                Toggle("Delete Backup on Startup", isOn: $vm.deleteBackupOnStartup)
            }
        }
#endif

        section(header: "Maintenance") {
            ConfigurationMaintenanceRows { pendingMaintenanceAction = $0 }
        }
    }
    
    @ViewBuilder
    private var diffsplitterSoundControls: some View {
#if os(iOS)
        Toggle(isOn: $vm.playDiffsplitterDoneSound) {
            Text(L10n.t("Notify with Live Activity when Diffsplitter finishes"))
        }
        configurationSecondaryCaption(
            L10n.t("Live Activity when available, otherwise a banner. Plays a sound after the selected minimum duration.")
        )
#else
        Toggle(isOn: $vm.playDiffsplitterDoneSound) {
            Text(L10n.t("Play a sound when Diffsplitter finishes a comparison"))
        }
        configurationSecondaryCaption(
            L10n.t("Notify with a sound and banner when a Diffsplitter comparison takes at least the selected duration.")
        )
#endif

        if vm.playDiffsplitterDoneSound {
            DiffsplitterCompletionDurationControls(
                minimumSeconds: $vm.diffsplitterNotifyMinimumSeconds,
                notifyWhenBackgrounded: $vm.diffsplitterNotifyWhenBackgrounded,
                showsResetButton: true
            )
        }
    }

    @ViewBuilder
    private func section<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        configurationSection(header: header, content: content)
    }

}

private struct DiffsplitterPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel

    var body: some View {
        ConfigurationPreferenceBannerPanel(imageName: "DiffsplitterConfUnit") {
            panels
        }
    }

    @ViewBuilder
    private var panels: some View {
        let hexLines = Int(vm.diffsplitterHexWindowLines.rounded())
        let maxTextMB = Int(vm.diffsplitterMaxTextMegabytes.rounded())
        let nestDepth = Int(vm.diffsplitterMaxNestDepth.rounded())
        let maxEntries = Int(vm.diffsplitterMaxEntries.rounded())
        let largeHexEnabled = vm.diffsplitterLargeFileHexConversionEnabled

        section {
            Picker(
                L10n.t("Offload Large Dumps to Temporary Storage"),
                selection: $vm.diffsplitterPreferDiskTempForLargeFiles
            ) {
                Text(L10n.t("Session Disk Space")).tag(true)
                Text(L10n.t("Memory (RAM)")).tag(false)
            }
            configurationSecondaryCaption(
                L10n.t("Choose where Diffsplitter stores large dumps while you inspect them. Storing on disk demands less horsepower, while memory (RAM) can be faster on powerful machines.")
            )
        }

        section {
            Toggle(isOn: $vm.diffsplitterIncludeHiddenFiles) {
                Text(L10n.t("Include Hidden Files"))
            }
            configurationSecondaryCaption(
                L10n.t("When off, Diffsplitter skips hidden files while walking folders.")
            )
        }

        section {
            labeledSlider(
                title: L10n.t("Hex Dump Window"),
                valueLabel: L10n.f("%d lines", hexLines),
                isDefault: hexLines == DiffsplitterSettings.defaultHexWindowLines,
                range: Double(DiffsplitterSettings.hexWindowLinesRange.lowerBound)
                    ... Double(DiffsplitterSettings.hexWindowLinesRange.upperBound),
                value: $vm.diffsplitterHexWindowLines
            ) {
                vm.diffsplitterHexWindowLines = Double(DiffsplitterSettings.defaultHexWindowLines)
            }
            configurationSecondaryCaption(
                L10n.t("How many hex lines stay in memory for the visible dump window.")
            )

            Toggle(isOn: $vm.diffsplitterLargeFileHexConversionEnabled) {
                Text(L10n.t("Large File Hex Conversion"))
            }
            configurationSecondaryCaption(
                L10n.t("When on, oversized files that are not content-detected binaries open as a windowed hex dump instead of text. Binary status is only for recognised binary content and is unaffected.")
            )

            labeledSlider(
                title: L10n.t("Large File Size Threshold"),
                valueLabel: L10n.f("%d MB", maxTextMB),
                isDefault: maxTextMB == DiffsplitterSettings.defaultMaxTextMegabytes,
                range: Double(DiffsplitterSettings.maxTextMegabytesRange.lowerBound)
                    ... Double(DiffsplitterSettings.maxTextMegabytesRange.upperBound),
                value: $vm.diffsplitterMaxTextMegabytes,
                enabled: largeHexEnabled
            ) {
                vm.diffsplitterMaxTextMegabytes = Double(DiffsplitterSettings.defaultMaxTextMegabytes)
            }
            configurationSecondaryCaption(
                L10n.t("Files larger than this use windowed hex conversion when Large File Hex Conversion is on.")
            )
            .opacity(largeHexEnabled ? 1 : 0.45)

            labeledSlider(
                title: L10n.t("Archive Nest Depth"),
                valueLabel: L10n.f("%d levels", nestDepth),
                isDefault: nestDepth == DiffsplitterSettings.defaultMaxNestDepth,
                range: Double(DiffsplitterSettings.maxNestDepthRange.lowerBound)
                    ... Double(DiffsplitterSettings.maxNestDepthRange.upperBound),
                value: $vm.diffsplitterMaxNestDepth,
                step: 1
            ) {
                vm.diffsplitterMaxNestDepth = Double(DiffsplitterSettings.defaultMaxNestDepth)
            }
            configurationSecondaryCaption(
                L10n.t("Maximum nested archive depth Diffsplitter will expand.")
            )

            labeledSlider(
                title: L10n.t("Archive Entry Limit"),
                valueLabel: L10n.f("%d entries", maxEntries),
                isDefault: maxEntries == DiffsplitterSettings.defaultMaxEntries,
                range: DiffsplitterSettings.maxEntriesStopIndexRange,
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
                step: 1
            ) {
                vm.diffsplitterMaxEntries = Double(DiffsplitterSettings.defaultMaxEntries)
            }
            configurationSecondaryCaption(
                L10n.t("Maximum files Diffsplitter will index from folders and archives.")
            )
        }

#if os(macOS)
        section {
            Text(L10n.t("Folder Status Dot Priority"))
            configurationSecondaryCaption(
                L10n.t("Drag to reorder. Items nearer the top win when a folder contains mixed changes.")
            )
            DiffsplitterStatusPriorityEditor(
                order: $vm.diffsplitterStatusPriority,
                onMove: vm.moveDiffsplitterStatusPriority
            )
        }
#endif
    }

    @ViewBuilder
    private func section<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        configurationSection(header: header, content: content)
    }

    private func labeledSlider(
        title: String,
        valueLabel: String,
        isDefault: Bool,
        range: ClosedRange<Double>,
        value: Binding<Double>,
        step: Double? = nil,
        enabled: Bool = true,
        reset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isDefault || !enabled)
                .help(L10n.t("Reset to Default"))
                .accessibilityLabel(L10n.t("Reset to Default"))
                if let step {
                    Slider(value: value, in: range, step: step).disabled(!enabled)
                } else {
                    Slider(value: value, in: range).disabled(!enabled)
                }
            }
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

#if os(macOS)
private struct EntityTrackerPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @AppStorage("theoderoy.Deboogey.EntityTracker.rowScale") private var rowScale: Double = 1.0
    @State private var displayScale: Double = {
        let stored = UserDefaults.standard.double(forKey: "theoderoy.Deboogey.EntityTracker.rowScale")
        return stored.isZero ? 1.0 : stored
    }()
    @AppStorage("theoderoy.Deboogey.EntityTracker.scaleTarget") private var scaleTarget: String = "both"

    var body: some View {
        ConfigurationPreferenceBannerPanel(imageName: "EntityTrackerConfUnit") {
            panels
        }
    }

    @ViewBuilder
    private var panels: some View {
        section {
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
            ? L10n.t("Removes ephemeral entries (e.g. SkyLight Diagnostics) from the log")
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
        configurationSection(header: header, content: content)
    }
}

#endif

private struct AcknowledgementsPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        ConfigurationPanelContainer {
            panels
        }
    }
    
    @ViewBuilder
    private var panels: some View {
#if !DEBOOGEY_MCE
        section(header: "Sources") {
            creditRows([
                (
                    "Cocoa Debug Menu",
                    "Sourced Article",
                    "https://mjtsai.com/blog/2024/03/22/_eventfirstresponderchaindescription/",
                    "link",
                    .blue
                ),
                (
                    "enable_overlay",
                    "Sourced Article",
                    "https://x.com/khanhduytran0/status/1951637277760999628?s=61",
                    "link",
                    .blue
                ),
            ])
        }
#endif
        
        section(header: "Special Thanks") {
            creditRows([
                ("Salty", "Insight", "https://github.com/ogui-775", "star.fill", .yellow),
                ("1davi", "Tester", "https://github.com/1davi", "gearshape", .green),
                ("Alex Spaulding", "Tester", "https://github.com/aspauldingcode", "gearshape", .green),
                ("MTACS", "Tester", "https://github.com/MTACS", "gearshape", .green),
                ("Olivia Iacovou", "Tester", "https://github.com/oliviaiacovou", "gearshape", .green),
            ])
        }
    }

    @ViewBuilder
    private func creditRows(
        _ rows: [(name: String, role: String, url: String, symbol: String, tint: Color)]
    ) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            Button(action: { openURL(URL(string: row.url)!) }) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.headline)
                        Text(row.role).font(.subheadline).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: row.symbol).foregroundColor(row.tint)
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func section<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        configurationSection(header: header, content: content)
    }
}

enum Panel: Identifiable, Hashable, Codable {
    case general
    case about
    case diffsplitter
    case entityTracker
    case acknowledge

    static var allCases: [Panel] {
#if os(iOS)
        if configurationShowsDiffsplitter {
            [.general, .diffsplitter, .about, .acknowledge]
        } else {
            [.about, .acknowledge]
        }
#else
        [.general, .diffsplitter, .entityTracker, .acknowledge]
#endif
    }
    
    var id: String {
        switch self {
        case .general: return "general"
        case .about: return "about"
        case .diffsplitter: return "diffsplitter"
        case .entityTracker: return "entityTracker"
        case .acknowledge: return "acknowledge"
        }
    }
    var title: String {
        switch self {
        case .general:
            return L10n.t("General")
        case .about:
            return L10n.t("About Deboogey")
        case .diffsplitter:
            return L10n.t("Diffsplitter")
        case .entityTracker:
            return L10n.t("Entity Tracker")
        case .acknowledge:
            return L10n.t("Acknowledgements")
        }
    }
    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .about: return "info.circle"
        case .diffsplitter: return "DiffsplitterIconIPOSF"
        case .entityTracker: return "eyeglasses"
        case .acknowledge: return "star"
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .diffsplitter:
            Label {
                Text(title)
            } icon: {
                Image("DiffsplitterIconIPOSF")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
        default:
            Label(title, systemImage: systemImage)
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

    @Published var diffsplitterNotifyWhenBackgrounded: Bool {
        didSet { vars.diffsplitterNotifyWhenBackgrounded = diffsplitterNotifyWhenBackgrounded }
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

    @Published var diffsplitterLargeFileHexConversionEnabled: Bool {
        didSet { vars.diffsplitterLargeFileHexConversionEnabled = diffsplitterLargeFileHexConversionEnabled }
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
    
    init(
        initialSelection: Panel? = {
#if os(iOS)
            .about
#else
            .general
#endif
        }(),
        vars: PersistentVariables = PersistentVariables()
    ) {
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
        self.diffsplitterNotifyWhenBackgrounded = vars.diffsplitterNotifyWhenBackgrounded
        self.diffsplitterNotifyMinimumSeconds = vars.diffsplitterNotifyMinimumSeconds
        self.diffsplitterStatusPriority = vars.diffsplitterStatusPriority
        self.diffsplitterIncludeHiddenFiles = vars.diffsplitterIncludeHiddenFiles
        self.diffsplitterPreferDiskTempForLargeFiles = vars.diffsplitterPreferDiskTempForLargeFiles
        self.diffsplitterHexWindowLines = vars.diffsplitterHexWindowLines
        self.diffsplitterLargeFileHexConversionEnabled = vars.diffsplitterLargeFileHexConversionEnabled
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
    
    func resetPreferenceValues() {
        vars.resetPreferenceValues()
        reloadFromVars()
    }

    fileprivate func performMaintenance(_ action: ConfigurationMaintenanceAction) {
        switch action {
        case .resetPreferences: resetPreferenceValues()
        case .deleteStorage: theThirdImpact()
        }
    }

    private func reloadFromVars() {
        pesterMeWithSipping = vars.pesterMeWithSipping
        showNetworkNotices = vars.showNetworkNotices
        showCLTNotices = vars.showCLTNotices
        showLoupeApplyVerification = vars.showLoupeApplyVerification
        upgradeChannel = vars.upgradeChannel
        hideUpgradeAlerts = vars.hideUpgradeAlerts
        deleteBackupOnStartup = vars.deleteBackupOnStartup
        entityTrackerAutoDeleteEnabled = vars.entityTrackerAutoDeleteEnabled
        entityTrackerAutoDeleteScope = vars.entityTrackerAutoDeleteScope
        entityTrackerAutoDeleteTrigger = vars.entityTrackerAutoDeleteTrigger
        entityTrackerAutoDeleteLoupeActivities = vars.entityTrackerAutoDeleteLoupeActivities
        playIndexingDoneSound = vars.playIndexingDoneSound
        playToolCycleSound = vars.playToolCycleSound
        playDiffsplitterDoneSound = vars.playDiffsplitterDoneSound
        diffsplitterNotifyWhenBackgrounded = vars.diffsplitterNotifyWhenBackgrounded
        diffsplitterNotifyMinimumSeconds = vars.diffsplitterNotifyMinimumSeconds
        diffsplitterStatusPriority = vars.diffsplitterStatusPriority
        diffsplitterIncludeHiddenFiles = vars.diffsplitterIncludeHiddenFiles
        diffsplitterPreferDiskTempForLargeFiles = vars.diffsplitterPreferDiskTempForLargeFiles
        diffsplitterHexWindowLines = vars.diffsplitterHexWindowLines
        diffsplitterLargeFileHexConversionEnabled = vars.diffsplitterLargeFileHexConversionEnabled
        diffsplitterMaxTextMegabytes = vars.diffsplitterMaxTextMegabytes
        diffsplitterMaxNestDepth = vars.diffsplitterMaxNestDepth
        diffsplitterMaxEntries = vars.diffsplitterMaxEntries
    }

    func theThirdImpact() {
        vars.theThirdImpact()
    }
}

private struct PanelList: View {
    @Binding var selection: Panel?
    private let panels: [Panel] = [.general, .diffsplitter, .entityTracker, .acknowledge]

    var body: some View {
        if #available(macOS 13.0, *) {
            List(selection: $selection) {
                ForEach(panels) { panel in
                    NavigationLink(value: panel) { panel.label }
                }
            }
        } else {
            List {
                ForEach(panels) { panel in
                    Button(action: { selection = panel }) {
                        panel.label
                    }
                    .buttonStyle(.plain)
                }
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
            case .about:
                AboutView()
            case .diffsplitter:
                DiffsplitterPanelView(vm: vm)
            case .entityTracker:
#if os(macOS)
                EntityTrackerPanelView(vm: vm)
#else
                EmptyView()
#endif
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
#if os(iOS)
    @State private var pendingMaintenanceAction: ConfigurationMaintenanceAction?
#endif

    var body: some View {
#if os(iOS)
        List {
            Section {
                if configurationShowsDiffsplitter {
                    NavigationLink {
                        GeneralPanelView(vm: vm)
                            .navigationTitle(Panel.general.title)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Panel.general.label
                    }
                    NavigationLink {
                        DiffsplitterPanelView(vm: vm)
                            .navigationTitle(Panel.diffsplitter.title)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Panel.diffsplitter.label
                    }
                }
                NavigationLink {
                    AboutView()
                        .navigationTitle(Panel.about.title)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Panel.about.label
                }
                NavigationLink {
                    AcknowledgementsPanelView(vm: vm)
                        .navigationTitle(Panel.acknowledge.title)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Panel.acknowledge.label
                }
            }
            if !configurationShowsDiffsplitter {
                Section(header: Text(L10n.t("Maintenance"))) {
                    ConfigurationMaintenanceRows { pendingMaintenanceAction = $0 }
                }
            }
        }
        .navigationTitle(L10n.t("Settings"))
        .configurationMaintenanceAlert(pending: $pendingMaintenanceAction) {
            vm.performMaintenance($0)
        }
#else
        if #available(macOS 14.0, *) {
            ModernNavigationView(vm: vm)
                .minimumWindowContentSize(AppWindowSizing.Configuration.modern)
        } else {
            TabView {
                GeneralPanelView(vm: vm)
                    .tabItem {
                        Panel.general.label
                    }

                DiffsplitterPanelView(vm: vm)
                    .tabItem {
                        Panel.diffsplitter.label
                    }
                
                EntityTrackerPanelView(vm: vm)
                    .tabItem {
                        Panel.entityTracker.label
                    }
                
                AcknowledgementsPanelView(vm: vm)
                    .tabItem {
                        Panel.acknowledge.label
                    }
            }
            .minimumWindowContentSize(AppWindowSizing.Configuration.legacy)
        }
#endif
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
