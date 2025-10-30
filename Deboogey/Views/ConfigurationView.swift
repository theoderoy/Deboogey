//
//  ConfigurationView.swift
//  Deboogey
//
//  Created by Théo De Roy on 26/10/2025.
//

import SwiftUI
import Combine

private struct SettingsPanelView: View {
    @Environment(\.sipEnabled) private var sipEnabled
    @ObservedObject var vm: ConfigurationViewModel

    var body: some View {
        Form {
            Section("Miscellaneous") {
                Toggle(isOn: $vm.pesterMeWithSipping) {
                    Text("System Integrity Protection Notices")
                    if sipEnabled {
                        Text("Show a notice when utilities are blocked by System Integrity Protection.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("These notices will not be shown until System Integrity Protection is enabled.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!sipEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedPanelView: View {
    @ObservedObject var vm: ConfigurationViewModel
    @State private var showResetAlert = false

    var body: some View {
        Form {
            Section("Maintenance") {
                Button("Delete Persistent Storage", systemImage: "trash") {
                    showResetAlert = true
                }
                Text("Clears all preferences and then quits the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Delete Persistent Storage?", isPresented: $showResetAlert) {
            Button("Delete", role: .destructive) {
                vm.theThirdImpact()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all preferences and then quit the app.")
        }
    }
}

enum Panel: String, CaseIterable, Identifiable, Hashable, Codable {
    case settings = "Settings"
    case advanced = "Advanced"

    var id: String { rawValue }
    var title: String { rawValue }
    var systemImage: String {
        switch self {
        case .settings: return "gear"
        case .advanced: return "wrench.and.screwdriver"
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
        List(selection: $selection) {
            NavigationLink(value: Panel.settings) {
                Label(Panel.settings.title, systemImage: Panel.settings.systemImage)
            }
            NavigationLink(value: Panel.advanced) {
                Label(Panel.advanced.title, systemImage: Panel.advanced.systemImage)
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
            case .advanced:
                AdvancedPanelView(vm: vm)
            case .none:
                Text("Select a panel")
            }
        }
        .navigationTitle(vm.selection?.title ?? "Settings")
    }
}

struct ConfigurationRootView: View {
    @Environment(\.sipEnabled) private var sipEnabled
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    @StateObject private var vm = ConfigurationViewModel()

    var body: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView() {
                PanelList(selection: $vm.selection)
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(180)
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
                    .frame(width: 520)
                    .tabItem {
                        Label(Panel.settings.title, systemImage: Panel.settings.systemImage)
                    }

                AdvancedPanelView(vm: vm)
                    .frame(width: 520)
                    .tabItem {
                        Label(Panel.advanced.title, systemImage: Panel.advanced.systemImage)
                    }
            }
        }
    }
}

#Preview {
    ConfigurationRootView()
}
