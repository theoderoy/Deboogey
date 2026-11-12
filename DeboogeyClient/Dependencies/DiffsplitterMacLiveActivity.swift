//
//  DiffsplitterMacLiveActivity.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 11/11/2026.
//

import Foundation
#if DEBOOGEY_MAC_LIVE_ACTIVITIES
import ActivityKit
#endif

@MainActor
enum DiffsplitterMacLiveActivity {
    final class Handle {
        private let updateImpl: (DiffsplitterIndexProgress) -> Void
        private let endImpl: (Bool) -> Void

        fileprivate init(
            update: @escaping (DiffsplitterIndexProgress) -> Void,
            end: @escaping (Bool) -> Void
        ) {
            updateImpl = update
            endImpl = end
        }

        func update(_ progress: DiffsplitterIndexProgress) {
            updateImpl(progress)
        }

        func end(success: Bool) {
            endImpl(success)
        }
    }

    static func begin(label: String, status: String) async -> Handle? {
#if DEBOOGEY_MAC_LIVE_ACTIVITIES
        guard #available(macOS 27.3, *) else { return nil }
        return await beginOnCurrentSystem(label: label, status: status)
#else
        _ = label
        _ = status
        return nil
#endif
    }

#if DEBOOGEY_MAC_LIVE_ACTIVITIES
    @available(macOS 27.3, *)
    private static func beginOnCurrentSystem(label: String, status: String) async -> Handle? {
        let state = DiffsplitterActivityAttributes.ContentState(status: status, fractionCompleted: 0)
        guard let activity = await DeboogeyMacLiveActivities.request(
            attributes: DiffsplitterActivityAttributes(label: label),
            state: state,
            failureLabel: "Diffsplitter"
        ) else { return nil }
        return Handle(
            update: { progress in
                DeboogeyMacLiveActivities.publishUpdate(
                    activity,
                    state: DiffsplitterActivityAttributes.ContentState(
                        status: progress.status,
                        fractionCompleted: progress.fractionCompleted
                    )
                )
            },
            end: { success in
                let successState = DiffsplitterActivityAttributes.ContentState(
                    status: activity.content.state.status,
                    fractionCompleted: 1
                )
                DeboogeyMacLiveActivities.publishEnd(
                    activity,
                    success: success,
                    successState: success ? successState : nil
                )
            }
        )
    }
#endif
}
