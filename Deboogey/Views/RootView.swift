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

struct RootView: View {
    @State private var alertMessage: String? = nil
    @State private var showingLadybugLauncher = false
    @State private var showingws_overlayLauncher = false
    @State private var showingSettings = false
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
                VStack {
                    Group {
                        Button(action: {
                            showingLadybugLauncher = true
                        }) {
                            Label {
                                Text("Ladybug Interface")
                            } icon: {
                                Image(systemName: "ladybug")
                            }
                            .font(.headline)
                            .padding(8)
                            .frame(maxWidth: 220)
                        }
                        .buttonStyle(.plain)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Group {
                        if #available(macOS 12.0, *) {
                            Button(action: {
                                showingws_overlayLauncher = true
                            }) {
                                Label {
                                    Text("WindowServer Diagnostics")
                                } icon: {
                                    Image(systemName: "macwindow")
                                }
                                .font(.headline)
                                .padding(8)
                                .frame(maxWidth: 220)
                            }
                            .buttonStyle(.plain)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .disabled(sipEnabled)
                        } else {
                            HStack {
                                Button(action: {}) {
                                    Label {
                                        Text("WindowServer Diagnostics")
                                    } icon: {
                                        Image(systemName: "rectangle")
                                    }
                                    .font(.headline)
                                    .padding(8)
                                    .frame(maxWidth: 180)
                                }
                                .buttonStyle(.plain)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                                .disabled(true)
                                
                                Button(action: {
                                    alertMessage = "WindowServer Diagnostics requires macOS 12.0 (Monterey) or later."
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Group {
                        if #available(macOS 14.0, *) {
                            ModernConfigurationButton()
                        } else {
                            if #available(macOS 12.0, *) {
                                Button(action: {
                                    showingSettings = true
                                }) {
                                    Label {
                                        Text("Settings")
                                    } icon: {
                                        Image(systemName: "gear")
                                    }
                                    .font(.headline)
                                    .padding(8)
                                    .frame(maxWidth: 220)
                                }
                                .buttonStyle(.plain)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                }
                            }
                    }
                    .padding(.top, 20)
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
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
             ConfigurationRootView()
                 .frame(minWidth: 500, minHeight: 400)
                 .toolbar {
                     ToolbarItem(placement: .confirmationAction) {
                         Button("Done") { showingSettings = false }
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
private struct ModernConfigurationButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: {
            openWindow(id: "settings")
        }) {
            Label {
                Text("Configuration")
            } icon: {
                Image(systemName: "gear")
            }
            .font(.headline)
            .padding(8)
            .frame(maxWidth: 220)
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    RootView()
}
