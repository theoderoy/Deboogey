//
//  AboutView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 27/07/2026.
//

import SwiftUI

struct AboutView: View {
    private var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var clientBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image("DeboogeyIdent")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)

            Text(L10n.t("Deboogey"))
                .font(.title.bold())

            VStack(spacing: 4) {
#if DEBOOGEY_MCE
                Text(DebugVariables.VersionType.marketplaceCandidateEdition.localizedName)
#endif
                Text("\(clientVersion) \(clientBuild)")
                Spacer(minLength: 4)
                Link(destination: URL(string: "https://github.com/theoderoy")!) {
                    HStack(spacing: 4) {
                        Image("theoderoyLogoIPOSF")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                        Text(L10n.t("© Théo De Roy"))
                    }
                }
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
