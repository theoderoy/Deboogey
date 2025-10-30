//
//  ws_overlayLauncherView.swift
//  Deboogey
//
//  Created by Théo De Roy on 25/10/2025.
//

import SwiftUI

struct ws_overlayLauncherView: View {
    enum Preset: String, CaseIterable, Identifiable {
        case all
        case contributor
        case mouse
        case foreground
        case hang
        case custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .contributor: return "Contributor"
            case .mouse: return "Mouse"
            case .foreground: return "Foreground"
            case .hang: return "Hang"
            case .custom: return "Custom…"
            }
        }

        var helperArgument: String? {
            switch self {
            case .all: return "all"
            case .contributor: return "contributor"
            case .mouse: return "mouse"
            case .foreground: return "foreground"
            case .hang: return "hang"
            case .custom: return nil
            }
        }

        var description: String {
            switch self {
            case .all: return "Enable all overlays (0b1111)."
            case .contributor: return "Enable contributor screen (0b1000)."
            case .mouse: return "Enable foreground tracking (0b0100)."
            case .foreground: return "Enable foreground debugger (0b0010)."
            case .hang: return "Enable framerate & hang sensors (0b0001)."
            case .custom: return "Provide a custom mask in binary (0b...) or decimal."
            }
        }
    }

    @State private var preset: Preset = .all
    @State private var customMask: String = ""
    @State private var isRunning: Bool = false
    @State private var errorMessage: String? = nil

    var onRun: (_ argument: String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Group {
                if Bundle.main.url(forResource: "DEBOOGEY_EDUCATION-WS_OVERLAY_h265", withExtension: "mov") != nil {
                    EducationPlayerView(name: "DEBOOGEY_EDUCATION-WS_OVERLAY_h265", fileExtension: "mov")
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .frame(minWidth: 480, minHeight: 270)
                        .clipped()
                        .padding(4)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 40, weight: .regular))
                                    .foregroundStyle(.secondary)
                                Text("WindowServer Diagnostics")
                                    .foregroundStyle(.secondary)
                            }
                        )
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .frame(minWidth: 480, minHeight: 270)
                        .clipped()
                }
            }
            
            Text("Look inside WindowServer and view all kinds of diagnostic information, such as macOS' refresh rate & application bounding boxes.")
                .foregroundStyle(.tertiary)
                .padding()

            Form {
                Section {
                    Picker("Preset", selection: $preset) {
                        ForEach(Preset.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section(footer: Text(preset.description).foregroundStyle(.tertiary)) {
                    if preset == .custom {
                        TextField(text: $customMask) { }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
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
            .navigationTitle("WindowServer Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") { runHelper() }
                        .disabled(isRunning || (preset == .custom && customMask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }

    private func runHelper() {
        errorMessage = nil
        isRunning = true

        let argument: String
        if let presetArg = preset.helperArgument {
            argument = presetArg
        } else {
            argument = customMask.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Task.detached {
            do {
                let output = try ws_overlayLauncher.runOverlayHelper(arguments: [argument])
                #if DEBUG
                print("[ws_overlay] output: \(output)")
                #endif
                await MainActor.run {
                    onRun(argument)
                    isRunning = false
                    dismiss()
                }
            } catch {
                #if DEBUG
                print("[ws_overlay] failed: \(error)")
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
        ws_overlayLauncherView()
    }
}
