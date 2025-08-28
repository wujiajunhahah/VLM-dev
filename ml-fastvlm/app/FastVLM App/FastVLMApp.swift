//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI

@main
struct FastVLMApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { ContentView() }
                    .tabItem { Label("捕捉", systemImage: "camera.viewfinder") }
                NavigationStack { SceneRecallView() }
                    .tabItem { Label("场景回顾", systemImage: "arkit") }
            }
        }
    }
}
