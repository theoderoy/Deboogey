//
//  DeboogeyLiveActivityBundle.swift
//  DeboogeyLiveActivity
//
//  Created by Théo De Roy on 11/11/2026.
//

import SwiftUI
import WidgetKit

@main
struct DeboogeyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
#if DEBOOGEY_MAC_LIVE_ACTIVITIES
        DiffsplitterActivityWidget()
        LoupeMachineActivityWidget()
#else
        DeboogeyLiveActivityStubWidget()
#endif
    }
}

#if !DEBOOGEY_MAC_LIVE_ACTIVITIES
private struct DeboogeyLiveActivityStubEntry: TimelineEntry {
    let date: Date
}

private struct DeboogeyLiveActivityStubProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeboogeyLiveActivityStubEntry {
        DeboogeyLiveActivityStubEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (DeboogeyLiveActivityStubEntry) -> Void) {
        completion(DeboogeyLiveActivityStubEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeboogeyLiveActivityStubEntry>) -> Void) {
        completion(Timeline(entries: [DeboogeyLiveActivityStubEntry(date: Date())], policy: .never))
    }
}

private struct DeboogeyLiveActivityStubWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DeboogeyLiveActivityStub", provider: DeboogeyLiveActivityStubProvider()) { _ in
            EmptyView()
        }
        .configurationDisplayName("Deboogey")
        .description("Deboogey")
        .supportedFamilies([.systemSmall])
    }
}
#endif
