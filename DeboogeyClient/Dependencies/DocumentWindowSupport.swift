//
//  DocumentWindowSupport.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import SwiftUI
#if canImport(AppKit)
import AppKit

final class DocumentWindowAttachmentView: NSView {
    var didMoveToWindowHandler: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        didMoveToWindowHandler?(window)
    }
}

enum DocumentUnsavedChangesPrompt {
    static func present(
        in window: NSWindow?,
        messageText: String,
        informativeText: String,
        setPrompting: @escaping (Bool) -> Void,
        saveDraft: ((@escaping (Bool) -> Void) -> Void)?,
        onDiscardOrSave: @escaping () -> Void
    ) {
        guard let window else { return }
        setPrompting(true)
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: L10n.t("Save"))
        alert.addButton(withTitle: L10n.t("Don’t Save"))
        alert.addButton(withTitle: L10n.t("Cancel"))
        alert.beginSheetModal(for: window) { response in
            setPrompting(false)
            switch response {
            case .alertFirstButtonReturn:
                saveDraft? { saved in
                    if saved { onDiscardOrSave() }
                }
            case .alertSecondButtonReturn:
                onDiscardOrSave()
            default:
                break
            }
        }
    }

    static func installQuitMonitor(
        hasUnsavedChanges: @escaping () -> Bool,
        isKeyWindow: @escaping () -> Bool,
        prompt: @escaping (@escaping () -> Void) -> Void
    ) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard hasUnsavedChanges(),
                  isKeyWindow(),
                  event.charactersIgnoringModifiers?.lowercased() == "q",
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            else { return event }
            prompt { NSApp.terminate(nil) }
            return nil
        } as Any
    }
}

@MainActor
enum ToolDocumentWindowHosting {
    static func makeWindow<Content: View>(
        title: String,
        sizing: AppWindowSize,
        bridgeToolbars: Bool,
        rootView: Content
    ) -> NSWindow {
        let rooted = rootView.environment(\.locale, L10n.locale)
        let window: NSWindow
        if bridgeToolbars, #available(macOS 14.0, *) {
            let hostingView = NSHostingView(rootView: rooted)
            hostingView.sceneBridgingOptions = [.toolbars]
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: sizing.defaultSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
        } else {
            window = NSWindow(contentViewController: NSHostingController(rootView: rooted))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(sizing.defaultSize)
        }
        window.title = title
        window.minSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: sizing.minimumSize)
        ).size
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    static func observeClose(
        of window: NSWindow,
        onClose: @escaping () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onClose()
            }
        }
    }
}
#endif
