//
//  ConfigurationView.swift
//  Deboogey
//
//  Created by Théo De Roy on 26/10/2025.
//

import SwiftUI
import Combine

private struct ConfigurationPanelView: View {
    @Environment(\.sipEnabled) private var sipEnabled
    @Binding var pesterMeWithSipping: Bool

    var body: some View {
        Form {
            Section("Miscellaneous") {
                Toggle(isOn: $pesterMeWithSipping) {
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

enum Panel: String, CaseIterable, Identifiable, Hashable, Codable {
    case settings = "Settings"

    var id: String { rawValue }
    var title: String { rawValue }
    var systemImage: String {
        switch self {
        case .settings: return "gear"
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
}

private struct PanelList: View {
    @Binding var selection: Panel?

    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: Panel.settings) {
                Label(Panel.settings.title, systemImage: Panel.settings.systemImage)
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
                ConfigurationPanelView(pesterMeWithSipping: $vm.pesterMeWithSipping)
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

                                Divider()
                                    .frame(height: 18)

                                Button(action: vm.goForward) {
                                    Image(systemName: "chevron.right")
                                }
                                .help("Go Forward")
                                .disabled(!vm.canGoForward)
                            }
                        }
                    }
                    .onChange(of: vm.selection) { oldValue, newValue in
                        vm.onSelectionChanged(oldValue: oldValue, newValue: newValue)
                    }
            }
        } else {
            TabView {
                PanelDetail(vm: vm)
                    .frame(width: 520)
                .tabItem {
                    Label(Panel.settings.title, systemImage: Panel.settings.systemImage)
                }
            }
        }
    }
}

#Preview {
    ConfigurationRootView()
}
