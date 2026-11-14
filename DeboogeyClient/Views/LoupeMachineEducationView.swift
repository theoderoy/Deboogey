//
//  LoupeMachineEducationView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 27/07/2026.
//

import SwiftUI

struct LoupeMachineEducationView: View {
    var title: String? = nil
    var explanation: String? = nil
    let onDismiss: () -> Void

    @StateObject private var vars = PersistentVariables()
    @State private var step = 0

    private var includesLiveActivityStep: Bool {
        IndexCompletionFeedback.usesLiveActivityUX
    }

    private var stepCount: Int {
        includesLiveActivityStep ? 2 : 1
    }

    private var resolvedTitle: String {
        if let title { return title }
#if os(iOS)
        return L10n.t("Loupe View")
#else
        return L10n.t("Loupe Machine")
#endif
    }

    private var resolvedExplanation: String {
        if let explanation { return explanation }
#if os(iOS)
        return L10n.t("Loupe View lets you open Loupe Machine documents on iPhone, iPad, and Apple Vision, inspect and edit their flags, and prepare a change set to apply elsewhere.")
#elseif DEBOOGEY_MCE
        return L10n.t("Loupe Machine lets you select an application, discover binary preference flags, inspect and edit them, and prepare a change set to apply elsewhere.")
#else
        return L10n.t("Loupe Machine lets you select an application, discover its system-modifiable flags, and inspect or edit them.")
#endif
    }

    var body: some View {
        VStack(spacing: includesLiveActivityStep ? 24 : 30) {
            Group {
                switch step {
                case 0:
                    introStep
                default:
                    liveActivityStep
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: includesLiveActivityStep ? .infinity : nil,
                alignment: .top
            )

            if includesLiveActivityStep {
                pageIndicators
            }

            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        go(to: step - 1)
                    } label: {
                        Text(L10n.t("Back"))
                            .deboogeyOnboardingButtonLabel()
                    }
                    .deboogeyButtonStyle(tint: .accentColor)
                }

                ActionButton(title: L10n.t("Continue"), color: .accentColor) {
                    if step < stepCount - 1 {
                        go(to: step + 1)
                    } else {
                        onDismiss()
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .padding(.top, 40)
#if os(macOS)
        .frame(width: includesLiveActivityStep ? 520 : 500, height: includesLiveActivityStep ? 520 : nil)
#else
        .frame(maxWidth: includesLiveActivityStep ? 520 : 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }

    private var introStep: some View {
        VStack(spacing: 8) {
            Image("LoupeMachineIdent")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)
                .padding(.bottom, 12)

            Text(resolvedTitle)
                .font(.title2)
                .fontWeight(.medium)

            Text(resolvedExplanation)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.top, 20)
        }
    }

    private var liveActivityStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: IndexCompletionFeedback.completionNotifySymbolName)
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text(IndexCompletionFeedback.completionNotifyTitle)
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(IndexCompletionFeedback.completionNotifyCaption)
                    .padding(.top, 12)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("", isOn: $vars.playIndexingDoneSound)
                .labelsHidden()
                .toggleStyle(.switch)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private func go(to newStep: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            step = newStep
        }
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: index == step ? 8 : 6, height: index == step ? 8 : 6)
                    .accessibilityLabel(L10n.f("Step %d of %d", index + 1, stepCount))
                    .accessibilityAddTraits(index == step ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.f("Step %d of %d", step + 1, stepCount))
    }
}

private struct ActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .deboogeyOnboardingButtonLabel()
        }
        .deboogeyProminentButtonStyle(tint: color)
    }
}

#Preview {
    LoupeMachineEducationView(onDismiss: {})
}
