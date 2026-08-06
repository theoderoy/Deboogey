//
//  WhatsNewView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 01/02/2026.
//

import SwiftUI

struct WhatsNewView: View {
    let onDismiss: () -> Void

    private let entries: [WhatsNewEntry] = [
        WhatsNewEntry(
            scope: .MCEOnly,
            icon: "wrench.and.screwdriver",
            color: .accentColor,
            title: "Cocoa Debug Menu",
            description: "Play around with the sandbox parameters of Deboogey using Apple's own built-in tool."
        ),
        WhatsNewEntry(
            scope: .unified,
            icon: "loupe",
            color: .blue,
            title: "Updates to Loupe Machine",
            description: "You are now equipped with a search bar to look up any flags, along with a new 'All' category."
        ),
        WhatsNewEntry(
            scope: .unified,
            icon: "ladybug",
            color: .red,
            title: "Bug Fixes",
            description: "Fixed an issue where the 'Window' menu bar entry would have inaccurate items in some versions of Deboogey."
        )
    ]

    private var versionHeading: String {
        let version = (shortVersion.isEmpty ? "" : shortVersion)
            + (buildNumber.isEmpty
                ? "" : shortVersion.isEmpty ? buildNumber : " \(buildNumber)")
        return L10n.f("What's changed in %@", version)
    }

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 128)
                }
                
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DeboogeyClient")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(versionHeading)
                    .font(.title2)
                    .fontWeight(.medium)
            }
            .padding(.top, 40)
            
            VStack(alignment: .leading, spacing: 25) {
                ForEach(entries.filter(\.scope.isVisible)) { entry in
                    FeatureRow(entry: entry)
                }
            }
            .padding(.horizontal, 40)
            
            ContinueButton(title: "Continue", color: .accentColor, action: onDismiss)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
        .frame(width: 500)
    }
}

private enum WhatsNewEntryScope {
    case unified
    case regularOnly
    case MCEOnly

    var isVisible: Bool {
        switch self {
        case .unified:
            true
        case .regularOnly:
            !DebugVariables.isMarketplaceCandidateEditionBuild
        case .MCEOnly:
            DebugVariables.isMarketplaceCandidateEditionBuild
        }
    }
}

private struct WhatsNewEntry: Identifiable {
    let scope: WhatsNewEntryScope
    let icon: String
    let color: Color
    let title: String
    let description: String

    var id: String { title }
}

private struct ContinueButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.t(title))
                .font(.headline)
                .padding(8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .continueButtonStyle(tint: color)
    }
}

private extension View {
    @ViewBuilder
    func continueButtonStyle(tint color: Color) -> some View {
        if #available(macOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(color)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.large)
                .tint(color)
        }
    }
}

private struct FeatureRow: View {
    let entry: WhatsNewEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: entry.icon)
                .font(.system(size: 30))
                .foregroundColor(entry.color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t(entry.title))
                    .font(.headline)
                
                Text(L10n.t(entry.description))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WhatsNewView(onDismiss: {})
}
