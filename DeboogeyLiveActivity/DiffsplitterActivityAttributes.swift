//
//  DiffsplitterActivityAttributes.swift
//  DeboogeyLiveActivity
//
//  Created by Théo De Roy on 11/11/2026.
//

#if DEBOOGEY_MAC_LIVE_ACTIVITIES
import ActivityKit
import Foundation

struct DiffsplitterActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var fractionCompleted: Double
    }

    var label: String
}
#endif
