//
//  DiffsplitterStatusPriorityEditor.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import SwiftUI

#if os(macOS)
struct DiffsplitterStatusPriorityEditor: View {
    @Binding var order: [String]
    var onMove: ((IndexSet, Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            List {
                ForEach(Array(order.enumerated()), id: \.element) { index, raw in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Circle()
                            .fill(DiffsplitterEngine.DirEntryStatus.color(forRawValue: raw))
                            .frame(width: 10, height: 10)
                        Text(DiffsplitterEngine.DirEntryStatus.title(forRawValue: raw))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(DiffsplitterEngine.DirEntryStatus.title(forRawValue: raw))
                    .accessibilityValue(L10n.f("Priority %d", index + 1))
                }
                .onMove { source, destination in
                    if let onMove {
                        onMove(source, destination)
                    } else {
                        order.move(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            .frame(height: CGFloat(order.count) * 28)
            .listStyle(.bordered)
            .modifier(DeboogeyPriorityListScrollModifier())

            Button(L10n.t("Reset to Default")) {
                order = PersistentVariables.defaultDiffsplitterStatusPriority
            }
            .disabled(order == PersistentVariables.defaultDiffsplitterStatusPriority)
        }
    }
}
#endif
