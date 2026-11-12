//
//  LoupeMachineActivityAttributes.swift
//  DeboogeyLiveActivity
//
//  Created by Théo De Roy on 11/11/2026.
//

#if DEBOOGEY_MAC_LIVE_ACTIVITIES
import ActivityKit
import Foundation

struct LoupeMachineActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var indexedItemCount: Int
    }

    var label: String
}
#endif
