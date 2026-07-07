//
//  DeboogeySDLauncherView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 25/10/2025.
//

import SwiftUI

struct DeboogeySDLauncherView: View {
    enum Preset: String, CaseIterable, Identifiable {
        case all, contributor, mouse, foreground, hang, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return L10n.t("All")
            case .contributor: return L10n.t("Contributor")
            case .mouse: return L10n.t("Mouse")
            case .foreground: return L10n.t("Foreground")
            case .hang: return L10n.t("Hang")
            case .custom: return L10n.t("Custom…")
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
            case .all: return L10n.t("Enable all overlays (0b1111).")
            case .contributor: return L10n.t("Enable contributor screen (0b1000).")
            case .mouse: return L10n.t("Enable foreground tracking (0b0100).")
            case .foreground: return L10n.t("Enable foreground debugger (0b0010).")
            case .hang: return L10n.t("Enable framerate & hang sensors (0b0001).")
            case .custom: return L10n.t("Provide a custom mask in binary (0b...) or decimal.")
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .contributor: return "person.crop.rectangle"
            case .mouse: return "cursorarrow.motionlines"
            case .foreground: return "macwindow"
            case .hang: return "speedometer"
            case .custom: return "slider.horizontal.3"
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
        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 0) {
                    Group {
                        if EducationPlayerView.hasAsset(named: "DEBOOGEY_EDUCATION-DEBOOGEYSD_h265") {
                            EducationPlayerView(assetName: "DEBOOGEY_EDUCATION-DEBOOGEYSD_h265")
                        } else {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .overlay(
                                    VStack(spacing: 12) {
                                        Image(systemName: "macwindow").font(.system(size: 48, weight: .thin))
                                        Text(L10n.t("SkyLight Diagnostics")).font(.headline)
                                    }.foregroundColor(.secondary)
                                )
                        }
                    }
                    .aspectRatio(16.0/9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Text(L10n.t("Take a look at the system's internal diagnostics, such as the refresh rate, collision boxes, screen activity and more."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.t("PRESET"))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)

                        TabView(selection: $preset) {
                            ForEach(Preset.allCases, id: \.id) { tabPreset in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(tabPreset.description)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)

                                    if tabPreset == .custom {
                                        TextField("0x...", text: $customMask)
                                            .textFieldStyle(.plain)
                                            .font(.system(.body, design: .monospaced))
                                            .padding(8)
                                            .background(Color.secondary.opacity(0.05))
                                            .cornerRadius(6)
                                    }
                                }
                                .tabItem {
                                    Label(tabPreset.title, systemImage: tabPreset.systemImage)
                                }
                                .tag(tabPreset)
                            }
                            .padding(12)
                        }
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
        .disabled(isRunning)
        Divider()
        HStack {
            Button(L10n.t("Cancel")) { presentationMode.wrappedValue.dismiss() }
                .disabled(isRunning)
            Spacer()
            Button(L10n.t("Run")) { runHelper() }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || (preset == .custom && customMask.isEmpty))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        }
        .frame(width: 520, height: 540)
        .navigationTitle(L10n.t("SkyLight Diagnostics"))
    }

    private func runHelper() {
        errorMessage = nil
        isRunning = true
        let argument = preset.helperArgument ?? customMask.trimmingCharacters(in: .whitespacesAndNewlines)

        Task.detached {
            do {
                _ = try DeboogeySDLauncher.runOverlayHelper(arguments: [argument])
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
        NavigationStack { DeboogeySDLauncherView() }
    } else {
        NavigationView { DeboogeySDLauncherView() }
    }
}

