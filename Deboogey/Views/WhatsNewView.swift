//
//  WhatsNewView.swift
//  Deboogey
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
                
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Deboogey")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(
                    "What's changed in "
                        + (shortVersion.isEmpty ? "" : "\(shortVersion)")
                        + (buildNumber.isEmpty
                            ? "" : shortVersion.isEmpty ? "\(buildNumber)" : " \(buildNumber)")
                )
                .font(.title2)
                .fontWeight(.medium)
            }
            .padding(.top, 40)
            
            VStack(alignment: .leading, spacing: 25) {
                FeatureRow(
                    icon: "exclamationmark.triangle",
                    color: .yellow,
                    title: "Support",
                    description: "Release 3.1 and Internal 14 are the final Deboogey releases that will support macOS Big Sur."
                )
                
                FeatureRow(
                    icon: "ladybug",
                    color: .red,
                    title: "Bug Fixes",
                    description: "Addressed an issue where Entity Tracker would not properly take care of deleting ephemeral entries if this was preconfigured by the user to happen automatically."
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()

            Button(action: onDismiss) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 500, height: 600)
    }
}

struct FeatureRow: View {
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
                Text(title)
                    .font(.headline)
                
                Text(description)
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
