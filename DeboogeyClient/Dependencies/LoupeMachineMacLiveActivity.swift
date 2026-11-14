//
//  LoupeMachineMacLiveActivity.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 11/11/2026.
//

import Combine
import Foundation
#if DEBOOGEY_MAC_LIVE_ACTIVITIES
import ActivityKit
#endif

@MainActor
enum LoupeMachineMacLiveActivity {
    final class Handle {
        private let updateImpl: (String, Int) -> Void
        private let endImpl: (Bool, String?) -> Void

        fileprivate init(
            update: @escaping (String, Int) -> Void,
            end: @escaping (Bool, String?) -> Void
        ) {
            updateImpl = update
            endImpl = end
        }

        func update(status: String, indexedItemCount: Int) {
            updateImpl(status, indexedItemCount)
        }

        func end(success: Bool, status: String?) {
            endImpl(success, status)
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
        let state = LoupeMachineActivityAttributes.ContentState(status: status, indexedItemCount: 0)
        guard let activity = await DeboogeyMacLiveActivities.request(
            attributes: LoupeMachineActivityAttributes(label: label),
            state: state,
            failureLabel: "Loupe Machine"
        ) else { return nil }
        return Handle(
            update: { status, indexedItemCount in
                DeboogeyMacLiveActivities.publishUpdate(
                    activity,
                    state: LoupeMachineActivityAttributes.ContentState(
                        status: status,
                        indexedItemCount: indexedItemCount
                    )
                )
            },
            end: { success, status in
                let successState = LoupeMachineActivityAttributes.ContentState(
                    status: status ?? activity.content.state.status,
                    indexedItemCount: activity.content.state.indexedItemCount
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

@MainActor
final class LoupeIndexActivity: ObservableObject {
    private var handle: LoupeMachineMacLiveActivity.Handle?
    private var generation: UInt64 = 0

    func begin(applicationName: String) async {
        generation &+= 1
        let generation = generation
        handle?.end(success: false, status: nil)
        handle = nil
        guard IndexCompletionFeedback.usesLiveActivityUX, IndexCompletionFeedback.isEnabled else { return }
        let newHandle = await LoupeMachineMacLiveActivity.begin(
            label: L10n.t("Loupe Machine"),
            status: L10n.f("Inspecting %@…", applicationName)
        )
        guard generation == self.generation else {
            newHandle?.end(success: false, status: nil)
            return
        }
        handle = newHandle
    }

    func update(flagCount: Int) {
        handle?.update(
            status: L10n.f("%d flag(s) found", flagCount),
            indexedItemCount: flagCount
        )
    }

    @discardableResult
    func end(success: Bool, status: String?) -> Bool {
        generation &+= 1
        let showedActivity = handle != nil
        handle?.end(success: success, status: status)
        handle = nil
        return showedActivity
    }
}
