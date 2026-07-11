//
//  RootView.swift
//  DeboogeyClient
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

private struct WindowDefaultSizeApplier: NSViewRepresentable {
    let sizing: AppWindowSize
    let onWindowPrepared: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sizing: sizing,
            onWindowPrepared: onWindowPrepared
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.applySizing(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.applySizing(to: nsView.window)
        }
    }

    final class Coordinator {
        private let sizing: AppWindowSize
        private let onWindowPrepared: () -> Void
        private var didApplyDefaultSize = false
        private var didPrepareWindow = false

        init(
            sizing: AppWindowSize,
            onWindowPrepared: @escaping () -> Void
        ) {
            self.sizing = sizing
            self.onWindowPrepared = onWindowPrepared
        }

        func applySizing(to window: NSWindow?) {
            guard let window else { return }

            let minimumFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: sizing.minimumSize)
            ).size
            window.minSize = minimumFrameSize

            let currentContentSize = window.contentLayoutRect.size
            if !didApplyDefaultSize || currentContentSize.isSmaller(than: sizing.minimumSize) {
                window.setContentSize(sizing.defaultSize)
                didApplyDefaultSize = true
            }

            guard !didPrepareWindow else { return }
            didPrepareWindow = true
            onWindowPrepared()
        }
    }
}

private extension CGSize {
    func isSmaller(than other: CGSize) -> Bool {
        width < other.width || height < other.height
    }
}

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
                Text(L10n.t(title))
            } icon: {
                Image(systemName: icon)
            }
            .font(.headline)
            .frame(width: 220)
            .contentShape(Rectangle())
        }
        .launcherButtonStyle(tint: color)
    }
}

private extension View {
    @ViewBuilder
    func launcherButtonStyle(tint color: Color) -> some View {
        if #available(macOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.large)
                .tint(color)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.large)
                .tint(color)
        }
    }

    @ViewBuilder
    func developmentStateCapsuleStyle() -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .glassEffect(.regular.tint(.accentColor), in: .capsule)
        } else {
            self
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor))
        }
    }
}

struct RootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.sipSatisfied) private var sipSatisfied

    @ObservedObject var networkMonitor = NetworkMonitor.shared
    @ObservedObject var upgradeChecker = UpgradeChecker.shared

    @StateObject private var vars = PersistentVariables()

    @State private var activeAlert: ActiveAlert?
    @State private var cltInstalled: Bool = false
    @State private var didRunStartupFlow = false

    @State private var showingDeboogeyCDMLauncher = false
    @State private var showingDeboogeySDLauncher = false
    @State private var showingEntityTracker = false
    @State private var showingWhatsNew = false

    @State private var hideUpdateCard = false
    @State private var highlightUpdateCard = false
    @State private var showUpdateCardOverride = false
    @State private var updateCardOpen = false
    @State private var hideExperimentalBuildCard = false

    enum ActiveAlert: Identifiable, Equatable {
        case message(String)
        case sipNotice
        case cltNotice
        case internalUpgradeNotice
        
        var id: String {
            switch self {
            case .message(let str): return "message-\(str)"
            case .sipNotice: return "sipNotice"
            case .cltNotice: return "cltNotice"
            case .internalUpgradeNotice: return "internalUpgradeNotice"
            }
        }
    }

    private var shouldShowUpdateCard: Bool {
        upgradeChecker.isUpdating
        || (upgradeChecker.upgradeAvailable && (!vars.hideUpgradeAlerts || showUpdateCardOverride) && (!hideUpdateCard || showUpdateCardOverride))
        || (!networkMonitor.isConnected && !vars.hideUpgradeAlerts && !hideUpdateCard && vars.showNetworkNotices)
    }

    private var updateCardExpanded: Bool {
        upgradeChecker.isUpdating
        || updateCardOpen
        || (!networkMonitor.isConnected && !upgradeChecker.upgradeAvailable && vars.showNetworkNotices)
    }

    private var boundedUpdateProgress: Double {
        min(max(upgradeChecker.updateProgress, 0), 1)
    }
    
    var body: some View {
        VStack {
            if upgradeChecker.isExperimentalBuild && !hideExperimentalBuildCard {
                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(upgradeChecker.isDevelopmentBuild ? .red : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t(upgradeChecker.isDevelopmentBuild ? "PlaceholderText1" : "This version of Deboogey is experimental."))
                                .font(.headline)
                            Text(L10n.t(upgradeChecker.isDevelopmentBuild ? "PlaceholderText2" : "This build contains experimental features and is not officially notarised by Apple. Use caution when running it."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 22)
                    }
                    Button(action: { hideExperimentalBuildCard = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .padding(12)
                .frame(width: 420)
                .background((upgradeChecker.isDevelopmentBuild ? Color.red : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                .padding(.top, 8)
            }

            if sipSatisfied == true && vars.pesterMeWithSipping == true {
                Text(L10n.t("System write-dependent features have been disabled."))
                    .foregroundStyle(.tertiary)
                    .padding(3)
                    .padding(.bottom, 8)
            }
            
            HStack {
                VStack(spacing: 8) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                    
                    Text(appName ?? "DEBOOGEY_DEVELOPMENT_STATE")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text(
                        (shortVersion.isEmpty ? "" : "\(shortVersion)")
                        + (buildNumber.isEmpty
                           ? "" : shortVersion.isEmpty ? "\(buildNumber)" : " \(buildNumber)")
                    )
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .bold()
                    .developmentStateCapsuleStyle()
                }
                VStack(spacing: 12) {
                    if #available(macOS 13.0, *) {
                        DeboogeyCDMWindowLauncher()
                    } else {
                        LauncherButton(
                            title: "Cocoa Debug Menu",
                            icon: "wrench.and.screwdriver",
                            color: .accentColor
                        ) {
                            showingDeboogeyCDMLauncher = true
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
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        } else if !cltInstalled {
                            HStack {
                                LauncherButton(
                                    title: "SkyLight Diagnostics",
                                    icon: "macwindow",
                                    color: .accentColor
                                ) { }
                                    .disabled(true)
                                
                                Button(action: {
                                    activeAlert = .cltNotice
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            DeboogeySDWindowLauncher()
                        }
                    } else {
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
                        } else if !cltInstalled {
                            HStack {
                                LauncherButton(
                                    title: "SkyLight Diagnostics",
                                    icon: "macwindow",
                                    color: .accentColor
                                ) { }
                                    .disabled(true)
                                
                                Button(action: {
                                    activeAlert = .cltNotice
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
                                showingDeboogeySDLauncher = true
                            }
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
            
            if shouldShowUpdateCard {
                ZStack {
                    Rectangle()
                        .cornerRadius(20)
                        .foregroundColor(!networkMonitor.isConnected && !upgradeChecker.upgradeAvailable ? .orange : .accentColor)
                        .opacity(0.1)
                    if upgradeChecker.isUpdating {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L10n.t(upgradeChecker.updateStep.isEmpty ? "Preparing upgrade" : upgradeChecker.updateStep))
                                    .font(.headline)
                                Spacer()
                                Text("\(Int((boundedUpdateProgress * 100).rounded()))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: boundedUpdateProgress, total: 1)
                                .progressViewStyle(.linear)
                        }
                        .padding(.horizontal, 14)
                    } else if updateCardExpanded {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                if !networkMonitor.isConnected && !upgradeChecker.upgradeAvailable {
                                    Text(L10n.t("Network connection required")).font(.headline)
                                    Text(L10n.t("Connect to check for upgrades")).font(.caption).foregroundColor(.orange)
                                } else {
                                    Text(L10n.f("%@ is available", upgradeChecker.formattedLatestVersion)).font(.headline)
                                    if !networkMonitor.isConnected {
                                        Text(L10n.t("Network connection required to download upgrade")).font(.caption).foregroundColor(.orange)
                                    } else {
                                        Text(L10n.t("You might need to manually code-sign after upgrading.")).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            if upgradeChecker.upgradeAvailable {
                                HStack(spacing: 8) {
                                    Button(L10n.t("Upgrade")) {
                                        beginUpgrade()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!networkMonitor.isConnected)
                                    
                                    if !networkMonitor.isConnected {
                                        Image(systemName: "wifi.slash")
                                            .foregroundColor(.orange)
                                            .help(L10n.t("No network connection"))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    } else {
                        Button(action: { updateCardOpen = true }) {
                            HStack(spacing: 6) {
                                Text(L10n.t("Upgrade available"))
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
                    if updateCardExpanded && !upgradeChecker.isUpdating {
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
                .frame(width: 420, height: updateCardExpanded ? 70 : 38)
                .padding(10)
                
                if DebugVariables.auxiliaryUpgrades {
                    Text(L10n.t("Auxiliary upgrades have been enabled."))
                        .foregroundStyle(.orange)
                        .padding(.bottom, 8)
                }
            }

            if let forced = DebugVariables.forcedVersionType {
                Text(L10n.f("Parameters pose this build type as %@.", forced.localizedName))
                    .foregroundStyle(.orange)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showingDeboogeySDLauncher) {
            NavigationView {
                DeboogeySDLauncherView { argument in
                    EntityTracker.shared.record(source: .wsOverlay, arguments: [argument])
                }
            }
            .frame(width: 520, height: 540)
        }
        .sheet(isPresented: $showingDeboogeyCDMLauncher) {
            NavigationView {
                DeboogeyCDMLauncherView { arguments in
                    EntityTracker.shared.record(source: .deboogeyCDM, arguments: arguments)
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
                    title: Text(L10n.t("System write-dependent features have been disabled.")),
                    message: Text(L10n.t("Some features of this app require debugging restrictions to be lifted.\n\nThis helps protect your Mac. Deboogey does not take malicious advantage of this, but adjust only if you understand the risks.")),
                    primaryButton: .default(Text(L10n.t("Learn More"))) {
                        if let url = URL(string: "https://support.apple.com/guide/security/secb7ea06b49/web") {
                            openURL(url)
                        }
                    },
                    secondaryButton: .default(Text(L10n.t("OK")))
                )
            case .cltNotice:
                return Alert(
                    title: Text(L10n.t("Command Line Tools for Xcode are not installed.")),
                    message: Text(L10n.t("Some features of this app require Command Line Tools for Xcode.")),
                    primaryButton: .default(Text(L10n.t("Install"))) {
                        installCLT()
                    },
                    secondaryButton: .cancel()
                )
            case .internalUpgradeNotice:
                return Alert(
                    title: Text(L10n.t("Upgrade to an experimental build?")),
                    message: Text(L10n.t("This build contains experimental features and is not officially notarised by Apple. Use caution when running it.")),
                    primaryButton: .destructive(Text(L10n.t("Continue"))) {
                        performUpgrade()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                prepareStartupFlowIfNeeded()
            }
        }
        .onReceive(upgradeChecker.manualCheck) { _ in
            runManualCheck()
        }
        .onReceive(upgradeChecker.auxiliaryArchiveCompleted) { filename in
            activeAlert = .message(L10n.f("%@ has been baked successfully.", filename))
        }
        .onChange(of: upgradeChecker.upgradeAvailable) { available in
            if available && !vars.hideUpgradeAlerts { hideUpdateCard = false; showUpdateCardOverride = false; updateCardOpen = true }
        }
        .onChange(of: vars.hideUpgradeAlerts) { hide in
            if hide { updateCardOpen = false; hideUpdateCard = true; showUpdateCardOverride = false }
        }
        .minimumWindowContentSize(AppWindowSizing.root)
        .background(
            WindowDefaultSizeApplier(sizing: AppWindowSizing.root) {
                prepareStartupFlowIfNeeded()
            }
        )
    }

    private func prepareStartupFlowIfNeeded() {
        guard !didRunStartupFlow else { return }
        didRunStartupFlow = true
        checkCLT()
        if DebugVariables.alwaysShowWhatsNewView || !vars.hasShownWhatsNew {
            showingWhatsNew = true
        } else {
            performStartupChecks()
        }
    }
    
    private func installCLT() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        try? process.run()
        NSApp.terminate(nil)
    }
    
    private func checkCLT() {
        let xcodeSelect = "/usr/bin/xcode-select"
        guard FileManager.default.isExecutableFile(atPath: xcodeSelect) else {
            cltInstalled = false
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcodeSelect)
        process.arguments = ["-p"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            cltInstalled = process.terminationStatus == 0
        } catch {
            cltInstalled = false
        }
    }
    
    private func performStartupChecks() {
        if sipSatisfied == true && vars.pesterMeWithSipping == true {
            DispatchQueue.main.async {
                activeAlert = .sipNotice
            }
        } else if sipSatisfied == false && !cltInstalled && vars.showCLTNotices == true {
            DispatchQueue.main.async {
                activeAlert = .cltNotice
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
                    beginUpgrade()
                } else {
                    showUpdateCardOverride = vars.hideUpgradeAlerts || hideUpdateCard
                    updateCardOpen = true
                    highlightUpdateCard = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { highlightUpdateCard = false }
                }
            } else { activeAlert = .message(L10n.t("No upgrade is present at this time.")) }
        }
    }

    private func beginUpgrade() {
        if upgradeChecker.shouldConfirmInternalUpgrade {
            activeAlert = .internalUpgradeNotice
        } else {
            performUpgrade()
        }
    }

    private func performUpgrade() {
        vars.hasShownWhatsNew = false
        upgradeChecker.upgradeAvailable = false
        upgradeChecker.proceedWithUpdate()
    }
}

@available(macOS 13.0, *)
private struct DeboogeyCDMWindowLauncher: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        LauncherButton(title: "Cocoa Debug Menu", icon: "wrench.and.screwdriver", color: .accentColor) {
            openWindow(id: "deboogey-cdm-launcher")
        }
    }
}

@available(macOS 13.0, *)
private struct DeboogeySDWindowLauncher: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        LauncherButton(title: "SkyLight Diagnostics", icon: "macwindow", color: .accentColor) {
            openWindow(id: "deboogey-sd-launcher")
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

