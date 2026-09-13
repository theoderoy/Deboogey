//
//  HelperEducationHeader.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import SwiftUI

struct HelperEducationHeader: View {
    let assetName: String
    let fallbackSymbol: String
    let fallbackTitle: String
    let blurb: String

    var body: some View {
        VStack(spacing: 0) {
            Group {
#if canImport(AppKit)
                if EducationPlayerView.hasAsset(named: assetName) {
                    EducationPlayerView(assetName: assetName)
                } else {
                    fallbackMedia
                }
#else
                fallbackMedia
#endif
            }
            .aspectRatio(16.0/9.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(12)
            .padding(.horizontal)

            Text(L10n.t(blurb))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .padding(.horizontal, 32)
        }
    }

    private var fallbackMedia: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 48, weight: .thin))
                    Text(L10n.t(fallbackTitle))
                        .font(.headline)
                }
                .foregroundColor(.secondary)
            )
    }
}
