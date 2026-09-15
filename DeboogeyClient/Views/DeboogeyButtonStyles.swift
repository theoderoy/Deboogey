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
    @Binding var notifyWhenBackgrounded: Bool
    var showsResetButton: Bool = false
    var stacksBackgroundControls: Bool = false
    var footerUsesForegroundStyle: Bool = false

    var body: some View {
        if stacksBackgroundControls {
            VStack(alignment: .leading, spacing: 16) {
                durationSlider
#if os(iOS)
                backgroundNotifyBlock
#endif
            }
        } else {
            Group {
                durationSlider
#if os(iOS)
                Toggle(isOn: $notifyWhenBackgrounded) {
                    Text(L10n.t("Also notify immediately in the background"))
                }
                Text(L10n.t("Skips Minimum Duration during Live Activity and Background Process."))
                    .font(.subheadline)
                    .modifier(FooterForegroundModifier(useForegroundStyle: footerUsesForegroundStyle))
#endif
            }
        }
    }

    private var durationSlider: some View {
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

#if os(iOS)
    private var backgroundNotifyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $notifyWhenBackgrounded) {
                Text(L10n.t("Also notify immediately in the background"))
            }
            Text(L10n.t("Skips Minimum Duration during Live Activity and Background Process."))
                .font(.subheadline)
                .modifier(FooterForegroundModifier(useForegroundStyle: footerUsesForegroundStyle))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
#endif
}

private struct FooterForegroundModifier: ViewModifier {
    let useForegroundStyle: Bool

    func body(content: Content) -> some View {
        if useForegroundStyle {
            content.foregroundStyle(.secondary)
        } else {
            content.foregroundColor(.secondary)
        }
    }
}
