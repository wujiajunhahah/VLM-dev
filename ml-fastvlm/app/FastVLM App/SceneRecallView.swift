//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI
#if os(iOS)
import ARKit
import RealityKit
import Vision
import simd

struct SceneRecallView: View {
	@State private var isScanning: Bool = false
	@State private var mappingStatusText: String = "未开始"
	@State private var savedMaps: [URL] = SceneRecallStorage.listSavedWorldMaps()
	@State private var selectedMapURL: URL?

	var body: some View {
		NavigationStack {
			VStack(spacing: 12) {
				ARViewContainer(isScanning: $isScanning, mappingStatusText: $mappingStatusText)
					.aspectRatio(3/4, contentMode: .fit)
					.overlay(alignment: .topLeading) {
						Text("映射: \(mappingStatusText)")
							.font(.caption)
							.foregroundStyle(.white)
							.padding(6)
							.background(.ultraThinMaterial)
							.clipShape(Capsule())
							.padding(8)
					}

				HStack(spacing: 10) {
					Button(isScanning ? "停止扫描" : "开始扫描") {
						isScanning.toggle()
					}
					.buttonStyle(.borderedProminent)

					Button("保存场景") {
						NotificationCenter.default.post(name: SceneRecallCoordinator.requestSaveWorldMap, object: nil)
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
							savedMaps = SceneRecallStorage.listSavedWorldMaps()
						}
					}
					.buttonStyle(.bordered)

					Button("拍摄空间照片") {
						NotificationCenter.default.post(name: SceneRecallCoordinator.requestCaptureSpatialPhoto, object: nil)
					}
					.buttonStyle(.bordered)
				}

				List {
					Section("已保存的场景") {
						if savedMaps.isEmpty {
							Text("暂无已保存场景，先进行扫描并保存")
								.foregroundStyle(.secondary)
						} else {
							ForEach(savedMaps, id: \.
								self) { url in
								HStack {
									Text(url.deletingPathExtension().lastPathComponent)
										.lineLimit(1)
								Spacer()
								Button("回顾") {
									selectedMapURL = url
									NotificationCenter.default.post(name: SceneRecallCoordinator.requestLoadWorldMap, object: url)
								}
								.buttonStyle(.bordered)
							}
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								Button(role: .destructive) {
									SceneRecallStorage.delete(url: url)
									savedMaps = SceneRecallStorage.listSavedWorldMaps()
								} label: { Label("删除", systemImage: "trash") }
							}
						}
					}
				}
			}
			.navigationTitle("场景回顾")
		}
	}
}

// MARK: - AR Hosting
fileprivate struct ARViewContainer: UIViewRepresentable {
	@Binding var isScanning: Bool
	@Binding var mappingStatusText: String

	func makeCoordinator() -> SceneRecallCoordinator {
		SceneRecallCoordinator(updateStatus: { status in
			DispatchQueue.main.async { self.mappingStatusText = status }
		})
	}

	func makeUIView(context: Context) -> ARView {
		let arView = ARView(frame: .zero)
		arView.automaticallyConfigureSession = false
		arView.environment.sceneUnderstanding.options.insert(.occlusion)
		arView.debugOptions = [.showFeaturePoints, .showSceneUnderstanding]
		context.coordinator.arView = arView
		context.coordinator.startOrStopScanning(start: isScanning)
		return arView
	}

	func updateUIView(_ uiView: ARView, context: Context) {
		context.coordinator.startOrStopScanning(start: isScanning)
	}
}

final class SceneRecallCoordinator: NSObject, ARSessionDelegate {
	static let requestSaveWorldMap = Notification.Name("SceneRecallCoordinator.requestSaveWorldMap")
	static let requestLoadWorldMap = Notification.Name("SceneRecallCoordinator.requestLoadWorldMap")
	static let requestCaptureSpatialPhoto = Notification.Name("SceneRecallCoordinator.requestCaptureSpatialPhoto")

	weak var arView: ARView?
	private let updateStatus: (String) -> Void

	init(updateStatus: @escaping (String) -> Void) {
		self.updateStatus = updateStatus
		super.init()
		NotificationCenter.default.addObserver(self, selector: #selector(saveWorldMapRequested), name: Self.requestSaveWorldMap, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(loadWorldMapRequested(_:)), name: Self.requestLoadWorldMap, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(captureSpatialPhotoRequested), name: Self.requestCaptureSpatialPhoto, object: nil)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func startOrStopScanning(start: Bool) {
		guard let arView else { return }
		if start {
			guard ARWorldTrackingConfiguration.isSupported else { return }
			let config = ARWorldTrackingConfiguration()
			config.planeDetection = [.horizontal, .vertical]
			config.environmentTexturing = .automatic
			if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
				config.sceneReconstruction = .meshWithClassification
			}
			var semantics: ARConfiguration.FrameSemantics = []
			if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { semantics.insert(.sceneDepth) }
			if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) { semantics.insert(.smoothedSceneDepth) }
			config.frameSemantics = semantics

			arView.session.delegate = self
			arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
			updateStatus("扫描中…")
		} else {
			arView.session.pause()
			updateStatus("已停止")
		}
	}

	func session(_ session: ARSession, didUpdate frame: ARFrame) {
		switch frame.worldMappingStatus {
		case .notAvailable: updateStatus("不可用")
		case .limited: updateStatus("有限")
		case .extending: updateStatus("扩展中")
		case .mapped: updateStatus("已完成")
		@unknown default: updateStatus("未知")
		}
	}

	@objc private func saveWorldMapRequested() {
		guard let session = arView?.session else { return }
		session.getCurrentWorldMap { worldMap, error in
			guard let worldMap else { return }
			do {
				let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
				try SceneRecallStorage.saveWorldMapData(data)
			} catch {
				print("Save worldMap failed: \(error)")
			}
		}
	}

	@objc private func loadWorldMapRequested(_ note: Notification) {
		guard let url = note.object as? URL else { return }
		do {
			let data = try Data(contentsOf: url)
			guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else { return }
			guard ARWorldTrackingConfiguration.isSupported else { return }
			let config = ARWorldTrackingConfiguration()
			config.planeDetection = [.horizontal, .vertical]
			config.environmentTexturing = .automatic
			config.initialWorldMap = worldMap
			if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
				config.sceneReconstruction = .meshWithClassification
			}
			arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
		} catch {
			print("Load worldMap failed: \(error)")
		}
	}

	@objc private func captureSpatialPhotoRequested() {
		guard let arView else { return }
		guard let frame = arView.session.currentFrame else { return }
		let pixelBuffer = frame.capturedImage
		let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
		let context = CIContext()
		guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return }
		let baseImage = UIImage(cgImage: cg)

		// 运行显著性检测进行自动裁剪
		let handler = VNImageRequestHandler(cgImage: cg, orientation: .right, options: [:])
		let request = VNGenerateAttentionBasedSaliencyImageRequest()
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				try handler.perform([request])
				let cropped = self.cropImageBySaliency(baseImage: baseImage, request: request) ?? baseImage
				self.placeImageBillboard(in: arView, image: cropped)
				self.saveToPhotos(image: cropped)
			} catch {
				print("Saliency error: \(error)")
			}
		}
	}

	private func cropImageBySaliency(baseImage: UIImage, request: VNGenerateAttentionBasedSaliencyImageRequest) -> UIImage? {
		guard let result = request.results?.first as? VNSaliencyImageObservation,
				let best = result.salientObjects?.max(by: { $0.confidence < $1.confidence }) ?? result.salientObjects?.first
		else { return nil }
		let bbox = best.boundingBox
		let rect = CGRect(x: bbox.minX * baseImage.size.width,
						 y: (1 - bbox.maxY) * baseImage.size.height,
						 width: bbox.width * baseImage.size.width,
						 height: bbox.height * baseImage.size.height)
		guard let cg = baseImage.cgImage?.cropping(to: rect.integral) else { return nil }
		return UIImage(cgImage: cg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
	}

	private func placeImageBillboard(in arView: ARView, image: UIImage) {
		guard let cgImage = image.cgImage else { return }
		do {
			let texture = try TextureResource.generate(from: cgImage, options: .init())
			let material = UnlitMaterial(color: .white)
			var mat = material
			mat.baseColor = .texture(texture)
			let aspect = Float(image.size.width / max(image.size.height, 1))
			let height: Float = 0.2
			let width: Float = height * aspect
			let plane = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [mat])
			var transform = arView.cameraTransform
			let forwardColumn = transform.matrix.columns.2
			let forward = normalize(SIMD3<Float>(forwardColumn.x, forwardColumn.y, forwardColumn.z))
			transform.translation -= forward * 0.5 // 前方0.5米
			plane.transform = transform
			let anchor = AnchorEntity(world: .zero)
			anchor.addChild(plane)
			arView.scene.addAnchor(anchor)
		} catch {
			print("Texture generate failed: \(error)")
		}
	}

	private func saveToPhotos(image: UIImage) {
		UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
	}
}

// MARK: - Storage
enum SceneRecallStorage {
	static func folderURL() -> URL {
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		let folder = docs.appendingPathComponent("SceneRecalls", isDirectory: true)
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}

	static func saveWorldMapData(_ data: Data) throws {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyyMMdd-HHmmss"
		let name = "scan-\(formatter.string(from: Date()))"
		let url = folderURL().appendingPathComponent(name).appendingPathExtension("worldmap")
		try data.write(to: url)
	}

	static func listSavedWorldMaps() -> [URL] {
		let dir = folderURL()
		let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
		return urls.filter { $0.pathExtension == "worldmap" }
			.sorted { (a, b) -> Bool in
				let ad = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
				let bd = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
				return ad > bd
			}
	}

	static func delete(url: URL) {
		try? FileManager.default.removeItem(at: url)
	}
}

#endif


