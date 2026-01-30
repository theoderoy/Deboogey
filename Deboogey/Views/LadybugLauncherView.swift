//
//  LadybugLauncherView.swift
//  Deboogey
//
//  Created by Théo De Roy on 15/10/2025.
//

import SwiftUI

struct LadybugLauncherView: View {
    enum Action: String, CaseIterable, Identifiable {
        case enable, disable
        var id: String { rawValue }
        var title: String { self == .enable ? "Enable" : "Disable" }
        var helperArgument: String { rawValue }
    }

    enum Domain: String, CaseIterable, Identifiable {
        case global, deboogey, custom
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
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 0) {
                    Group {
                        if Bundle.main.url(forResource: "DEBOOGEY_EDUCATION-LADYBUG_h265", withExtension: "mov") != nil {
                            EducationPlayerView(name: "DEBOOGEY_EDUCATION-LADYBUG_h265", fileExtension: "mov")
                        } else {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .overlay(
                                    VStack(spacing: 12) {
                                        Image(systemName: "ladybug").font(.system(size: 48, weight: .thin))
                                        Text("Cocoa Debug Menu").font(.headline)
                                    }.foregroundColor(.secondary)
                                )
                        }
                    }
                    .aspectRatio(16.0/9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Text("Inspect the sandbox of individual programs and adjust parameters.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTION").font(.caption.bold()).foregroundColor(.secondary).padding(.leading, 8)
                        Picker("", selection: $action) {
                            ForEach(Action.allCases) { a in Text(a.title).tag(a) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("TARGET DOMAIN").font(.caption.bold()).foregroundColor(.secondary).padding(.leading, 8)
                        
                        if #available(macOS 12.0, *) {
                            Picker("", selection: $domain) {
                                Text(Domain.global.title).tag(Domain.global)
                                if bundleID != nil { Text(Domain.deboogey.title).tag(Domain.deboogey) }
                                Text(Domain.custom.title).tag(Domain.custom)
                            }
                            .labelsHidden()
                            .onChange(of: domain) { newValue in
                                if newValue == .deboogey { autoKill = false }
                            }
                        } else {
                            HStack {
                                Text("Upgrade to macOS 12 for granular targeting.").font(.footnote).foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: "info.circle").foregroundColor(.secondary)
                            }
                        }

                        if domain.isCustom {
                            TextField("com.example.app", text: $customBundle)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(6)
                        }

                        Divider().opacity(0.5)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(domain == .global ? "Restart System" : "Auto-Quit App").font(.body)
                                Text(domain == .deboogey ? "Required for Deboogey" : "Recommended").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if domain == .deboogey {
                                Text("Enabled").font(.caption.bold()).foregroundColor(.blue)
                            } else {
                                Toggle("", isOn: $autoKill).toggleStyle(.switch).labelsHidden()
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)

                    if let errorMessage {
                        Text(errorMessage).foregroundColor(.red).font(.caption).padding(8)
                    }

                    if domain != .deboogey, !autoKill {
                        Text("Quit the domain manually to see changes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .frame(width: 520, height: 650)
        .disabled(isRunning)
        .navigationTitle("Cocoa Debug Menu")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }.disabled(isRunning)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Run") { runHelper() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || (domain == .custom && customBundle.isEmpty))
            }
        }
        .alert(item: Binding<IdentifiableString?>(
            get: { alertMessage.map { IdentifiableString(value: $0) } },
            set: { _ in alertMessage = nil }
        )) { message in Alert(title: Text(message.value)) }
    }

    private func runHelper() {
        errorMessage = nil
        isRunning = true
        let actionArg = action.helperArgument
        let domainArg: String = {
            switch domain {
            case .global: return "global"
            case .deboogey: return bundleID ?? ""
            case .custom: return customBundle.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }()
        var arguments = [actionArg, domainArg]
        if autoKill && domainArg != "global" { arguments.append("--autokill") }

        Task.detached {
            do {
                _ = try ladybugLauncher.runLadybugHelper(arguments: arguments)
                await MainActor.run {
                    onRun(actionArg, domainArg)
                    isRunning = false
                    presentationMode.wrappedValue.dismiss()
                    if domainArg == "global" && autoKill {
                        Task.detached {
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                            process.arguments = ["-e", "tell application \"System Events\" to restart"]
                            try? process.run()
                        }
                    }
                    if let bundleID, domainArg == bundleID { NSApplication.shared.terminate(nil) }
                }
            } catch {
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
        NavigationStack { LadybugLauncherView(onRun: { _, _ in }) }
    } else {
        NavigationView { LadybugLauncherView(onRun: { _, _ in }) }
    }
}
