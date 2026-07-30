//
//  AppWindowSizing.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 30/07/2026.
//


import SwiftUI

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
    static let root = AppWindowSize(width: 620, height: 520)
    static let loupeMachine = AppWindowSize(width: 960, height: 720)

    enum Configuration {
        static let sidebarWidth: CGFloat = 200
        static let detailWidth: CGFloat = 520
        static let minimumHeight: CGFloat = 520
        static let modern = AppWindowSize(width: sidebarWidth + detailWidth, height: minimumHeight)
        static let legacy = AppWindowSize(width: detailWidth, height: minimumHeight)
    }
}

extension View {
    func minimumWindowContentSize(_ sizing: AppWindowSize) -> some View {
        frame(minWidth: sizing.minimumSize.width, minHeight: sizing.minimumSize.height)
    }
}
