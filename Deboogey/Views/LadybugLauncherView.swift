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
    
    var bundleID: String? = Bundle.main.bundleIdentifier
    var onRun: (_ action: String, _ domain: String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Group {
                if Bundle.main.url(forResource: "DEBOOGEY_EDUCATION_LADYBUG", withExtension: "mov") != nil {
                    EducationPlayerView(name: "DEBOOGEY_EDUCATION_LADYBUG", fileExtension: "mov")
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "ladybug")
                                    .font(.system(size: 40, weight: .regular))
                                    .foregroundStyle(.secondary)
                                Text("Ladybug Interface")
                                    .foregroundStyle(.secondary)
                            }
                        )
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .clipped()
                }
            }

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
                    Picker("Domain", selection: $domain) {
                        Text(Domain.global.title).tag(Domain.global)
                        if bundleID != nil {
                            Text(Domain.deboogey.title).tag(Domain.deboogey)
                        }
                        Text(Domain.custom.title).tag(Domain.custom)
                    }
                    .labelsHidden()
                    .onChange(of: domain) { newValue in
                        withAnimation { _ = newValue.isCustom }
                        if newValue == .deboogey { autoKill = false }
                    }
                    .onAppear {
                        if domain == .deboogey { autoKill = false }
                    }

                    if domain.isCustom {
                        TextField(text: $customBundle) { }
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(.secondary)
                    }

                    if domain == .deboogey {
                        Text("Deboogey automatically quits.")
                            .foregroundStyle(.tertiary)
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
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(8)
            .disabled(isRunning)
            .navigationTitle("Ladybug Interface")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") { runHelper() }
                        .disabled(isRunning || (domain == .custom && customBundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }

    private var footerHint: some View {
        Group {
            if domain != .deboogey, autoKill == false {
                Text("Quit the domain to see changes.")
                    .foregroundStyle(.tertiary)
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
                    dismiss()

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
    NavigationStack {
        LadybugLauncherView(onRun: { _, _ in })
    }
}
