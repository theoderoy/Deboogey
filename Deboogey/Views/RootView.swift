//
//  RootView.swift
//  Deboogey
//
//  Created by Théo De Roy on 13/10/2025.
//

import AppKit
import SwiftUI

let appName =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
let shortVersion =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

struct LauncherButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
            }
            .font(.headline)
            .padding(8)
            .frame(maxWidth: 220)
            .background(color.opacity(0.1))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RootView: View {
    @State private var alertMessage: String? = nil
    @State private var showingLadybugLauncher = false
    @State private var showingws_overlayLauncher = false
    @State private var showSystemWriteRefused = false
    @StateObject private var vars = PersistentVariables()
    @Environment(\.sipEnabled) private var sipEnabled
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack {
            if #available(macOS 12.0, *) {
                if sipEnabled == true && vars.pesterMeWithSipping == true {
                    Text("System write-dependent features have been disabled.").foregroundColor(
                        .secondary
                    )
                    .padding(3)
                    .padding(.bottom, 8)
                }
            }

            HStack {
                VStack(spacing: 8) {
                    Image("Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)

                    Text(appName ?? "DEBOOGEY_DEVELOPMENT_STATE")
                        .font(.largeTitle)
                        .fontWeight(.black)
                    Text(
                        (shortVersion.isEmpty ? "" : "\(shortVersion)")
                            + (buildNumber.isEmpty
                                ? "" : shortVersion.isEmpty ? "\(buildNumber)" : " \(buildNumber)")
                    )
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue))
                }
                VStack(spacing: 12) {
                    LauncherButton(
                        title: "Ladybug Interface",
                        icon: "ladybug",
                        color: .blue
                    ) {
                        showingLadybugLauncher = true
                    }

                    if #available(macOS 12.0, *) {
                        LauncherButton(
                            title: "WindowServer Diagnostics",
                            icon: "macwindow",
                            color: .blue
                        ) {
                            showingws_overlayLauncher = true
                        }
                        .disabled(sipEnabled)
                    } else {
                        HStack {
                            LauncherButton(
                                title: "WindowServer Diagnostics",
                                icon: "rectangle",
                                color: .secondary
                            ) { }
                            .disabled(true)
                            
                            Button(action: {
                                alertMessage = "Upgrade to macOS 12 to use WindowServer Diagnostics."
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if #available(macOS 14.0, *) {
                        ModernSettingsLauncher()
                    } else {
                        LauncherButton(
                            title: {
                                if #available(macOS 13.0, *) { return "Settings" }
                                return "Preferences"
                            }(),
                            icon: "gear",
                            color: .gray
                        ) {
                            if #available(macOS 13.0, *) {
                                NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
                            } else {
                                NSApp.sendAction(Selector("showPreferencesWindow:"), to: nil, from: nil)
                            }
                        }
                    }
                }
                .padding()
            }

            Link(destination: URL(string: "https://github.com/theoderoy")!) {
                Text("github.com/theoderoy")
                    .bold()
                    .padding(4)
            }
        }
        .sheet(isPresented: $showingws_overlayLauncher) {
            if #available(macOS 13.0, *) {
                NavigationStack {
                    ws_overlayLauncherView { argument in
                        print("ws_overlayLauncherView Requested: \(argument)")
                    }
                }
            } else {
                if #available(macOS 12.0, *) {
                    NavigationView {
                        ws_overlayLauncherView { argument in
                            print("ws_overlayLauncherView Requested: \(argument)")
                        }
                    }
                    .frame(width: 520, height: 540)
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showingLadybugLauncher) {
            if #available(macOS 13.0, *) {
                NavigationStack {
                    LadybugLauncherView { action, domain in
                        print("LadybugLauncherView Requested: \(action) \(domain)")
                    }
                }
            } else {
                NavigationView {
                    LadybugLauncherView { action, domain in
                        print("LadybugLauncherView Requested: \(action) \(domain)")
                    }
                }
                .frame(width: 520, height: 650)
            }
        }
        .alert(isPresented: $showSystemWriteRefused) {
            Alert(
                title: Text("System write-dependent features have been disabled."),
                message: Text("Some features of this app require System Integrity Protection to be disabled.\n\nThis helps protect your Mac, so disable it if you understand the risks."),
                primaryButton: .default(Text("Learn More")) {
                    if let url = URL(string: "https://support.apple.com/guide/security/secb7ea06b49/web") {
                        openURL(url)
                    }
                },
                secondaryButton: .cancel(Text("OK"))
            )
        }
        .alert(item: Binding<IdentifiableString?>(
            get: { alertMessage.map { IdentifiableString(value: $0) } },
            set: { _ in alertMessage = nil }
        )) { message in
            Alert(title: Text(message.value))
        }
        .onAppear {
            if #available(macOS 12.0, *) {
                if sipEnabled == true && vars.pesterMeWithSipping == true {
                    DispatchQueue.main.async {
                        showSystemWriteRefused = true
                    }
                }
            }
        }
        .frame(width: 520, height: 610)
    }
}

@available(macOS 14.0, *)
private struct ModernSettingsLauncher: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        LauncherButton(
            title: "Configuration",
            icon: "gear",
            color: .gray
        ) {
            openWindow(id: "settings")
        }
    }
}

#Preview {
    RootView()
}
