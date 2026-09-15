//
//  DiffsplitterContinuedProcessing.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

#if os(iOS)

import BackgroundTasks
import Foundation

@MainActor
enum DiffsplitterContinuedProcessing {
    static let identifier = "theoderoy.Deboogey.MCE.diffsplitter-compare"

    final class Handle: @unchecked Sendable {
        private let task: BGContinuedProcessingTask
        private let lock = NSLock()
        private var didFinish = false
        private var lastSubtitle: String?

        init(task: BGContinuedProcessingTask, onExpire: @escaping @Sendable () -> Void) {
            self.task = task
            task.progress.totalUnitCount = 1000
            task.progress.completedUnitCount = 0
            task.expirationHandler = onExpire
        }

        func update(_ progress: DiffsplitterIndexProgress) {
            let clamped = min(max(progress.fractionCompleted, 0), 1)
            task.progress.completedUnitCount = Int64((clamped * 1000).rounded())
            guard lastSubtitle != progress.status else { return }
            lastSubtitle = progress.status
            task.updateTitle(L10n.t("Diffsplitter"), subtitle: progress.status)
        }

        func finish(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish else { return }
            didFinish = true
            task.setTaskCompleted(success: success)
        }
    }

    private static var didRegister = false
    private static var pendingContinuation: CheckedContinuation<Handle?, Never>?
    private static var pendingOnExpire: (@Sendable () -> Void)?

    static func registerAtLaunch() {
        guard #available(iOS 26.0, *) else { return }
        ensureRegistered()
    }

    static func begin(
        title: String,
        subtitle: String,
        onExpire: @escaping @Sendable () -> Void
    ) async -> Handle? {
        guard #available(iOS 26.0, *) else { return nil }
        ensureRegistered()
        return await withCheckedContinuation { continuation in
            if let previous = pendingContinuation {
                pendingContinuation = nil
                previous.resume(returning: nil)
            }
            pendingContinuation = continuation
            pendingOnExpire = onExpire

            let request = BGContinuedProcessingTaskRequest(
                identifier: identifier,
                title: title,
                subtitle: subtitle
            )
            request.strategy = .queue

            Task.detached {
                do {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } catch {
                    await MainActor.run {
                        guard let pending = pendingContinuation else { return }
                        pendingContinuation = nil
                        pendingOnExpire = nil
                        pending.resume(returning: nil)
                    }
                }
            }
        }
    }

    private static func ensureRegistered() {
        guard !didRegister else { return }
        didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            Task { @MainActor in
                deliver(task)
            }
        }
    }

    private static func deliver(_ task: BGTask) {
        let continuation = pendingContinuation
        pendingContinuation = nil
        let onExpire = pendingOnExpire
        pendingOnExpire = nil

        guard let continued = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            continuation?.resume(returning: nil)
            return
        }
        continuation?.resume(returning: Handle(task: continued, onExpire: onExpire ?? {}))
    }
}

#endif
