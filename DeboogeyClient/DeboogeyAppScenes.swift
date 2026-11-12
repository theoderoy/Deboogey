//
//  DeboogeyAppScenes.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 15/10/2026.
//

import SwiftUI

#if os(macOS)

struct DeboogeyRootContentView: View {
    @ViewBuilder
    var body: some View {
        rootView
            .modifier(RootLauncherSceneChrome())
    }

    @ViewBuilder
    private var rootView: some View {
        if #available(macOS 13.0, *) {
            RootView().modifier(ExternalDocumentWindowHandler())
        } else {
            RootView().modifier(ExternalDocumentHandler(
                openLoupe: { LegacyDocumentRoutes.openLoupe($0) },
                openDiffsplitter: { LegacyDocumentRoutes.openDiffsplitter($0) }
            ))
        }
    }
}

enum DeboogeyLegacyRootLaunch {
    static func openIfNeeded(_ open: @escaping () -> Void) {
        if #unavailable(macOS 13.0) {
            DispatchQueue.main.async(execute: open)
        }
    }
}

enum DeboogeyRootNavigation {
    static let windowID = "deboogey-root"

    @available(macOS 13.0, *)
    static func open(using openWindow: OpenWindowAction) {
        openWindow(id: windowID)
    }
}

@available(macOS 13.0, *)
struct DeboogeyRootWindowScene<Content: View>: Scene {
    @ViewBuilder var content: () -> Content

    var body: some Scene {
        Window(appName ?? "Deboogey", id: DeboogeyRootNavigation.windowID) {
            content()
        }
        .deboogeyRootWindowPlacement()
    }
}

private struct RootLauncherSceneChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.windowFullScreenBehavior(.disabled)
        } else {
            content
        }
    }
}
@available(macOS 13.0, *)
struct DeboogeyLoupeDocumentCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        DocumentToolCommandSet(
            createLoupeDocument: { LoupeMachineNavigation.open(documentAt: nil, using: openWindow) },
            createDiffsplitterDocument: { DiffsplitterNavigation.open(documentAt: nil, using: openWindow) },
            openDocument: {
                DocumentOpenPanel.chooseDeboogeyDocument(
                    openLoupe: { DocumentWindowRoutes.openLoupe($0, using: openWindow) },
                    openDiffsplitter: { DocumentWindowRoutes.openDiffsplitter($0, using: openWindow) }
                )
            },
            openMain: { DeboogeyRootNavigation.open(using: openWindow) }
        )
    }
}

@available(macOS 13.0, *)
private struct DeboogeyLoupeWindowGroup: Scene {
    var body: some Scene {
        WindowGroup(
            L10n.t("Loupe Machine"),
            id: LoupeMachineNavigation.windowID,
            for: LoupeMachineWindowRequest.self
        ) { $request in
            NavigationStack {
                LoupeMachineView(request: request)
            }
            .environment(\.locale, L10n.locale)
        } defaultValue: {
            LoupeMachineWindowRequest(action: .create)
        }
        .deboogeyWindowPlacement(AppWindowSizing.loupeMachine)
        .windowResizability(.contentMinSize)
    }
}

@available(macOS 13.0, *)
struct DeboogeyLoupeScene: Scene {
    var body: some Scene {
        DeboogeyLoupeWindowGroup().commandsRemoved()
    }
}

@available(macOS 13.0, *)
struct DeboogeyLoupeCommandsScene: Scene {
    var body: some Scene {
        DeboogeyLoupeWindowGroup().commands {
            DeboogeyLoupeDocumentCommands()
        }
    }
}

@available(macOS 13.0, *)
struct DeboogeyDiffsplitterScene: Scene {
    var body: some Scene {
        WindowGroup(
            L10n.t("Diffsplitter"),
            id: DiffsplitterNavigation.windowID,
            for: DiffsplitterWindowRequest.self
        ) { $request in
            DiffsplitterView(request: request)
                .environment(\.locale, L10n.locale)
        } defaultValue: {
            DiffsplitterWindowRequest(action: .create)
        }
        .commandsRemoved()
        .deboogeyWindowPlacement(AppWindowSizing.diffsplitter)
        .windowResizability(.contentMinSize)
    }
}

@available(macOS 13.0, *)
struct DeboogeyCDMLauncherScene: Scene {
    var body: some Scene {
        Window(L10n.t("Cocoa Debug Menu"), id: "deboogey-cdm-launcher") {
            NavigationStack {
                DeboogeyCDMLauncherView { arguments in
                    EntityTracker.shared.record(source: .deboogeyCDM, arguments: arguments)
                }
            }
            .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .deboogeyWindowPlacement(AppWindowSizing.cocoaDebugMenu)
        .windowResizability(.contentSize)
    }
}

#if !DEBOOGEY_MCE
@available(macOS 13.0, *)
struct DeboogeySDLauncherScene: Scene {
    let sipSatisfied: Bool

    var body: some Scene {
        Window(L10n.t("SkyLight Diagnostics"), id: "deboogey-sd-launcher") {
            NavigationStack {
                if sipSatisfied {
                    VStack(spacing: 12) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundColor(.secondary)
                        Text(L10n.t("SkyLight Diagnostics"))
                            .font(.headline)
                        Text(L10n.t("System write-dependent features have been disabled."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                } else {
                    DeboogeySDLauncherView { argument in
                        EntityTracker.shared.record(source: .wsOverlay, arguments: [argument])
                    }
                }
            }
            .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .deboogeyWindowPlacement(AppWindowSizing.skyLightDiagnostics)
        .windowResizability(.contentSize)
    }
}
#endif

@available(macOS 13.0, *)
struct EntityTrackerScene: Scene {
    var body: some Scene {
        Window(L10n.t("Entity Tracker"), id: "entity-tracker") {
            NavigationStack {
                EntityTrackerView()
            }
            .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .deboogeyWindowPlacement(AppWindowSizing.entityTracker)
        .windowResizability(.contentSize)
    }
}

@available(macOS 14.0, *)
struct ConfigurationModern: Scene {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(PersistentVariables.settingsDisplayTitle(), id: "settings") {
            ConfigurationRootView()
                .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(PersistentVariables.settingsDisplayTitle() + "...", systemImage: "gear") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .deboogeyWindowPlacement(AppWindowSizing.Configuration.modern)
        .windowResizability(.contentMinSize)
    }
}

struct ConfigurationLegacy: Scene {
    var body: some Scene {
        Settings {
            ConfigurationRootView()
                .environment(\.locale, L10n.locale)
        }
    }
}

#endif
