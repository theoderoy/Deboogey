//
//  RootView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

let appName =
Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
let shortVersion =
Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

#if os(macOS)
private enum RootLauncherMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 16
    static let actionsPadding: CGFloat = 8
    static let bannerContentSpacing: CGFloat = 14
    static let bannerWidth: CGFloat = 420
    static let topBannerHeight: CGFloat = 64
    static let bottomBannerHeight: CGFloat = 58
    static let bottomBannerCollapsedHeight: CGFloat = 32
}

private struct RootBannerMotion {
    let reduceMotion: Bool

    var pop: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    var unfold: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    var popTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.86).combined(with: .opacity),
                removal: .scale(scale: 0.92).combined(with: .opacity)
            )
    }

    var unfoldTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
            )
    }
}

private final class RootWindowChromeProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.applyFixedLauncherChrome()
        if window.alphaValue < 1 { window.alphaValue = 1 }
    }
}

private struct RootWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> RootWindowChromeProbe {
        let view = RootWindowChromeProbe(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: RootWindowChromeProbe, context: Context) {}
}
private struct RootLauncherBranding: View {
    var body: some View {
        VStack(spacing: 8) {
            Image("DeboogeyIdent")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)

            Text(appName ?? "DEBOOGEY_DEVELOPMENT_STATE")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}

private struct RootLauncherCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .fixedSize()
            .background(RootWindowChrome())
    }
}
#endif

struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

struct LauncherButton: View {
    let title: String
    let icon: String
    let color: Color
    var prominent: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label {
                Text(L10n.t(title))
            } icon: {
                LauncherIcon(name: icon)
            }
            .deboogeyStandardButtonLabel()
        }
        .deboogeyButtonStyle(tint: color, prominent: prominent)
    }
}

private struct EntityTrackerLauncherButton: View {
    let action: () -> Void

    var body: some View {
        LauncherButton(title: "Entity Tracker", icon: "eyeglasses", color: .gray, action: action)
    }
}

#if os(iOS)
private extension View {
    func sheetWithCloseButton<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                content()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                isPresented.wrappedValue = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel(L10n.t("Close"))
                        }
                    }
            }
        }
    }
}
#endif

private struct LauncherIcon: View {
    let name: String

    private var usesAssetIcon: Bool {
#if os(macOS)
        NSImage(named: name) != nil
#else
        UIImage(named: name) != nil
#endif
    }

    var body: some View {
        if usesAssetIcon {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: name)
        }
    }
}

#if os(macOS)
private struct DisabledSkyLightLauncher: View {
    var usesTertiaryStyle: Bool = false
    let onHelp: () -> Void

    var body: some View {
        HStack {
            LauncherButton(
                title: "SkyLight Diagnostics",
                icon: "macwindow",
                color: .accentColor
            ) { }
            .disabled(true)

            Button(action: onHelp) {
                Image(systemName: "questionmark.circle")
                    .font(.title2)
                    .modifier(DisabledSkyLightHelpForeground(usesTertiaryStyle: usesTertiaryStyle))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DisabledSkyLightHelpForeground: ViewModifier {
    let usesTertiaryStyle: Bool

    func body(content: Content) -> some View {
        if usesTertiaryStyle {
            content.foregroundStyle(.tertiary)
        } else {
            content.foregroundColor(.secondary)
        }
    }
}
#endif

struct RootView: View {
#if DEBOOGEY_MCE
#if os(iOS)
    @Environment(\.mceIOSNavigate) private var navigate
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var diffsplitterAvailability = MCEIOSFeatureSupport.Model.shared
    @StateObject private var vars = PersistentVariables()
    @State private var showingSettings = false
    @State private var showingEntityTracker = false
    @State private var showingDiffsplitterUnavailable = false
    @State private var showingWhatsNew = false
    @State private var didPrepareStartupFlow = false

    var body: some View {
        VStack {
            if horizontalSizeClass == .compact {
                VStack(spacing: 24) {
                    branding
                    actions
                }
            } else {
                HStack {
                    branding
                    actions
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheetWithCloseButton(isPresented: $showingSettings) {
            ConfigurationRootView()
        }
        .sheetWithCloseButton(isPresented: $showingEntityTracker) {
            EntityTrackerView()
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView {
                showingWhatsNew = false
                vars.acknowledgeWhatsNew()
            }
            .interactiveDismissDisabled()
        }
        .alert(
            L10n.t("Diffsplitter is unavailable on this device."),
            isPresented: $showingDiffsplitterUnavailable
        ) {
            Button(L10n.t("OK"), role: .cancel) {}
        } message: {
            Text(L10n.t(diffsplitterUnavailableMessage))
        }
        .onAppear {
            guard !didPrepareStartupFlow else { return }
            didPrepareStartupFlow = true
            showingWhatsNew = vars.shouldPresentWhatsNew
        }
    }

    private var branding: some View {
        VStack(spacing: 8) {
            Image("DeboogeyIdent")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            Text(appName ?? "Deboogey")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if diffsplitterAvailability.diffsplitter {
                DeboogeyDiffsplitterIOSLauncher(navigate: navigate)
            } else if diffsplitterAvailability.diffsplitterBlocker == .chip {
                HStack {
                    LauncherButton(
                        title: "Diffsplitter",
                        icon: "DiffsplitterIconIPOSF",
                        color: .accentColor,
                        prominent: true
                    ) { }
                    .disabled(true)

                    Button {
                        showingDiffsplitterUnavailable = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Why is Diffsplitter unavailable?"))
                }
            }

            DeboogeyLoupeIOSLauncher(navigate: navigate)

            EntityTrackerLauncherButton {
                showingEntityTracker = true
            }

            LauncherButton(
                title: PersistentVariables.settingsDisplayTitle(),
                icon: "gear",
                color: .gray
            ) {
                showingSettings = true
            }
        }
        .padding()
    }

    private var diffsplitterUnavailableMessage: String {
        "Diffsplitter requires an Apple A14 or M1 chip, or later."
    }
#else
    @StateObject private var vars = PersistentVariables()

    @State private var showingDeboogeyCDMLauncher = false
    @State private var showingEntityTracker = false
    @State private var showingWhatsNew = false
    @State private var didPrepareStartupFlow = false

    var body: some View {
        RootLauncherCanvas {
            HStack(spacing: RootLauncherMetrics.columnSpacing) {
                RootLauncherBranding()

                VStack(spacing: 12) {
                    if #available(macOS 13.0, *) {
                        DeboogeyLoupeWindowLauncher()
                        DeboogeyDiffsplitterWindowLauncher()
                    } else {
                        DeboogeyLoupeLegacyWindowLauncher()
                        DeboogeyDiffsplitterLegacyWindowLauncher()
                    }

                    LauncherButton(
                        title: "Cocoa Debug Menu",
                        icon: "wrench.and.screwdriver",
                        color: .accentColor
                    ) {
                        showingDeboogeyCDMLauncher = true
                    }

                    Divider()
                        .frame(width: DeboogeyButtonMetrics.standardWidth)

                    if #available(macOS 13.0, *) {
                        EntityTrackerWindowLauncher()
                    } else {
                        EntityTrackerLauncherButton {
                            showingEntityTracker = true
                        }
                    }

                    SettingsLauncher()
                }
                .padding(RootLauncherMetrics.actionsPadding)
            }
            .padding(.horizontal, RootLauncherMetrics.horizontalPadding)
            .padding(.vertical, RootLauncherMetrics.verticalPadding)
        }
        .sheet(isPresented: $showingEntityTracker) {
            NavigationView {
                EntityTrackerView()
            }
            .frame(width: AppWindowSizing.entityTracker.defaultSize.width, height: AppWindowSizing.entityTracker.defaultSize.height)
        }
        .sheet(isPresented: $showingDeboogeyCDMLauncher) {
            DeboogeyCDMLauncherView { arguments in
                EntityTracker.shared.record(source: .deboogeyCDM, arguments: arguments)
            }
            .frame(width: AppWindowSizing.cocoaDebugMenu.defaultSize.width, height: AppWindowSizing.cocoaDebugMenu.defaultSize.height)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView {
                showingWhatsNew = false
                vars.acknowledgeWhatsNew()
            }
        }
        .onAppear {
            guard !didPrepareStartupFlow else { return }
            didPrepareStartupFlow = true
            showingWhatsNew = vars.shouldPresentWhatsNew
        }
    }
#endif
#else
    @Environment(\.openURL) private var openURL
    @Environment(\.sipSatisfied) private var sipSatisfied
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var isOfflineWithoutUpgrade: Bool {
        !networkMonitor.isConnected && !upgradeChecker.upgradeAvailable
    }

    private var shouldShowExperimentalBuildCard: Bool {
        upgradeChecker.isExperimentalBuild && !hideExperimentalBuildCard
    }

    private var shouldShowUpdateCard: Bool {
        !DebugVariables.areUpdatesDisabled
        && (upgradeChecker.isUpdating
        || (upgradeChecker.upgradeAvailable && (!vars.hideUpgradeAlerts || showUpdateCardOverride) && (!hideUpdateCard || showUpdateCardOverride))
        || (!networkMonitor.isConnected && !vars.hideUpgradeAlerts && !hideUpdateCard && vars.showNetworkNotices))
    }

    private var updateCardExpanded: Bool {
        upgradeChecker.isUpdating
        || updateCardOpen
        || (isOfflineWithoutUpgrade && vars.showNetworkNotices)
    }

    private var boundedUpdateProgress: Double {
        min(max(upgradeChecker.updateProgress, 0), 1)
    }

    private var updateCardAccent: Color {
        isOfflineWithoutUpgrade ? .orange : .accentColor
    }

    private var updateBannerHeight: CGFloat {
        shouldShowUpdateCard && !updateCardExpanded
            ? RootLauncherMetrics.bottomBannerCollapsedHeight
            : RootLauncherMetrics.bottomBannerHeight
    }

    private var updateBannerCornerRadius: CGFloat {
        shouldShowUpdateCard && !updateCardExpanded ? 10 : 16
    }

    private var bannerMotion: RootBannerMotion {
        RootBannerMotion(reduceMotion: reduceMotion)
    }

    private var usesTertiarySkyLightHelp: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }
    
    var body: some View {
        let motion = bannerMotion
        RootLauncherCanvas {
            VStack(spacing: RootLauncherMetrics.bannerContentSpacing) {
                ZStack {
                    if shouldShowExperimentalBuildCard {
                        ZStack(alignment: .topTrailing) {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(upgradeChecker.isDevelopmentBuild ? .red : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t(upgradeChecker.isDevelopmentBuild ? "PlaceholderText1" : "This version of Deboogey is experimental."))
                                        .font(.headline)
                                    Text(L10n.t(upgradeChecker.isDevelopmentBuild ? "PlaceholderText2" : "This build contains experimental features and is not officially notarised by Apple. Use caution when running it."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 22)
                            }
                            Button {
                                withAnimation(motion.pop) { hideExperimentalBuildCard = true }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background((upgradeChecker.isDevelopmentBuild ? Color.red : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        .transition(motion.popTransition)
                    }
                }
                .frame(width: RootLauncherMetrics.bannerWidth, height: RootLauncherMetrics.topBannerHeight)

                if !DebugVariables.isMarketplaceCandidateEditionBuild,
                   sipSatisfied == true,
                   vars.pesterMeWithSipping == true {
                    Text(L10n.t("System write-dependent features have been disabled."))
                        .foregroundStyle(.tertiary)
                        .padding(3)
                }

                HStack(spacing: RootLauncherMetrics.columnSpacing) {
                    RootLauncherBranding()
                    VStack(spacing: 12) {
                        if #available(macOS 13.0, *) {
                            DeboogeyLoupeWindowLauncher()
                            DeboogeyDiffsplitterWindowLauncher()
                            DeboogeyCDMWindowLauncher()
                        } else {
                            DeboogeyLoupeLegacyWindowLauncher()
                            DeboogeyDiffsplitterLegacyWindowLauncher()
                            LauncherButton(
                                title: "Cocoa Debug Menu",
                                icon: "wrench.and.screwdriver",
                                color: .accentColor
                            ) {
                                showingDeboogeyCDMLauncher = true
                            }
                        }

                        if !DebugVariables.isMarketplaceCandidateEditionBuild {
                            if sipSatisfied {
                                DisabledSkyLightLauncher(usesTertiaryStyle: usesTertiarySkyLightHelp) {
                                    activeAlert = .sipNotice
                                }
                            } else if !cltInstalled {
                                DisabledSkyLightLauncher {
                                    activeAlert = .cltNotice
                                }
                            } else if #available(macOS 13.0, *) {
                                DeboogeySDWindowLauncher()
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
                            .frame(width: DeboogeyButtonMetrics.standardWidth)

                        if #available(macOS 13.0, *) {
                            EntityTrackerWindowLauncher()
                        } else {
                            EntityTrackerLauncherButton {
                                showingEntityTracker = true
                            }
                        }

                        SettingsLauncher()
                    }
                    .padding(RootLauncherMetrics.actionsPadding)
                }

                ZStack {
                    if shouldShowUpdateCard {
                        ZStack {
                            RoundedRectangle(cornerRadius: updateBannerCornerRadius)
                                .foregroundColor(updateCardAccent)
                                .opacity(0.1)
                            if upgradeChecker.isUpdating {
                                VStack(alignment: .leading, spacing: 4) {
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
                                .padding(.horizontal, 12)
                                .transition(motion.unfoldTransition)
                            } else if updateCardExpanded {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        if isOfflineWithoutUpgrade {
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
                                    Spacer(minLength: 8)
                                    if upgradeChecker.upgradeAvailable {
                                        HStack(spacing: 8) {
                                            Button(L10n.t("Upgrade")) {
                                                beginUpgrade()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .disabled(!networkMonitor.isConnected)

                                            if !networkMonitor.isConnected {
                                                Image(systemName: "wifi.slash")
                                                    .foregroundColor(.orange)
                                                    .help(L10n.t("No network connection"))
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .transition(motion.unfoldTransition)
                            } else {
                                HStack(spacing: 6) {
                                    Button {
                                        withAnimation(motion.unfold) { updateCardOpen = true }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(L10n.t("Upgrade available"))
                                                .font(.caption.weight(.semibold))
                                            if !networkMonitor.isConnected {
                                                Image(systemName: "wifi.slash")
                                                    .foregroundColor(.orange)
                                                    .font(.caption2)
                                            }
                                            Image(systemName: "chevron.down")
                                                .font(.caption2.weight(.semibold))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Spacer(minLength: 4)
                                    Button(action: dismissUpdateCard) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .transition(motion.unfoldTransition)
                            }
                            if updateCardExpanded && !upgradeChecker.isUpdating {
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button(action: dismissUpdateCard) {
                                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(4)
                                    }
                                    Spacer()
                                }
                                .transition(motion.unfoldTransition)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: updateBannerCornerRadius)
                                .stroke(updateCardAccent.opacity(highlightUpdateCard ? 0.9 : 0), lineWidth: 2)
                        )
                        .scaleEffect(highlightUpdateCard ? 1.02 : 1)
                        .animation(.easeInOut(duration: 0.35), value: highlightUpdateCard)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(motion.popTransition)
                    }

                    if DebugVariables.auxiliaryUpgrades {
                        VStack {
                            Spacer()
                            Text(L10n.t("Auxiliary upgrades have been enabled."))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(width: RootLauncherMetrics.bannerWidth, height: updateBannerHeight)
                .animation(motion.unfold, value: updateCardExpanded)

                if let forced = DebugVariables.forcedVersionType {
                    Text(L10n.f("Parameters pose this build type as %@.", forced.localizedName))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, RootLauncherMetrics.horizontalPadding)
            .padding(.vertical, RootLauncherMetrics.verticalPadding)
            .frame(
                width: AppWindowSizing.root.defaultSize.width,
                height: AppWindowSizing.root.defaultSize.height,
                alignment: .top
            )
        }
        .sheet(isPresented: $showingDeboogeySDLauncher) {
            NavigationView {
                DeboogeySDLauncherView { argument in
                    EntityTracker.shared.record(source: .wsOverlay, arguments: [argument])
                }
            }
            .frame(width: AppWindowSizing.skyLightDiagnostics.defaultSize.width, height: AppWindowSizing.skyLightDiagnostics.defaultSize.height)
        }
        .sheet(isPresented: $showingDeboogeyCDMLauncher) {
            NavigationView {
                DeboogeyCDMLauncherView { arguments in
                    EntityTracker.shared.record(source: .deboogeyCDM, arguments: arguments)
                }
            }
            .frame(width: AppWindowSizing.cocoaDebugMenu.defaultSize.width, height: AppWindowSizing.cocoaDebugMenu.defaultSize.height)
        }
        .sheet(isPresented: $showingEntityTracker) {
            NavigationView {
                EntityTrackerView()
            }
            .frame(width: AppWindowSizing.entityTracker.defaultSize.width, height: AppWindowSizing.entityTracker.defaultSize.height)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView {
                showingWhatsNew = false
                vars.acknowledgeWhatsNew()
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
            prepareStartupFlowIfNeeded()
        }
        .onReceive(upgradeChecker.manualCheck) { _ in
            runManualCheck()
        }
        .onReceive(upgradeChecker.auxiliaryArchiveCompleted) { filename in
            activeAlert = .message(L10n.f("%@ has been baked successfully.", filename))
        }
        .onChange(of: upgradeChecker.upgradeAvailable) { available in
            guard available, !vars.hideUpgradeAlerts else { return }
            withAnimation(bannerMotion.pop) {
                hideUpdateCard = false
                showUpdateCardOverride = false
                updateCardOpen = true
            }
        }
        .onChange(of: vars.hideUpgradeAlerts) { hide in
            guard hide else { return }
            withAnimation(bannerMotion.pop) {
                updateCardOpen = false
                hideUpdateCard = true
                showUpdateCardOverride = false
            }
        }
    }

    private func prepareStartupFlowIfNeeded() {
        guard !didRunStartupFlow else { return }
        didRunStartupFlow = true
        if !DebugVariables.isMarketplaceCandidateEditionBuild {
            checkCLT()
        }
        if vars.shouldPresentWhatsNew {
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
        if !DebugVariables.isMarketplaceCandidateEditionBuild,
           sipSatisfied == true,
           vars.pesterMeWithSipping == true {
            DispatchQueue.main.async {
                activeAlert = .sipNotice
            }
        } else if !DebugVariables.isMarketplaceCandidateEditionBuild,
                  sipSatisfied == false,
                  !cltInstalled,
                  vars.showCLTNotices == true {
            DispatchQueue.main.async {
                activeAlert = .cltNotice
            }
        }
        if !DebugVariables.areUpdatesDisabled {
            upgradeChecker.cleanUpOldApp()
            upgradeChecker.checkForUpdates()
        }
    }
    
    private func runManualCheck() {
        guard !DebugVariables.areUpdatesDisabled else { return }
        if isOfflineWithoutUpgrade {
            if vars.showNetworkNotices {
                withAnimation(bannerMotion.pop) {
                    showUpdateCardOverride = true
                    hideUpdateCard = false
                }
            }
            return
        }
        
        upgradeChecker.checkForUpdates(force: true, clearIfNone: true) { found in
            if found {
                if updateCardOpen {
                    beginUpgrade()
                } else {
                    withAnimation(bannerMotion.pop) {
                        showUpdateCardOverride = vars.hideUpgradeAlerts || hideUpdateCard
                        updateCardOpen = true
                    }
                    highlightUpdateCard = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { highlightUpdateCard = false }
                }
            } else { activeAlert = .message(L10n.t("No upgrade is present at this time.")) }
        }
    }

    private func dismissUpdateCard() {
        withAnimation(bannerMotion.pop) {
            hideUpdateCard = true
            showUpdateCardOverride = false
            updateCardOpen = false
            highlightUpdateCard = false
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
        upgradeChecker.upgradeAvailable = false
        upgradeChecker.proceedWithUpdate()
    }
#endif
}

private struct DeboogeyDocumentToolLauncherMenu<Education: View>: View {
    let title: String
    let icon: String
    let prominent: Bool
    let openLabel: String
    let openIcon: String
    let openDocument: () -> Void
    let createDocument: () -> Void
    @Binding var hasShownEducation: Bool
    var forceEducation: Bool = false
    @ViewBuilder let education: (@escaping () -> Void) -> Education

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingEducation = false
    @State private var showingActions = false
    @State private var pendingAction: Action = .open

    private enum Action {
        case open
        case create
    }

    private var prefersActionAlert: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private func showingActionsPresentation(_ matchesAlertPreference: Bool) -> Binding<Bool> {
        Binding(
            get: { showingActions && prefersActionAlert == matchesAlertPreference },
            set: { if prefersActionAlert == matchesAlertPreference { showingActions = $0 } }
        )
    }

    var body: some View {
        LauncherButton(
            title: title,
            icon: icon,
            color: .accentColor,
            prominent: prominent
        ) {
            showingActions = true
        }
        .popover(
            isPresented: showingActionsPresentation(false),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    request(.open)
                } label: {
                    Label(L10n.t(openLabel), systemImage: openIcon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .padding(.horizontal, 4)

                Divider()

                Button {
                    request(.create)
                } label: {
                    Label(L10n.t("Create New Document…"), systemImage: "plus.app")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .padding(.horizontal, 4)
            }
            .frame(minWidth: 280)
        }
        .alert(
            "",
            isPresented: showingActionsPresentation(true)
        ) {
            Button(L10n.t(openLabel)) {
                request(.open)
            }
            Button(L10n.t("Create New Document…")) {
                request(.create)
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showingEducation) {
            education {
                hasShownEducation = true
                showingEducation = false
                DispatchQueue.main.async {
                    perform(pendingAction)
                }
            }
        }
    }

    private func request(_ action: Action) {
        showingActions = false
        pendingAction = action
        if hasShownEducation && !forceEducation {
            perform(action)
        } else {
            showingEducation = true
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .open: openDocument()
        case .create: createDocument()
        }
    }
}

private struct DeboogeyLoupeLauncherMenu: View {
    let openDocument: () -> Void
    let createDocument: () -> Void
    @AppStorage("theoderoy.Deboogey.LoupeMachine.hasShownEducation")
    private var hasShownEducation = false

    var body: some View {
        DeboogeyDocumentToolLauncherMenu(
            title: "Loupe Machine",
            icon: "loupe",
            prominent: true,
            openLabel: "Open Loupe Machine Document",
            openIcon: "doc.text.magnifyingglass",
            openDocument: openDocument,
            createDocument: createDocument,
            hasShownEducation: $hasShownEducation,
            forceEducation: DebugVariables.alwaysShowLMEducation
        ) { onContinue in
            LoupeMachineEducationView(onDismiss: onContinue)
        }
    }
}

private struct DeboogeyDiffsplitterLauncherMenu: View {
    let openDocument: () -> Void
    let createDocument: () -> Void
    var prominent: Bool = false
    @AppStorage("theoderoy.Deboogey.Diffsplitter.hasShownEducation")
    private var hasShownEducation = false

    var body: some View {
        DeboogeyDocumentToolLauncherMenu(
            title: "Diffsplitter",
            icon: "DiffsplitterIconIPOSF",
            prominent: prominent,
            openLabel: "Open Diffsplitter Document",
            openIcon: "doc.text",
            openDocument: openDocument,
            createDocument: createDocument,
            hasShownEducation: $hasShownEducation
        ) { onContinue in
            DiffsplitterEducationView(onDismiss: onContinue)
        }
    }
}

#if os(iOS)
private extension View {
    func mceDocumentImporter(
        isPresented: Binding<Bool>,
        contentTypes: [UTType],
        onOpen: @escaping (URL) -> Void
    ) -> some View {
        fileImporter(
            isPresented: isPresented,
            allowedContentTypes: contentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            onOpen(url)
        }
    }
}

private struct DeboogeyLoupeIOSLauncher: View {
    let navigate: (MCEIOSRoute) -> Void
    @AppStorage("theoderoy.Deboogey.LoupeMachine.hasShownEducation")
    private var hasShownEducation = false
    @State private var showingEducation = false
    @State private var isOpeningDocument = false

    var body: some View {
        LauncherButton(
            title: "Loupe View",
            icon: "loupe",
            color: .accentColor,
            prominent: true
        ) {
            requestOpen()
        }
        .sheet(isPresented: $showingEducation) {
            LoupeMachineEducationView {
                hasShownEducation = true
                showingEducation = false
                DispatchQueue.main.async {
                    isOpeningDocument = true
                }
            }
        }
        .mceDocumentImporter(
            isPresented: $isOpeningDocument,
            contentTypes: [.loupeMachineDocument]
        ) { url in
            navigate(.loupe(LoupeMachineWindowRequest(action: .open, documentURL: url)))
        }
    }

    private func requestOpen() {
        if hasShownEducation && !DebugVariables.alwaysShowLMEducation {
            isOpeningDocument = true
        } else {
            showingEducation = true
        }
    }
}

private struct DeboogeyDiffsplitterIOSLauncher: View {
    let navigate: (MCEIOSRoute) -> Void
    @State private var isOpeningDocument = false

    var body: some View {
        DeboogeyDiffsplitterLauncherMenu(
            openDocument: { isOpeningDocument = true },
            createDocument: {
                navigate(.diffsplitter(DiffsplitterWindowRequest(action: .create, documentURL: nil)))
            },
            prominent: true
        )
        .mceDocumentImporter(
            isPresented: $isOpeningDocument,
            contentTypes: [.diffsplitterDocument, .diffsplitterXDocument]
        ) { url in
            navigate(.diffsplitter(DiffsplitterWindowRequest(action: .open, documentURL: url)))
        }
    }
}
#endif

#if os(macOS)
@available(macOS 13.0, *)
private struct DeboogeyLoupeWindowLauncher: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DeboogeyLoupeLauncherMenu(
            openDocument: { LoupeMachineNavigation.chooseDocument(using: openWindow) },
            createDocument: { LoupeMachineNavigation.open(documentAt: nil, using: openWindow) }
        )
    }
}

private struct DeboogeyLoupeLegacyWindowLauncher: View {
    var body: some View {
        DeboogeyLoupeLauncherMenu(
            openDocument: LoupeMachineNavigation.chooseDocumentLegacy,
            createDocument: { LoupeMachineNavigation.openLegacy(documentAt: nil) }
        )
    }
}

@available(macOS 13.0, *)
private struct DeboogeyDiffsplitterWindowLauncher: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DeboogeyDiffsplitterLauncherMenu(
            openDocument: { DiffsplitterNavigation.chooseDocument(using: openWindow) },
            createDocument: { DiffsplitterNavigation.open(documentAt: nil, using: openWindow) }
        )
    }
}

private struct DeboogeyDiffsplitterLegacyWindowLauncher: View {
    var body: some View {
        DeboogeyDiffsplitterLauncherMenu(
            openDocument: DiffsplitterNavigation.chooseDocumentLegacy,
            createDocument: { DiffsplitterNavigation.openLegacy(documentAt: nil) }
        )
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
        EntityTrackerLauncherButton {
            openWindow(id: "entity-tracker")
        }
    }
}

private struct SettingsLauncher: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernSettingsLauncher()
        } else {
            LauncherButton(
                title: PersistentVariables.settingsDisplayTitle(),
                icon: "gear",
                color: .gray
            ) {
                if #available(macOS 13.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
        }
    }
}

@available(macOS 14.0, *)
private struct ModernSettingsLauncher: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        LauncherButton(
            title: PersistentVariables.settingsDisplayTitle(),
            icon: "gear",
            color: .gray
        ) {
            openWindow(id: "settings")
        }
    }
}
#endif

#Preview {
    RootView()
}
