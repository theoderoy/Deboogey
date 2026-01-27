//
//  ws_overlayLauncherView.swift
//  Deboogey
//
//  Created by Théo De Roy on 25/10/2025.
//

import SwiftUI

@available(macOS 12.0, *)
struct ws_overlayLauncherView: View {
    enum Preset: String, CaseIterable, Identifiable {
        case all, contributor, mouse, foreground, hang, custom
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
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 0) {
                    Group {
                        if Bundle.main.url(forResource: "DEBOOGEY_EDUCATION-WS_OVERLAY_h265", withExtension: "mov") != nil {
                            EducationPlayerView(name: "DEBOOGEY_EDUCATION-WS_OVERLAY_h265", fileExtension: "mov")
                        } else {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .overlay(
                                    VStack(spacing: 12) {
                                        Image(systemName: "macwindow").font(.system(size: 48, weight: .thin))
                                        Text("WindowServer Diagnostics").font(.headline)
                                    }.foregroundColor(.secondary)
                                )
                        }
                    }
                    .aspectRatio(16.0/9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Text("Look inside WindowServer and view all kinds of diagnostic information, such as macOS' refresh rate & application bounding boxes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRESET").font(.caption.bold()).foregroundColor(.secondary).padding(.leading, 8)
                        
                        Picker("", selection: $preset) {
                            ForEach(Preset.allCases) { p in Text(p.title).tag(p) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if preset == .custom {
                            TextField("0x...", text: $customMask)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(6)
                        }

                        Divider().opacity(0.5)

                        Text(preset.description)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)

                    if let errorMessage {
                        Text(errorMessage).foregroundColor(.red).font(.caption).padding(8)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .frame(width: 520, height: 540)
        .disabled(isRunning)
        .navigationTitle("WindowServer Diagnostics")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }.disabled(isRunning)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Run") { runHelper() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || (preset == .custom && customMask.isEmpty))
            }
        }
    }

    private func runHelper() {
        errorMessage = nil
        isRunning = true
        let argument = preset.helperArgument ?? customMask.trimmingCharacters(in: .whitespacesAndNewlines)

        Task.detached {
            do {
                _ = try ws_overlayLauncher.runOverlayHelper(arguments: [argument])
                await MainActor.run {
                    onRun(argument)
                    isRunning = false
                    presentationMode.wrappedValue.dismiss()
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
        NavigationStack { ws_overlayLauncherView() }
    } else {
        if #available(macOS 12.0, *) {
            NavigationView { ws_overlayLauncherView() }
        }
    }
}
