//
//  WhatsNewView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 01/02/2026.
//

import SwiftUI

struct WhatsNewView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                }
                
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DeboogeyClient")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(
                    L10n.f(
                        "What's changed in %@",
                        (shortVersion.isEmpty ? "" : "\(shortVersion)")
                            + (buildNumber.isEmpty
                                ? "" : shortVersion.isEmpty ? "\(buildNumber)" : " \(buildNumber)")
                    )
                )
                .font(.title2)
                .fontWeight(.medium)
            }
            .padding(.top, 40)
            
            VStack(alignment: .leading, spacing: 25) {
                FeatureRow(
                    icon: "exclamationmark.triangle.fill",
                    color: .yellow,
                    title: "Compatibility",
                    description: "Release 4 and Internal 15 or later require macOS Monterey or later."
                )
                
                FeatureRow(
                    icon: "flag.fill",
                    color: .accentColor,
                    title: "Localisation",
                    description: "Deboogey now supports displaying itself in French. Visibility will depend on the system language to simplify user experience."
                )
                
                FeatureRow(
                    icon: "info.circle.fill",
                    color: .blue,
                    title: "Improvements",
                    description: "Mainly focused on stability and faster performance across the board. Configuration has been laid out better."
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()

            ContinueButton(title: "Continue", color: .accentColor, action: onDismiss)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
        .frame(width: 500, height: 600)
    }
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
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t(title))
                    .font(.headline)
                
                Text(L10n.t(description))
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
