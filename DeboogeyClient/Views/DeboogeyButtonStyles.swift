//
//  DeboogeyButtonStyles.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import SwiftUI

extension View {
    @ViewBuilder
    func deboogeyButtonStyle(tint color: Color, prominent: Bool = false) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if prominent {
                self
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(color)
            } else {
                self
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(color)
            }
        } else if prominent {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.large)
                .tint(color)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.large)
                .tint(color)
        }
    }

    func deboogeyProminentButtonStyle(tint color: Color = .accentColor) -> some View {
        deboogeyButtonStyle(tint: color, prominent: true)
    }
}

struct DeboogeyPriorityListScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollDisabled(true)
        } else {
            content
        }
    }
}
