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
#if os(macOS)
    @State private var contentHeight: CGFloat = 0
#endif

    private var entries: [WhatsNewEntry] {
        var entries = [
            WhatsNewEntry(
                scope: .macOnly,
                title: "Architecture",
                description: "Starting from Release 9 and Internal 31, Deboogey will no longer support Intel-based Macs.",
                variant: .notice
            ),
            WhatsNewEntry(
                scope: .diffsplitterEligible,
                icon: "archivebox",
                color: .accentColor,
                title: "Diffsplitter Batch",
                description: "Compare two folders or archives into a self-contained Diffsplitter Batch you can reopen later without the original sides, and save time using the new Batch Composer. Diffsplitter also now behaves more consistently across iPhone, iPad, and Apple Vision."
            ),
        ]
        if let liveActivitiesEntry { entries.append(liveActivitiesEntry) }
        entries.append(
            WhatsNewEntry(
                scope: .unified,
                icon: "flag",
                color: .accentColor,
                title: "Localisation",
                description: "Deboogey now supports displaying itself in Dutch. Visibility will depend on the system language to simplify user experience."
            )
        )
        entries.append(
            WhatsNewEntry(
                scope: .unified,
                icon: "info.circle",
                color: .accentColor,
                title: "Improvements",
                description: "Document type icons have been redesigned, you can now open all Deboogey document types through one picker and In-App Tones and completion feedback have been unified."
            )
        )
        return entries
    }

    private var liveActivitiesEntry: WhatsNewEntry? {
#if os(macOS)
        guard #available(macOS 27.3, *) else { return nil }
        return WhatsNewEntry(
            scope: .macOnly,
            icon: "platter.filled.top.and.arrow.up.iphone",
            color: .accentColor,
            title: "Live Activities",
            description: "Loupe Machine indexing and Diffsplitter comparisons can now stay visible on Mac with Live Activities, so long-running work remains glanceable while Deboogey is in the background."
        )
#else
        nil
#endif
    }

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
#if os(macOS)
        Group {
            if contentHeight > macSheetMaxHeight {
                ScrollView { whatsNewContent }
                    .frame(height: macSheetMaxHeight)
            } else {
                whatsNewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(width: 500)
        .background {
            whatsNewContent
                .frame(width: 500)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WhatsNewContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .onPreferenceChange(WhatsNewContentHeightKey.self) { contentHeight = $0 }
#else
        GeometryReader { geometry in
            ScrollView {
                whatsNewContent
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }

    private var whatsNewContent: some View {
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

            VStack(alignment: .leading, spacing: 25) {
                ForEach(entries.filter(\.scope.isVisible)) { entry in
                    FeatureRow(entry: entry)
                }
            }
            .padding(.horizontal, 40)

            ContinueButton(title: "Continue", color: .accentColor, action: onDismiss)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

#if os(macOS)
    private var macSheetMaxHeight: CGFloat {
        max(420, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
    }
#endif
}

#if os(macOS)
private enum WhatsNewContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#endif

private enum WhatsNewEntryScope {
    case unified, regularOnly, MCEOnly, macOnly, diffsplitterEligible

    var isVisible: Bool {
        switch self {
        case .unified: true
        case .regularOnly: !DebugVariables.isMarketplaceCandidateEditionBuild
        case .MCEOnly: DebugVariables.isMarketplaceCandidateEditionBuild
        case .macOnly:
#if os(macOS)
            true
#else
            false
#endif
        case .diffsplitterEligible:
#if os(macOS)
            true
#elseif os(iOS)
            MCEIOSFeatureSupport.diffsplitter
#else
            false
#endif
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
