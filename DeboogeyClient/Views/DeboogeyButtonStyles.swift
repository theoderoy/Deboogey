//
//  DeboogeyButtonStyles.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import SwiftUI

enum DeboogeyButtonMetrics {
    static let standardWidth: CGFloat = 220
}

extension View {
    func deboogeyStandardButtonLabel() -> some View {
        self
            .font(.headline)
            .frame(width: DeboogeyButtonMetrics.standardWidth)
            .contentShape(Rectangle())
    }

    func deboogeyOnboardingButtonLabel() -> some View {
        self
            .font(.headline)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    func deboogeyButtonStyle(tint color: Color, prominent: Bool = false) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Group {
                if prominent { self.buttonStyle(.glassProminent) }
                else { self.buttonStyle(.glass) }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(color)
        } else {
            Group {
                if prominent { self.buttonStyle(.borderedProminent) }
                else { self.buttonStyle(.bordered) }
            }
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
#if os(macOS)
        if #available(macOS 13.0, *) {
            content.scrollDisabled(true)
        } else {
            content
        }
#else
        content.scrollDisabled(true)
#endif
    }
}

struct DiffsplitterCompletionDurationControls: View {
    @Binding var minimumSeconds: Double
    var showsResetButton: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: showsResetButton ? 8 : 12) {
            HStack {
                Text(L10n.t("Minimum Duration"))
                Spacer()
                Text(DiffsplitterCompletionFeedback.durationLabel(for: minimumSeconds))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                if showsResetButton {
                    Button {
                        minimumSeconds = DiffsplitterCompletionFeedback.defaultMinimumSeconds
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(
                        Int(minimumSeconds.rounded())
                            == Int(DiffsplitterCompletionFeedback.defaultMinimumSeconds.rounded())
                    )
                    .help(L10n.t("Reset to Default"))
                    .accessibilityLabel(L10n.t("Reset to Default"))
                }
                Slider(
                    value: Binding(
                        get: { DiffsplitterCompletionFeedback.sliderIndex(forSeconds: minimumSeconds) },
                        set: { minimumSeconds = DiffsplitterCompletionFeedback.seconds(forSliderIndex: $0) }
                    ),
                    in: DiffsplitterCompletionFeedback.sliderIndexRange,
                    step: 1
                )
            }
        }
    }
}
