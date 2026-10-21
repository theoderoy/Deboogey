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
