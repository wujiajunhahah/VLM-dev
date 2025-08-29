//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI
import AVFoundation
import MLXLMCommon
import ARKit
import RealityKit
import Video

@MainActor
final class SmartCaptureViewModel: ObservableObject {
    @Published var isCapturing = false
    @Published var currentDescription = ""
    @Published var capturedScenes: [CapturedScene] = []
    @Published var isProcessing = false
    
    private let model = FastVLMModel()
    private let camera = CameraController()
    
    init() {
        Task {
            await model.load()
            camera.start()
        }
    }
    
    func captureScene() {
        guard !isProcessing else { return }
        isProcessing = true
        
        // 模拟场景捕捉
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let scene = CapturedScene(
                id: UUID(),
                timestamp: Date(),
                description: "智能捕捉的场景",
                emoji: "📸"
            )
            self.capturedScenes.append(scene)
            self.isProcessing = false
        }
    }
}

struct CapturedScene: Identifiable {
    let id: UUID
    let timestamp: Date
    let description: String
    let emoji: String
}

struct SmartCaptureView: View {
    @StateObject private var vm = SmartCaptureViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // 顶部状态
            HStack {
                Text("智能场景捕捉")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { vm.captureScene() }) {
                    Image(systemName: vm.isProcessing ? "hourglass" : "camera.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(vm.isProcessing ? .orange : .blue)
                }
                .disabled(vm.isProcessing)
            }
            .padding()
            
            // 当前状态
            if vm.isProcessing {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在分析场景...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 200)
            } else {
                VStack {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                    Text("点击相机按钮开始捕捉")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 200)
            }
            
            // 捕捉历史
            if !vm.capturedScenes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("捕捉历史")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.capturedScenes.reversed()) { scene in
                                SceneCard(scene: scene)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct SceneCard: View {
    let scene: CapturedScene
    
    var body: some View {
        HStack(spacing: 15) {
            Text(scene.emoji)
                .font(.system(size: 40))
            
            VStack(alignment: .leading, spacing: 5) {
                Text(scene.description)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(scene.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

#Preview {
    SmartCaptureView()
}
