//
//  WindowLauncherCommands.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 08/08/2026.
//

import SwiftUI

struct LegacyWindowLauncherCommands: Commands {
    let openMain: () -> Void
    var openCocoaDebugMenu: (() -> Void)?
    var openSkyLightDiagnostics: (() -> Void)?
    var skyLightDiagnosticsDisabled = false

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(action: openMain) {
                Label(L10n.t("Deboogey"), systemImage: "macwindow")
            }

            Button {
                LoupeMachineNavigation.openLegacy(documentAt: nil)
            } label: {
                Label(L10n.t("Loupe Machine"), systemImage: "scope")
            }

            Button {
                DiffsplitterNavigation.openLegacy(documentAt: nil)
            } label: {
                Label {
                    Text(L10n.t("Diffsplitter"))
                } icon: {
                    Image("DiffsplitterIconIPOSF")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            }

            if let openCocoaDebugMenu {
                Button(action: openCocoaDebugMenu) {
                    Label(L10n.t("Cocoa Debug Menu"), systemImage: "wrench.and.screwdriver")
                }
            }

            if let openSkyLightDiagnostics {
                Button(action: openSkyLightDiagnostics) {
                    Label(L10n.t("SkyLight Diagnostics"), systemImage: "macwindow")
                }
                    .disabled(skyLightDiagnosticsDisabled)
            }
        }
    }
}

@available(macOS 13.0, *)
struct WindowLauncherCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let openMain: () -> Void
    var includesCocoaDebugMenu = false
    var includesSkyLightDiagnostics = false
    var skyLightDiagnosticsDisabled = false

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(L10n.t("Deboogey"), systemImage: "macwindow", action: openMain)

            Button(L10n.t("Loupe Machine"), systemImage: "scope") {
                LoupeMachineNavigation.open(documentAt: nil, using: openWindow)
            }

            Button {
                DiffsplitterNavigation.open(documentAt: nil, using: openWindow)
            } label: {
                Label {
                    Text(L10n.t("Diffsplitter"))
                } icon: {
                    Image("DiffsplitterIconIPOSF")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            }

            if includesCocoaDebugMenu {
                Button(L10n.t("Cocoa Debug Menu"), systemImage: "wrench.and.screwdriver") {
                    openWindow(id: "deboogey-cdm-launcher")
                }
            }

            if includesSkyLightDiagnostics {
                Button(L10n.t("SkyLight Diagnostics"), systemImage: "macwindow") {
                    openWindow(id: "deboogey-sd-launcher")
                }
                .disabled(skyLightDiagnosticsDisabled)
            }
        }
    }
}
