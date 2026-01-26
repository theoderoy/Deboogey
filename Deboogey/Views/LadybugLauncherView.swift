//
//  LadybugLauncherView.swift
//  Deboogey
//
//  Created by Théo De Roy on 15/10/2025.
//

import SwiftUI

struct LadybugLauncherView: View {
    enum Action: String, CaseIterable, Identifiable {
        case enable
        case disable
        var id: String { rawValue }
        var title: String {
            switch self {
            case .enable: return "Enable"
            case .disable: return "Disable"
            }
        }
        var helperArgument: String { rawValue }
    }

    enum Domain: String, CaseIterable, Identifiable {
        case global
        case deboogey
        case custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .global: return "Global"
            case .deboogey: return "Deboogey"
            case .custom: return "Custom…"
            }
        }
        var isCustom: Bool { self == .custom }
    }

    @State private var action: Action = .enable
    @State private var domain: Domain = .global
    @State private var customBundle = ""
    @State private var autoKill = false
    @State private var isRunning = false
    @State private var errorMessage: String? = nil
    @State private var alertMessage: String? = nil

    var bundleID: String? = Bundle.main.bundleIdentifier
    var onRun: (_ action: String, _ domain: String) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack {
            Group {
                if Bundle.main.url(forResource: "DEBOOGEY_EDUCATION-LADYBUG_h265", withExtension: "mov") != nil {
                    EducationPlayerView(name: "DEBOOGEY_EDUCATION-LADYBUG_h265", fileExtension: "mov")
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .frame(minWidth: 480, minHeight: 270)
                        .clipped()
                        .padding(4)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "ladybug")
                                    .font(.system(size: 40, weight: .regular))
                                    .foregroundColor(.secondary)
                                Text("Ladybug Interface")
                                    .foregroundColor(.secondary)
                            }
                        )
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .frame(minWidth: 480, minHeight: 270)
                        .clipped()
                }
            }

            Text("Crack open sandboxes & view or change hidden parameters.")
                .foregroundColor(.secondary)
                .padding()

            Form {
                Section {
                    Picker("Action", selection: $action) {
                        ForEach(Action.allCases) { a in
                            Text(a.title).tag(a)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Section(footer: footerHint) {
                    if #available(macOS 12.0, *) {
                        Picker("Domain", selection: $domain) {
                            Text(Domain.global.title).tag(Domain.global)
                            if #available(macOS 12.0, *) {
                                if bundleID != nil {
                                    Text(Domain.deboogey.title).tag(Domain.deboogey)
                                }
                                Text(Domain.custom.title).tag(Domain.custom)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: domain) { newValue in
                            withAnimation { _ = newValue.isCustom }
                            if newValue == .deboogey { autoKill = false }
                        }
                        .onAppear {
                            if domain == .deboogey { autoKill = false }
                        }
                    } else {
                        HStack {
                            Text("Target Selection")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                alertMessage = "Targeting individual apps requires macOS 12.0 (Monterey) or later."
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if domain.isCustom {
                        TextField("", text: $customBundle)
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor(.secondary)
                    }

                    if domain == .deboogey {
                        Text("Deboogey automatically quits.")
                            .foregroundColor(.secondary)
                    } else {
                        Toggle(isOn: $autoKill) {
                            Text(domain == .global ? "Restart" : "Auto-Quit")
                        }
                        .toggleStyle(.switch)
                        .disabled(domain == .deboogey)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(8)
            .disabled(isRunning)
            .navigationTitle("Ladybug Interface")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") { runHelper() }
                        .disabled(isRunning || (domain == .custom && customBundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
        .alert(item: Binding<IdentifiableString?>(
            get: { alertMessage.map { IdentifiableString(value: $0) } },
            set: { _ in alertMessage = nil }
        )) { message in
            Alert(title: Text(message.value))
        }
    }

    private var footerHint: some View {
        Group {
            if domain != .deboogey, autoKill == false {
                Text("Quit the domain to see changes.")
                    .foregroundColor(.secondary)
            } else {
                EmptyView()
            }
        }
    }

    private func runHelper() {
        errorMessage = nil
        isRunning = true

        let actionArg = action.helperArgument
        let domainArg: String = {
            switch domain {
            case .global:
                return "global"
            case .deboogey:
                return bundleID ?? ""
            case .custom:
                return customBundle.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }()

        var arguments = [actionArg, domainArg]
        if autoKill && domainArg != "global" { arguments.append("--autokill") }

        Task.detached {
            do {
                let output = try ladybugLauncher.runLadybugHelper(arguments: arguments)
                #if DEBUG
                print("[ladybug] output: \(output)")
                #endif
                await MainActor.run {
                    onRun(actionArg, domainArg)
                    isRunning = false
                    presentationMode.wrappedValue.dismiss()

                    if domainArg == "global" {
                        if autoKill {
                            Task.detached {
                                let script = "tell application \"System Events\" to restart"
                                let process = Process()
                                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                                process.arguments = ["-e", script]
                                do { try process.run() } catch { /* ignore failures */ }
                            }
                        }
                    }
                    if let bundleID, domainArg == bundleID {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } catch {
                #if DEBUG
                print("[ladybug] failed: \(error)")
                #endif
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    isRunning = false
                }
            }
        }
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        NavigationStack {
            LadybugLauncherView(onRun: { _, _ in })
        }
    } else {
        NavigationView {
            LadybugLauncherView(onRun: { _, _ in })
        }
    }
}
