//
//  BookFoldHingeLayout.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 18/09/2026.
//

#if os(iOS)
import SwiftUI

struct BookFoldHingeSplitObserver: ViewModifier {
    @Binding var hingeMidX: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .background {
                    GeometryReader { proxy in
                        let mid = proxy.reservedRegions(kind: .division)
                            .first(where: \.isActive)
                            .map { $0.frame.midX.rounded() }
                        Color.clear
                            .preference(key: BookFoldHingeMidXKey.self, value: mid)
                    }
                    .allowsHitTesting(false)
                }
                .onPreferenceChange(BookFoldHingeMidXKey.self) { next in
                    if next != hingeMidX {
                        hingeMidX = next
                    }
                }
                .onDisappear {
                    hingeMidX = nil
                }
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct BookFoldHingeMidXKey: PreferenceKey {
    static var defaultValue: CGFloat? { nil }

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}
#endif
