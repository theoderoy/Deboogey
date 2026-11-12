//
//  LoupeMachineActivityWidget.swift
//  DeboogeyLiveActivity
//
//  Created by Théo De Roy on 11/11/2026.
//

#if DEBOOGEY_MAC_LIVE_ACTIVITIES
import ActivityKit
import SwiftUI
import WidgetKit

struct LoupeMachineActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoupeMachineActivityAttributes.self) { context in
            LoupeMachineActivityExpandedView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LoupeMachineActivityIcon()
                        .accessibilityLabel(context.attributes.label)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.label)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityLabel(context.attributes.label)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status)
                        .font(.caption)
                        .lineLimit(2)
                        .accessibilityLabel(context.state.status)
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                HStack(spacing: 8) {
                    LoupeMachineActivityIcon()
                    LoupeMachineActivityCount(indexedItemCount: context.state.indexedItemCount)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(context.state.status)
            } minimal: {
                LoupeMachineActivityCount(indexedItemCount: context.state.indexedItemCount)
                    .accessibilityLabel(context.state.status)
            }
            .contentMargins(.horizontal, 12, for: .compactTrailing)
            .contentMargins(.horizontal, 8, for: .minimal)
        }
    }
}

private struct LoupeMachineActivityExpandedView: View {
    let context: ActivityViewContext<LoupeMachineActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LoupeMachineActivityIcon(prominent: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.label)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            LoupeMachineActivityCount(indexedItemCount: context.state.indexedItemCount, prominent: true)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

private struct LoupeMachineActivityIcon: View {
    var prominent = false

    var body: some View {
        Image(systemName: "loupe")
            .font(.system(size: prominent ? 22 : 14, weight: .regular))
            .frame(width: prominent ? 22 : 14, height: prominent ? 28 : 18)
    }
}

private struct LoupeMachineActivityCount: View {
    let indexedItemCount: Int
    var prominent = false

    var body: some View {
        Text(indexedItemCount, format: .number)
            .font(prominent ? .title2.weight(.semibold).monospacedDigit() : .body.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
#endif
