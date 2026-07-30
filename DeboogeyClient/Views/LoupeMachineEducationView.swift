//
//  LoupeMachineEducationView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 27/07/2026.
//

import SwiftUI

struct LoupeMachineEducationView: View {
    let onDismiss: () -> Void

    private var explanation: String {
#if DEBOOGEY_MCE
        L10n.t("Loupe Machine lets you select an application, discover binary preference flags, inspect and edit them, and prepare a change set to apply elsewhere.")
#else
        L10n.t("Loupe Machine lets you select an application, discover its system-modifiable flags, and inspect or edit them.")
#endif
    }

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Image("LoupeMachineIdent")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)

                HStack(spacing: 6) {
                    Text(L10n.t("Loupe Machine"))
                        .font(.title2)
                        .fontWeight(.medium)

                    Text(L10n.t("BETA"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }

                Text(explanation)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
            }
            .padding(.top, 40)
            
            ActionButton(title: L10n.t("Continue"), color: .accentColor, action: onDismiss)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
        .frame(width: 500)
    }
}

private struct ActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding(8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .ActionButtonStyle(tint: color)
    }
}

private extension View {
    @ViewBuilder
    func ActionButtonStyle(tint color: Color) -> some View {
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

#Preview {
    LoupeMachineEducationView(onDismiss: {})
}
