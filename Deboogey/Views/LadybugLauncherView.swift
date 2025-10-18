//
//  LadybugLauncherView.swift
//  Deboogey
//
//  Created by Théo De Roy on 15/10/2025.
//

import SwiftUI

struct LadybugLauncherView: View {
    @State private var isEnabled = true
    @State private var selectedDomain = "global"
    @State private var customBundle = ""
    @State private var showingCustomField = false
    @State private var autoKill = false
    @State private var isRunning = false
    @Environment(\.dismiss) private var dismiss

    var bundleID: String? = Bundle.main.bundleIdentifier
    var onRun: (_ action: String, _ domain: String) -> Void

    var body: some View {
        Form {
            Section() {
                Picker("Action", selection: $isEnabled) {
                    Text("Enable").tag(true)
                    Text("Disable").tag(false)
                }
                .pickerStyle(.segmented)
            }

            Section() {
                Picker("Domain", selection: $selectedDomain) {
                    Text("Global").tag("global")
                    if let id = bundleID {
                        Text("Deboogey").tag(id)
                    }
                    Text("Custom…").tag("__custom__")
                }
                .onChange(of: selectedDomain) { newValue in
                    withAnimation {
                        showingCustomField = (newValue == "__custom__")
                    }
                    if newValue == bundleID {
                        autoKill = false
                    }
                }
                .onAppear {
                    if selectedDomain == bundleID {
                        autoKill = false
                    }
                }

                if showingCustomField {
                    TextField("com.example.myapp", text: $customBundle)
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(.secondary)
                }
                
                if selectedDomain == bundleID {
                    Text("Deboogey automatically quits.")
                        .foregroundStyle(.tertiary)
                } else {
                    Toggle(selectedDomain == "global" ? "Restart" : "Auto-Quit", isOn: $autoKill)
                        .toggleStyle(.switch)
                        .disabled(selectedDomain == bundleID)
                    if autoKill == false {
                        Text("Quit the domain to see changes.")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .disabled(isRunning)
        .navigationTitle("Ladybug Interface")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Run") {
                    isRunning = true
                    let action = isEnabled ? "enable" : "disable"
                    let domain = selectedDomain == "__custom__" ? customBundle : selectedDomain
                    var arguments = [action, domain]
                    if autoKill && domain != "global" { arguments.append("--autokill") }

                    Task.detached {
                        do {
                            let output = try ladybugLauncher.runLadybugHelper(arguments: arguments)
                            #if DEBUG
                            print("\(output)")
                            #endif
                            await MainActor.run {
                                onRun(action, domain)
                                isRunning = false
                                dismiss()
                                if domain == "global" {
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
                                if let bundleID, domain == bundleID {
                                    NSApplication.shared.terminate(nil)
                                }
                            }
                        } catch {
                            print("Failed to run helper with arguments \(arguments): \(error)")
                            await MainActor.run {
                                isRunning = false
                            }
                        }
                    }
                }
                .disabled(isRunning || (selectedDomain == "__custom__" && customBundle.isEmpty))
            }
        }
        .padding()
    }
}
