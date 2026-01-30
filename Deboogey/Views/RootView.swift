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
    @State private var activeAlert: ActiveAlert?
    @State private var showingLadybugLauncher = false
    @State private var showingws_overlayLauncher = false
    @StateObject private var vars = PersistentVariables()
    @ObservedObject var upgradeChecker = UpgradeChecker.shared
    @Environment(\.sipEnabled) private var sipEnabled
    @Environment(\.openURL) private var openURL
    
    enum ActiveAlert: Identifiable, Equatable {
        case message(String)
        case sipNotice
        case upgradeAvailable
        
        var id: String {
            switch self {
            case .message(let str): return "message-\(str)"
            case .sipNotice: return "sipNotice"
            case .upgradeAvailable: return "upgradeAvailable"
            }
        }
    }

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
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
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
                    .background(Capsule().fill(Color.accentColor))
                }
                VStack(spacing: 12) {
                    LauncherButton(
                        title: "Cocoa Debug Menu",
                        icon: "ladybug",
                        color: .accentColor
                    ) {
                        showingLadybugLauncher = true
                    }

                    if #available(macOS 12.0, *) {
                        LauncherButton(
                            title: "SkyLight Diagnostics",
                            icon: "macwindow",
                            color: .accentColor
                        ) {
                            showingws_overlayLauncher = true
                        }
                        .disabled(sipEnabled)
                    } else {
                        HStack {
                            LauncherButton(
                                title: "SkyLight Diagnostics",
                                icon: "rectangle",
                                color: .secondary
                            ) { }
                            .disabled(true)
                            
                            Button(action: {
                                activeAlert = .message("Upgrade to macOS 12 to use SkyLight Diagnostics.")
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
        .alert(item: $activeAlert) { item in
            switch item {
            case .message(let message):
                return Alert(title: Text(message))
            case .sipNotice:
                return Alert(
                    title: Text("System write-dependent features have been disabled."),
                    message: Text("Some features of this app require System Integrity Protection to be disabled.\n\nThis helps protect your Mac, so disable it if you understand the risks."),
                    primaryButton: .default(Text("Learn More")) {
                        if let url = URL(string: "https://support.apple.com/guide/security/secb7ea06b49/web") {
                            openURL(url)
                        }
                    },
                    secondaryButton: .cancel(Text("OK"))
                )
            case .upgradeAvailable:
                return Alert(
                    title: Text("Upgrade Available"),
                    message: Text("\(upgradeChecker.formattedLatestVersion) is available.\n\nYou might need to manually code-sign the application after upgrading."),
                    primaryButton: .default(Text("Upgrade"), action: {
                        upgradeChecker.upgradeAvailable = false
                        upgradeChecker.proceedWithUpdate()
                    }),
                    secondaryButton: .cancel {
                        upgradeChecker.upgradeAvailable = false
                    }
                )
            }
        }
        .onAppear {
            if #available(macOS 12.0, *) {
                if sipEnabled == true && vars.pesterMeWithSipping == true {
                    DispatchQueue.main.async {
                        activeAlert = .sipNotice
                    }
                }
            }
            upgradeChecker.cleanUpOldApp()
            upgradeChecker.checkForUpdates()
        }
        .onChange(of: upgradeChecker.upgradeAvailable) { available in
            if available && activeAlert == nil && !vars.hideUpgradeAlerts {
                activeAlert = .upgradeAvailable
            }
        }
        .onChange(of: activeAlert) { newValue in
            if newValue == nil && upgradeChecker.upgradeAvailable {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if activeAlert == nil && !vars.hideUpgradeAlerts {
                        activeAlert = .upgradeAvailable
                    }
                }
            }
        }
        .onChange(of: vars.hideUpgradeAlerts) { hide in
            if hide && activeAlert == .upgradeAvailable {
                activeAlert = nil
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
