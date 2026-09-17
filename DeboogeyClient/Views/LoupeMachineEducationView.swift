//
//  LoupeMachineEducationView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 27/07/2026.
//

import SwiftUI

struct LoupeMachineEducationView: View {
    var title: String = L10n.t("Loupe Machine")
    var explanation: String? = nil
    let onDismiss: () -> Void

    private var resolvedExplanation: String {
        if let explanation { return explanation }
#if DEBOOGEY_MCE
        return L10n.t("Loupe Machine lets you select an application, discover binary preference flags, inspect and edit them, and prepare a change set to apply elsewhere.")
#else
        return L10n.t("Loupe Machine lets you select an application, discover its system-modifiable flags, and inspect or edit them.")
#endif
    }

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Image("LoupeMachineIdent")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .padding(.bottom, 12)

                Text(title)
                    .font(.title2)
                    .fontWeight(.medium)

                Text(resolvedExplanation)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
            }
            .padding(.top, 40)
            
            ActionButton(title: L10n.t("Continue"), color: .accentColor, action: onDismiss)
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
