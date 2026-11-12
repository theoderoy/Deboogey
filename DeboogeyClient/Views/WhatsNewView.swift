//
//  WhatsNewView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 01/02/2026.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct WhatsNewView: View {
    let onDismiss: () -> Void

    private let entries: [WhatsNewEntry] = [
        WhatsNewEntry(
            scope: .unified,
            title: "Architecture",
            description: "Starting from Release 9 and Internal 31, Deboogey will no longer support Intel-based Macs.",
            variant: .notice
        ),
        WhatsNewEntry(
            scope: .unified,
            icon: "hand.wave",
            color: .accentColor,
            title: "PlaceholderText1",
            description: "PlaceholderText2"
        ),
    ]

    private var versionHeading: String {
        #if DEBOOGEY_MCE
        let version = shortVersion
        #else
        let version = (shortVersion.isEmpty ? "" : shortVersion)
            + (buildNumber.isEmpty ? "" : shortVersion.isEmpty ? buildNumber : " \(buildNumber)")
        #endif
        return L10n.f("What's changed in %@", version)
    }

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
#if canImport(AppKit)
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 128)
                }
#else
                Image("DeboogeyIdent")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
#endif

                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DeboogeyClient")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(versionHeading)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
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
#if os(macOS)
        .frame(width: 500)
#else
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
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

private enum WhatsNewEntryVariant {
    case standard
    case notice
}

private struct WhatsNewEntry: Identifiable {
    let scope: WhatsNewEntryScope
    let icon: String
    let color: Color
    let title: String
    let description: String
    let variant: WhatsNewEntryVariant

    var id: String { title }
    var isNotice: Bool { variant == .notice }

    init(
        scope: WhatsNewEntryScope,
        icon: String = "exclamationmark.triangle.fill",
        color: Color = .yellow,
        title: String,
        description: String,
        variant: WhatsNewEntryVariant = .standard
    ) {
        self.scope = scope
        self.icon = icon
        self.color = color
        self.title = title
        self.description = description
        self.variant = variant
    }
}

private struct ContinueButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.t(title))
                .deboogeyOnboardingButtonLabel()
        }
        .deboogeyProminentButtonStyle(tint: color)
    }
}


private struct FeatureRow: View {
    let entry: WhatsNewEntry

    private var usesAssetIcon: Bool {
        guard !entry.isNotice else { return false }
#if canImport(AppKit)
        return NSImage(named: entry.icon) != nil
#else
        return UIImage(named: entry.icon) != nil
#endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Group {
                if usesAssetIcon {
                    Image(entry.icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .foregroundColor(entry.color)
                } else {
                    Image(systemName: entry.icon)
                        .font(.system(size: 30))
                        .foregroundColor(entry.color)
                }
            }
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
        .padding(.horizontal, entry.isNotice ? 12 : 0)
        .padding(.vertical, entry.isNotice ? 8 : 0)
        .background {
            if entry.isNotice {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.yellow.opacity(0.12))
            }
        }
    }
}

#Preview {
    WhatsNewView(onDismiss: {})
}
