//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI

func isIOS26OrNewer() -> Bool {
    #if os(iOS)
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return v.majorVersion >= 26
    #else
    return false
    #endif
}

struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if isIOS26OrNewer() {
            content
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(
                            LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        } else {
            content
        }
    }
}

extension View {
    func glassCapsule() -> some View {
        self.modifier(GlassCapsuleModifier())
    }

    @ViewBuilder
    func glassBackground(fallbackColor: Color) -> some View {
        if isIOS26OrNewer() {
            self.background(.ultraThinMaterial)
        } else {
            self.background(fallbackColor)
        }
    }
}


