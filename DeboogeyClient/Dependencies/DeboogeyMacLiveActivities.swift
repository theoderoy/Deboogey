//
//  DeboogeyMacLiveActivities.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 12/11/2026.
//

import Foundation
#if DEBOOGEY_MAC_LIVE_ACTIVITIES
import ActivityKit
import os
#endif

enum DeboogeyMacLiveActivities {
#if DEBOOGEY_MAC_LIVE_ACTIVITIES
    private static let logger = Logger(subsystem: "theoderoy.Deboogey", category: "LiveActivity")
    private static let successDismissalDelay: TimeInterval = 5
    private static let lastAppexStampKey = "theoderoy.Deboogey.LiveActivity.lastAppexStamp"
    private static let extensionProcessNames = [
        "DeboogeyLiveActivity",
        "DeboogeyLiveActivityMCE"
    ]

    static func logRequestFailure(_ label: String, error: Error) {
        logger.error("\(label) Activity.request failed: \(error.localizedDescription, privacy: .public)")
    }

    static func bounceExtensionIfBundleReplaced(defaults: UserDefaults = .standard) {
        let stamp = embeddedLiveActivityAppexStamp()
        let previous = defaults.double(forKey: lastAppexStampKey)
        defaults.set(stamp, forKey: lastAppexStampKey)
        guard previous > 0, stamp > 0, abs(previous - stamp) > 0.5 else { return }
        logger.info("Live Activity appex changed; terminating stale extension processes")
        terminateExtensionProcesses()
    }

    private static func embeddedLiveActivityAppexStamp() -> TimeInterval {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: plugins,
                includingPropertiesForKeys: [.contentModificationDateKey]
              )
        else { return 0 }
        return contents
            .filter { $0.pathExtension == "appex" && $0.lastPathComponent.contains("LiveActivity") }
            .compactMap {
                try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate?
                    .timeIntervalSince1970
            }
            .max() ?? 0
    }

    static func terminateExtensionProcesses() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = extensionProcessNames
        try? process.run()
        process.waitUntilExit()
    }

    @available(macOS 27.3, *)
    static func endExisting() async {
        for existing in Activity<DiffsplitterActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        for existing in Activity<LoupeMachineActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }

    @available(macOS 27.3, *)
    static func request<A: ActivityAttributes>(
        attributes: A,
        state: A.ContentState,
        failureLabel: String
    ) async -> Activity<A>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        await endExisting()
        do {
            return try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            logRequestFailure(failureLabel, error: error)
            return nil
        }
    }

    @available(macOS 27.3, *)
    static func publishUpdate<A: ActivityAttributes>(_ activity: Activity<A>, state: A.ContentState) {
        Task { @MainActor in
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    @available(macOS 27.3, *)
    static func publishEnd<A: ActivityAttributes>(
        _ activity: Activity<A>,
        success: Bool,
        successState: A.ContentState?
    ) {
        Task { @MainActor in
            if success, let successState {
                await activity.end(
                    ActivityContent(state: successState, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(successDismissalDelay))
                )
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
#endif
}
