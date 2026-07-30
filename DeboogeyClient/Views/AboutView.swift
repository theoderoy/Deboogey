//
//  AboutView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 27/07/2026.
//

import AppKit
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
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)

            Text(L10n.t("Deboogey"))
                .font(.title.bold())

            VStack(spacing: 4) {
                Text("\(clientVersion) \(clientBuild)")
                Spacer(minLength: 4)
                Link(L10n.t("© Théo De Roy"), destination: URL(string: "https://github.com/theoderoy")!)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360)
    }
}
