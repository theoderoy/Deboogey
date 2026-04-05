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
    @State private var showingEntityTracker = false
    @State private var showingWhatsNew = false
    @State private var updateCardOpen = false
    @State private var hideUpdateCard = false
    @State private var showUpdateCardOverride = false
    @State private var highlightUpdateCard = false
    @StateObject private var vars = PersistentVariables()
    @ObservedObject var upgradeChecker = UpgradeChecker.shared
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    @Environment(\.sipSatisfied) private var sipSatisfied
    @Environment(\.openURL) private var openURL
    
    enum ActiveAlert: Identifiable, Equatable {
        case message(String)
        case sipNotice
        
        var id: String {
            switch self {
            case .message(let str): return "message-\(str)"
            case .sipNotice: return "sipNotice"
            }
        }
    }

    var body: some View {
        VStack {
            if #available(macOS 12.0, *) {
                if sipSatisfied == true && vars.pesterMeWithSipping == true {
                    Text("System write-dependent features have been disabled.")
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
                        .fontWeight(.bold)
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
                    if #available(macOS 13.0, *) {
                        LadybugWindowLauncher()
                    } else {
                        LauncherButton(
                            title: "Cocoa Debug Menu",
                            icon: "ladybug",
                            color: .accentColor
                        ) {
                            showingLadybugLauncher = true
                        }
                    }

                    if #available(macOS 13.0, *) {
                        if sipSatisfied {
                            HStack {
                                LauncherButton(
                                    title: "SkyLight Diagnostics",
                                    icon: "macwindow",
                                    color: .accentColor
                                ) { }
                                .disabled(true)

                                Button(action: {
                                    activeAlert = .sipNotice
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            WsOverlayWindowLauncher()
                        }
                    } else if #available(macOS 12.0, *) {
                        if sipSatisfied {
                            HStack {
                                LauncherButton(
                                    title: "SkyLight Diagnostics",
                                    icon: "macwindow",
                                    color: .accentColor
                                ) { }
                                .disabled(true)

                                Button(action: {
                                    activeAlert = .sipNotice
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            LauncherButton(
                                title: "SkyLight Diagnostics",
                                icon: "macwindow",
                                color: .accentColor
                            ) {
                                showingws_overlayLauncher = true
                            }
                        }
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

                    Divider()
                        .frame(width: 220)

                    if #available(macOS 13.0, *) {
                        EntityTrackerWindowLauncher()
                    } else {
                        LauncherButton(
                            title: "Entity Tracker",
                            icon: "binoculars",
                            color: .accentColor
                        ) {
                            showingEntityTracker = true
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
            
            if (upgradeChecker.upgradeAvailable && (!vars.hideUpgradeAlerts || showUpdateCardOverride) && (!hideUpdateCard || showUpdateCardOverride)) || (!networkMonitor.isConnected && !vars.hideUpgradeAlerts && !hideUpdateCard && vars.showNetworkNotices) {
                ZStack {
                    Rectangle()
                        .cornerRadius(20)
                        .foregroundColor(!networkMonitor.isConnected && !upgradeChecker.upgradeAvailable ? .orange : .accentColor)
                        .opacity(0.1)
                    if updateCardOpen || (!networkMonitor.isConnected && !upgradeChecker.upgradeAvailable && vars.showNetworkNotices) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                if !networkMonitor.isConnected && !upgradeChecker.upgradeAvailable {
                                    Text("Network connection required").font(.headline)
                                    Text("Connect to check for upgrades").font(.caption).foregroundColor(.orange)
                                } else {
                                    Text("\(upgradeChecker.formattedLatestVersion) is available").font(.headline)
                                    if !networkMonitor.isConnected {
                                        Text("Network connection required to download upgrade").font(.caption).foregroundColor(.orange)
                                    } else {
                                        Text("You might need to manually code-sign after upgrading.").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            if upgradeChecker.isUpdating {
                                ProgressView()
                            } else if upgradeChecker.upgradeAvailable {
                                HStack(spacing: 8) {
                                    Button("Upgrade") {
                                        vars.hasShownWhatsNew = false
                                        upgradeChecker.upgradeAvailable = false
                                        upgradeChecker.proceedWithUpdate()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!networkMonitor.isConnected)
                                    
                                    if !networkMonitor.isConnected {
                                        Image(systemName: "wifi.slash")
                                            .foregroundColor(.orange)
                                            .help("No network connection")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    } else {
                        Button(action: { updateCardOpen = true }) {
                            HStack(spacing: 6) {
                                Text("Upgrade available")
                                if !networkMonitor.isConnected {
                                    Image(systemName: "wifi.slash")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                                Image(systemName: "chevron.down")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if (updateCardOpen || (!networkMonitor.isConnected && !upgradeChecker.upgradeAvailable && vars.showNetworkNotices)) && !upgradeChecker.isUpdating {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: { 
                                    hideUpdateCard = true
                                    showUpdateCardOverride = false
                                    updateCardOpen = false
                                    highlightUpdateCard = false
                                }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                            }
                            Spacer()
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke((!networkMonitor.isConnected && !upgradeChecker.upgradeAvailable ? Color.orange : Color.accentColor).opacity(highlightUpdateCard ? 0.9 : 0), lineWidth: 2)
                )
                .scaleEffect(highlightUpdateCard ? 1.02 : 1)
                .animation(.easeInOut(duration: 0.35), value: highlightUpdateCard)
                .frame(width: 420, height: (updateCardOpen || (!networkMonitor.isConnected && !upgradeChecker.upgradeAvailable && vars.showNetworkNotices)) ? 70 : 38)
                .padding(10)
            }
        }
        .sheet(isPresented: $showingws_overlayLauncher) {
            if #available(macOS 12.0, *) {
                NavigationView {
                    ws_overlayLauncherView { argument in
                        EntityTracker.shared.record(source: .wsOverlay, arguments: [argument])
                    }
                }
                .frame(width: 520, height: 540)
            }
        }
        .sheet(isPresented: $showingLadybugLauncher) {
            NavigationView {
                LadybugLauncherView { arguments in
                    EntityTracker.shared.record(source: .ladybug, arguments: arguments)
                }
            }
            .frame(width: 520, height: 650)
        }
        .sheet(isPresented: $showingEntityTracker) {
            NavigationView {
                EntityTrackerView()
            }
            .frame(width: 560, height: 480)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView {
                showingWhatsNew = false
                vars.hasShownWhatsNew = true
                performStartupChecks()
            }
        }
        .alert(item: $activeAlert) { item in
            switch item {
            case .message(let message):
                return Alert(title: Text(message))
            case .sipNotice:
                return Alert(
                    title: Text("System write-dependent features have been disabled."),
                    message: Text("Some features of this app require debugging restrictions to be lifted.\n\nThis helps protect your Mac. Deboogey does not take malicious advantage of this, but adjust only if you understand the risks."),
                    primaryButton: .default(Text("Learn More")) {
                        if let url = URL(string: "https://support.apple.com/guide/security/secb7ea06b49/web") {
                            openURL(url)
                        }
                    },
                    secondaryButton: .default(Text("OK"))
                )
            }
        }
        .onAppear {
            if !vars.hasShownWhatsNew {
                showingWhatsNew = true
            } else {
                performStartupChecks()
            }
        }
        .onReceive(upgradeChecker.manualCheck) { _ in
            runManualCheck()
        }
        .onChange(of: upgradeChecker.upgradeAvailable) { available in
            if available && !vars.hideUpgradeAlerts { hideUpdateCard = false; showUpdateCardOverride = false; updateCardOpen = true }
        }
        .onChange(of: vars.hideUpgradeAlerts) { hide in
            if hide { updateCardOpen = false; hideUpdateCard = true; showUpdateCardOverride = false }
        }
        .frame(width: 520, height: 610)
    }

    private func performStartupChecks() {
        if #available(macOS 12.0, *) {
            if sipSatisfied == true && vars.pesterMeWithSipping == true {
                DispatchQueue.main.async {
                    activeAlert = .sipNotice
                }
            }
        }
        upgradeChecker.cleanUpOldApp()
        upgradeChecker.checkForUpdates()
    }

    private func runManualCheck() {
        if !networkMonitor.isConnected && !upgradeChecker.upgradeAvailable {
            if vars.showNetworkNotices {
                showUpdateCardOverride = true
                hideUpdateCard = false
            }
            return
        }
        
        upgradeChecker.checkForUpdates(force: true, clearIfNone: true) { found in
            if found {
                if updateCardOpen {
                    vars.hasShownWhatsNew = false
                    upgradeChecker.upgradeAvailable = false
                    upgradeChecker.proceedWithUpdate()
                } else {
                    showUpdateCardOverride = vars.hideUpgradeAlerts || hideUpdateCard
                    updateCardOpen = true
                    highlightUpdateCard = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { highlightUpdateCard = false }
                }
            } else { activeAlert = .message("No upgrade is present at this time.") }
        }
    }
}

@available(macOS 13.0, *)
private struct LadybugWindowLauncher: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        LauncherButton(title: "Cocoa Debug Menu", icon: "ladybug", color: .accentColor) {
            openWindow(id: "ladybug-launcher")
        }
    }
}

@available(macOS 13.0, *)
private struct WsOverlayWindowLauncher: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        LauncherButton(title: "SkyLight Diagnostics", icon: "macwindow", color: .accentColor) {
            openWindow(id: "ws-overlay-launcher")
        }
    }
}

@available(macOS 13.0, *)
private struct EntityTrackerWindowLauncher: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        LauncherButton(title: "Entity Tracker", icon: "binoculars", color: .accentColor) {
            openWindow(id: "entity-tracker")
        }
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
