//
//  AppWindowSizing.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 30/07/2026.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct AppWindowSize {
    let defaultSize: CGSize
    let minimumSize: CGSize

    init(width: CGFloat, height: CGFloat, minimumSize: CGSize? = nil) {
        let size = CGSize(width: width, height: height)
        defaultSize = size
        self.minimumSize = minimumSize ?? size
    }
}

enum AppWindowSizing {
    static let root = AppWindowSize(width: 448, height: 520)
    static let loupeMachine = AppWindowSize(width: 960, height: 720)
    static let diffsplitter = AppWindowSize(width: 960, height: 720)
    static let entityTracker = AppWindowSize(width: 560, height: 480)
    static let skyLightDiagnostics = AppWindowSize(width: 520, height: 540)
#if DEBOOGEY_MCE
    static let cocoaDebugMenu = AppWindowSize(width: 520, height: 480)
#else
    static let cocoaDebugMenu = AppWindowSize(width: 520, height: 650)
#endif

    enum Configuration {
        static let sidebarWidth: CGFloat = 200
        static let detailWidth: CGFloat = 520
        static let minimumHeight: CGFloat = 520
        static let modern = AppWindowSize(width: sidebarWidth + detailWidth, height: minimumHeight)
        static let legacy = AppWindowSize(width: detailWidth, height: minimumHeight)
    }
}

extension View {
    @ViewBuilder
    func minimumWindowContentSize(_ sizing: AppWindowSize) -> some View {
#if os(macOS)
        frame(minWidth: sizing.minimumSize.width, minHeight: sizing.minimumSize.height)
#else
        self
#endif
    }
}

#if os(macOS)
@available(macOS 13.0, *)
extension Scene {
    func deboogeyWindowPlacement(_ sizing: AppWindowSize) -> some Scene {
        self
            .defaultSize(
                width: sizing.defaultSize.width,
                height: sizing.defaultSize.height
            )
            .defaultPosition(.center)
    }
}

extension NSWindow {
    private func layoutHostingContent() {
        contentView?.layoutSubtreeIfNeeded()
        layoutIfNeeded()
        updateConstraintsIfNeeded()
    }

    func centerAfterHostingLayout() {
        layoutHostingContent()
        center()
    }

    func sizeToFittingContentAndCenter() {
        layoutHostingContent()
        if let fittingSize = contentView?.fittingSize,
           fittingSize.width > 0,
           fittingSize.height > 0 {
            setContentSize(fittingSize)
        }
        center()
    }

    func applyDefaultContentSize(_ sizing: AppWindowSize) {
        setContentSize(sizing.defaultSize)
        minSize = frameRect(forContentRect: NSRect(origin: .zero, size: sizing.minimumSize)).size
    }
}
#endif
