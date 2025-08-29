//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI
import ARKit
import RealityKit
import Photos

@MainActor
final class SceneRecallViewModel: ObservableObject {
    @Published var isSupported: Bool = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    @Published var isRecording: Bool = false
    @Published var meshAnchors: [ARMeshAnchor] = []
    @Published var shareURL: URL?

    func requestPhotoWrite() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        if status == .authorized || status == .limited {
            // ok
        }
    }

    func exportOBJ() {
        do {
            let url = try SceneMeshExporter.exportOBJ(anchors: meshAnchors)
            self.shareURL = url
        } catch {
            print("Export failed: \(error)")
        }
    }
}

struct SceneRecallView: View {
    @StateObject private var vm = SceneRecallViewModel()
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 0) {
            if vm.isSupported {
                SceneViewContainer(meshAnchors: $vm.meshAnchors, isRecording: $vm.isRecording)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("设备不支持", systemImage: "arkit", description: Text("需要具备 LiDAR 的设备"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(vm.isRecording ? "停止扫描" : "开始扫描") { vm.isRecording.toggle() }
                    Button("导出OBJ") { vm.exportOBJ(); showShare = true }
                        .disabled(vm.meshAnchors.isEmpty)
                }
            }
        }
        .task { await vm.requestPhotoWrite() }
        .sheet(isPresented: $showShare) {
            if let url = vm.shareURL { ShareSheet(items: [url]) }
        }
        .navigationTitle("场景回顾")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// RealityKit + ARKit view
private struct SceneViewContainer: UIViewRepresentable {
    @Binding var meshAnchors: [ARMeshAnchor]
    @Binding var isRecording: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.delegate = context.coordinator
        arView.session.run(config)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Toggle nothing; session keeps running. Mesh capture is collected via delegate
    }

    func makeCoordinator() -> Coordinator { Coordinator(meshAnchors: $meshAnchors) }

    final class Coordinator: NSObject, ARSessionDelegate {
        var meshAnchorsBinding: Binding<[ARMeshAnchor]>
        init(meshAnchors: Binding<[ARMeshAnchor]>) { self.meshAnchorsBinding = meshAnchors }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
            if meshes.isEmpty { return }
            DispatchQueue.main.async {
                var current = self.meshAnchorsBinding.wrappedValue
                current.append(contentsOf: meshes)
                self.meshAnchorsBinding.wrappedValue = current
            }
        }
    }
}