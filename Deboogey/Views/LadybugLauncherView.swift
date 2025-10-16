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
                        Text("This App (\(id))").tag(id)
                    }
                    Text("Custom…").tag("__custom__")
                }
                .onChange(of: selectedDomain) { newValue in
                    withAnimation {
                        showingCustomField = (newValue == "__custom__")
                    }
                }

                if showingCustomField {
                    TextField("com.example.myapp", text: $customBundle)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .navigationTitle("Ladybug Interface")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Run") {
                    let action = isEnabled ? "enable" : "disable"
                    let domain = selectedDomain == "__custom__" ? customBundle : selectedDomain
                    onRun(action, domain)
                    dismiss()
                }
                .disabled(selectedDomain == "__custom__" && customBundle.isEmpty)
            }
        }
        .padding()
    }
}
