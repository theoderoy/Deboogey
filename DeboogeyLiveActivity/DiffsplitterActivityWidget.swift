//
//  DiffsplitterActivityWidget.swift
//  DeboogeyLiveActivity
//
//  Created by Théo De Roy on 11/11/2026.
//

#if DEBOOGEY_MAC_LIVE_ACTIVITIES
import ActivityKit
import SwiftUI
import WidgetKit

struct DiffsplitterActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiffsplitterActivityAttributes.self) { context in
            DiffsplitterActivityExpandedView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DiffsplitterActivityIcon()
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
                    DiffsplitterActivityIcon()
                    DiffsplitterActivityProgress(fraction: context.state.fractionCompleted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(context.state.status)
            } minimal: {
                DiffsplitterActivityIcon()
                    .accessibilityLabel(context.attributes.label)
            }
            .contentMargins(.horizontal, 12, for: .compactTrailing)
            .contentMargins(.horizontal, 8, for: .minimal)
        }
    }
}

private struct DiffsplitterActivityExpandedView: View {
    let context: ActivityViewContext<DiffsplitterActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            DiffsplitterActivityIcon(prominent: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.label)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                ProgressView(value: min(max(context.state.fractionCompleted, 0), 1))
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

private struct DiffsplitterActivityIcon: View {
    var prominent = false

    private static let glyphAspect = 60.06 / 99.9

    var body: some View {
        let height: CGFloat = prominent ? 22 : 14
        DiffsplitterMark()
            .fill(Color.primary, style: FillStyle(eoFill: true))
            .frame(width: height * Self.glyphAspect, height: height)
    }
}

private struct DiffsplitterMark: Shape {
    func path(in rect: CGRect) -> Path {
        let src = CGRect(x: 1419.47, y: 1041.0, width: 60.06, height: 99.9)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + (x - src.minX) / src.width * rect.width,
                y: rect.minY + (y - src.minY) / src.height * rect.height
            )
        }

        var path = Path()
        path.move(to: p(1434.31, 1041.00))
        path.addLine(to: p(1472.50, 1041.00))
        path.addLine(to: p(1474.35, 1041.49))
        path.addLine(to: p(1476.50, 1042.76))
        path.addLine(to: p(1477.97, 1044.32))
        path.addLine(to: p(1478.94, 1046.08))
        path.addLine(to: p(1479.43, 1047.93))
        path.addLine(to: p(1479.33, 1111.70))
        path.addLine(to: p(1477.97, 1116.59))
        path.addLine(to: p(1475.43, 1120.79))
        path.addLine(to: p(1472.40, 1123.81))
        path.addLine(to: p(1467.91, 1126.45))
        path.addLine(to: p(1464.78, 1127.43))
        path.addLine(to: p(1462.05, 1127.82))
        path.addLine(to: p(1434.31, 1127.82))
        path.closeSubpath()

        path.move(to: p(1441.15, 1047.45))
        path.addLine(to: p(1468.98, 1047.45))
        path.addLine(to: p(1471.23, 1048.23))
        path.addLine(to: p(1472.60, 1049.89))
        path.addLine(to: p(1472.89, 1050.86))
        path.addLine(to: p(1472.89, 1111.02))
        path.addLine(to: p(1472.21, 1113.75))
        path.addLine(to: p(1470.84, 1116.10))
        path.addLine(to: p(1468.69, 1118.15))
        path.addLine(to: p(1466.25, 1119.42))
        path.addLine(to: p(1462.93, 1120.00))
        path.addLine(to: p(1441.15, 1120.00))
        path.closeSubpath()

        path.move(to: p(1429.43, 1056.23))
        path.addLine(to: p(1429.43, 1132.60))
        path.addLine(to: p(1462.24, 1132.70))
        path.addLine(to: p(1464.59, 1132.41))
        path.addLine(to: p(1464.59, 1140.90))
        path.addLine(to: p(1426.40, 1140.90))
        path.addLine(to: p(1424.55, 1140.41))
        path.addLine(to: p(1422.40, 1139.14))
        path.addLine(to: p(1420.94, 1137.58))
        path.addLine(to: p(1419.96, 1135.82))
        path.addLine(to: p(1419.47, 1133.97))
        path.addLine(to: p(1419.47, 1070.98))
        path.addLine(to: p(1420.54, 1066.29))
        path.addLine(to: p(1422.89, 1061.90))
        path.addLine(to: p(1425.92, 1058.58))
        path.addLine(to: p(1429.43, 1056.23))
        path.closeSubpath()
        return path
    }
}

private struct DiffsplitterActivityProgress: View {
    let fraction: Double

    var body: some View {
        ProgressView(value: min(max(fraction, 0), 1))
            .progressViewStyle(.circular)
            .controlSize(.small)
    }
}
#endif
