//
//  ConfigurationView.swift
//  Deboogey
//
//  Created by Théo De Roy on 26/10/2025.
//

import Combine
import SwiftUI

extension View {
    @ViewBuilder
    func formStyleGroupedCompat() -> some View {
        if #available(macOS 13.0, *) {
            self.formStyle(.grouped)
        } else {
            self.padding()
        }
    }
}

private struct SettingsPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @Environment(\.sipEnabled) private var sipEnabled
    @State private var showResetAlert = false

    var body: some View {
        Form {
            if #available(macOS 12.0, *) {
                Section(header: Text("Settings")) {
                    Toggle(isOn: $vm.pesterMeWithSipping) {
                        Text("System Integrity Protection Notices")
                        if sipEnabled {
                            Text(
                                "Show a notice when utilities are blocked by System Integrity Protection."
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        } else {
                            Text(
                                "These notices will not be shown until System Integrity Protection is enabled."
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!sipEnabled)
                }
            }
            Section(header: Text("Maintenance")) {
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
        .padding()
        .formStyleGroupedCompat()
        .alert(isPresented: $showResetAlert) {
            Alert(
                title: Text("Delete Persistent Storage?"),
                message: Text("This will clear all preferences and then quit the app."),
                primaryButton: .destructive(Text("Delete")) {
                    vm.theThirdImpact()
                },
                secondaryButton: .cancel()
            )
        }
    }
}

private struct AcknowledgementsPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @State private var showResetAlert = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section(header: Text("Sources")) {
                VStack(alignment: .leading, spacing: 8) {
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
            }
            Section(header: Text("Special Thanks")) {
                VStack(alignment: .leading, spacing: 8) {
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
                            Image(systemName: "screwdriver.fill").foregroundColor(.green)
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
                            Image(systemName: "screwdriver.fill").foregroundColor(.green)
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
                            Image(systemName: "screwdriver.fill").foregroundColor(.green)
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
                            Image(systemName: "screwdriver.fill").foregroundColor(.green)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

enum Panel: String, CaseIterable, Identifiable, Hashable, Codable {
    case settings = "Settings"
    case acknowledge = "Acknowledgements"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .settings:
            if #available(macOS 13.0, *) {
                return "Settings"
            } else {
                return "Preferences"
            }
        case .acknowledge:
            return "Acknowledgements"
        }
    }
    var systemImage: String {
        switch self {
        case .settings: return "gear"
        case .acknowledge:
            if #available(macOS 13.0, *) {
                return "star.square.on.square"
            } else {
                return "star.fill"
            }
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

    private let vars: PersistentVariables

    init(initialSelection: Panel? = .settings, vars: PersistentVariables = PersistentVariables()) {
        self.vars = vars
        self.selection = initialSelection
        self.pesterMeWithSipping = vars.pesterMeWithSipping
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
                NavigationLink(value: Panel.settings) {
                    Label(Panel.settings.title, systemImage: Panel.settings.systemImage)
                }
                NavigationLink(value: Panel.acknowledge) {
                    Label(Panel.acknowledge.title, systemImage: Panel.acknowledge.systemImage)
                }
            }
        } else {
            List {
                Button(action: { selection = .settings }) {
                    Label(Panel.settings.title, systemImage: Panel.settings.systemImage)
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
            case .settings:
                SettingsPanelView(vm: vm)
            case .acknowledge:
                AcknowledgementsPanelView(vm: vm)
            case .none:
                Text("Select a panel")
            }
        }
        .navigationTitle(vm.selection?.title ?? "Settings")
    }
}

struct ConfigurationRootView: View {
    @Environment(\.sipEnabled) private var sipEnabled
    @StateObject private var vm = ConfigurationViewModel()

    var body: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView {
                PanelList(selection: $vm.selection)
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(200)
            } detail: {
                PanelDetail(vm: vm)
                    .frame(width: 520)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            HStack {
                                Button(action: vm.goBack) {
                                    Image(systemName: "chevron.left")
                                }
                                .help("Go Back")
                                .disabled(!vm.canGoBack)
                                .padding(.leading, 3)

                                if #available(macOS 26.0, *) {
                                    Divider()
                                        .frame(height: 18)
                                }

                                Button(action: vm.goForward) {
                                    Image(systemName: "chevron.right")
                                }
                                .help("Go Forward")
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
            TabView {
                SettingsPanelView(vm: vm)
                    .tabItem {
                        Label(Panel.settings.title, systemImage: Panel.settings.systemImage)
                    }

                AcknowledgementsPanelView(vm: vm)
                    .tabItem {
                        Label(Panel.acknowledge.title, systemImage: Panel.acknowledge.systemImage)
                    }
            }
            .frame(width: 520, height: 400)
        }
    }
}

#Preview {
    ConfigurationRootView()
}
