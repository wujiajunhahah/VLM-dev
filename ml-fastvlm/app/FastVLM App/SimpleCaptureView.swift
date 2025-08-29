//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI
import AVFoundation
import MLXLMCommon
import Video

@MainActor
final class SimpleCaptureViewModel: ObservableObject {
    @Published var isCapturing = false
    @Published var currentDescription = ""
    @Published var isProcessing = false
    @Published var capturedScenes: [CapturedScene] = []
    
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
        isCapturing = true
        
        // 模拟场景捕捉和分析
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.currentDescription = "📱 正在分析场景..."
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let descriptions = [
                    "🏠 温馨的客厅，阳光透过窗户洒在沙发上",
                    "💻 整洁的工作台，电脑屏幕显示着代码",
                    "🌳 美丽的公园，绿树成荫，人们在散步",
                    "☕️ 舒适的咖啡厅，香气四溢",
                    "📚 安静的图书馆，书架整齐排列"
                ]
                
                let randomDescription = descriptions.randomElement() ?? "📸 智能场景捕捉完成"
                self.currentDescription = randomDescription
                
                let newScene = CapturedScene(
                    id: UUID(),
                    timestamp: Date(),
                    description: randomDescription,
                    emoji: self.extractEmoji(from: randomDescription)
                )
                
                self.capturedScenes.insert(newScene, at: 0)
                self.isCapturing = false
                self.isProcessing = false
            }
        }
    }
    
    private func extractEmoji(from text: String) -> String {
        let emojis = ["🏠", "💻", "🌳", "☕️", "📚", "📱", "📸", "🎯", "✨", "🌟"]
        return emojis.randomElement() ?? "📸"
    }
}

struct CapturedScene: Identifiable {
    let id: UUID
    let timestamp: Date
    let description: String
    let emoji: String
}

struct SimpleCaptureView: View {
    @StateObject private var vm = SimpleCaptureViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 状态显示
                VStack(spacing: 12) {
                    if vm.isCapturing {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                    } else {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                            .padding()
                    }
                    
                    Text(vm.currentDescription.isEmpty ? "点击下方按钮开始智能场景捕捉" : vm.currentDescription)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
                
                // 捕捉按钮
                Button {
                    vm.captureScene()
                } label: {
                    HStack {
                        Image(systemName: vm.isCapturing ? "stop.circle.fill" : "camera.circle.fill")
                        Text(vm.isCapturing ? "停止捕捉" : "开始捕捉")
                    }
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.isCapturing ? .red : .blue)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .disabled(vm.isProcessing)
                .padding(.horizontal)
                
                // 历史记录
                if !vm.capturedScenes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📝 捕捉历史")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(vm.capturedScenes) { scene in
                                    HStack(spacing: 12) {
                                        Text(scene.emoji)
                                            .font(.title)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(scene.description)
                                                .font(.body)
                                                .lineLimit(2)
                                            
                                            Text(scene.timestamp, style: .time)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("🎯 SmartScene")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    SimpleCaptureView()
}
