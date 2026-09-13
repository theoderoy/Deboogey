//
//  AboutView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 27/07/2026.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct AboutView: View {
    private var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var clientBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 10) {
#if canImport(AppKit)
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
#else
            Image("DeboogeyIdent")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
#endif

            Text(L10n.t("Deboogey"))
                .font(.title.bold())

            VStack(spacing: 4) {
#if DEBOOGEY_MCE
                Text(DebugVariables.VersionType.marketplaceCandidateEdition.localizedName)
#endif
                Text("\(clientVersion) \(clientBuild)")
                Spacer(minLength: 4)
                Link(L10n.t("© Théo De Roy"), destination: URL(string: "https://github.com/theoderoy")!)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(32)
#if os(macOS)
        .frame(width: 360)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }
}
