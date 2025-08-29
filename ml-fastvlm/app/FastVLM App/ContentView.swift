//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AVFoundation
import MLXLMCommon
import SwiftUI
import Video
import Foundation

// support swift 6
extension CVImageBuffer: @unchecked @retroactive Sendable {}
extension CMSampleBuffer: @unchecked @retroactive Sendable {}

// delay between frames -- controls the frame rate of the updates
let FRAME_DELAY = Duration.milliseconds(1)

struct ContentView: View {
    @State private var camera = CameraController()
    @State private var model = FastVLMModel()

    /// stream of frames -> VideoFrameView, see distributeVideoFrames
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?
    @State private var lastFrame: CVImageBuffer?

    @State private var prompt = "请用中文简要描述画面。"
    @State private var promptSuffix = "字数不超过15字。"

    @State private var isShowingInfo: Bool = false

    @State private var selectedCameraType: CameraType = .continuous
    @State private var isEditingPrompt: Bool = false
    @State private var isEmojiMode: Bool = false
    @State private var emojiStore = EmojiLogStore()
    @State private var timedRunning: Bool = false
    @State private var timedTask: Task<Void, Never>? = nil
    @State private var timedIntervalSeconds: Double = 30

    var toolbarItemPlacement: ToolbarItemPlacement {
        var placement: ToolbarItemPlacement = .navigation
        #if os(iOS)
        placement = .topBarLeading
        #endif
        return placement
    }
    
    var statusTextColor : Color {
        return model.evaluationState == .processingPrompt ? .black : .white
    }
    
    var statusBackgroundColor : Color {
        switch model.evaluationState {
        case .idle:
            return .gray
        case .generatingResponse:
            return .green
        case .processingPrompt:
            return .yellow
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10.0) {
                        // 精简：去掉相机模式选择与定时设置

                        if let framesToDisplay {
                            VideoFrameView(
                                frames: framesToDisplay,
                                cameraType: selectedCameraType,
                                action: { frame in
                                    processSingleFrame(frame)
                                })
                                // Because we're using the AVCaptureSession preset
                                // `.vga640x480`, we can assume this aspect ratio
                                .aspectRatio(4/3, contentMode: .fit)
                                #if os(macOS)
                                .frame(maxWidth: 750)
                                #endif
                                .overlay(alignment: .top) {
                                    if !model.promptTime.isEmpty {
                                        Text("TTFT \(model.promptTime)")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                            .monospaced()
                                            .padding(.vertical, 4.0)
                                            .padding(.horizontal, 6.0)
                                            .background(alignment: .center) {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.black.opacity(0.6))
                                            }
                                            .padding(.top)
                                    }
                                }
                                #if !os(macOS)
                                .overlay(alignment: .topTrailing) {
                                    CameraControlsView(
                                        backCamera: $camera.backCamera,
                                        device: $camera.device,
                                        devices: $camera.devices)
                                    .padding()
                                    Button {
                                        camera.captureSpatialPhoto()
                                    } label: {
                                        Image(systemName: "cube.transparent")
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(.white)
                                            .padding(8)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                    .padding([.top, .trailing], 8)
                                }
                                #endif
                                .overlay(alignment: .bottom) {
                                    HStack(spacing: 10) {
                                        Button {
                                            let frame = lastFrame
                                            if let frame { processSingleFrame(frame) }
                                        } label: {
                                            Label("一键描述", systemImage: "sparkles")
                                        }
                                        .buttonStyle(.borderedProminent)

                                        if !model.output.isEmpty {
                                            ShareLink(item: model.output) {
                                                Label("分享", systemImage: "square.and.arrow.up")
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(.vertical, 6.0)
                                    .padding(.horizontal, 8.0)
                                    .background(.ultraThinMaterial)
                                    .clipShape(.capsule)
                                    .padding(.bottom)
                                }
                                #if os(macOS)
                                .frame(maxWidth: .infinity)
                                .frame(minWidth: 500)
                                .frame(minHeight: 375)
                                #endif
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // 精简：去除可编辑 Prompt 区域

                Section("描述结果") {
                    if model.output.isEmpty && model.running {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(model.output)
                            .textSelection(.enabled)
                    }
                }

                #if os(macOS)
                Spacer()
                #endif
            }
            
            #if os(iOS)
            .listSectionSpacing(0)
            #elseif os(macOS)
            .padding()
            #endif
            .task {
                camera.start()
            }
            .task {
                await model.load()
            }

            #if !os(macOS)
            .onAppear {
                // Prevent the screen from dimming or sleeping due to inactivity
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                // Resumes normal idle timer behavior
                UIApplication.shared.isIdleTimerDisabled = false
            }
            #endif

            // task to distribute video frames -- this will cancel
            // and restart when the view is on/off screen.  note: it is
            // important that this is here (attached to the VideoFrameView)
            // rather than the outer view because this has the correct lifecycle
            .task { await distributeVideoFrames() }

            .navigationTitle("FastVLM")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { }
        }
    }

    var promptSummary: some View {
        Section("Prompt") {
            VStack(alignment: .leading, spacing: 4.0) {
                let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPrompt.isEmpty {
                    Text(trimmedPrompt)
                        .foregroundStyle(.secondary)
                }

                let trimmedSuffix = promptSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedSuffix.isEmpty {
                    Text(trimmedSuffix)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    var promptForm: some View {
        Group {
            #if os(iOS)
            Section("Prompt") {
                TextEditor(text: $prompt)
                    .frame(minHeight: 38)
            }

            Section("Prompt Suffix") {
                TextEditor(text: $promptSuffix)
                    .frame(minHeight: 38)
            }
            #elseif os(macOS)
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("Prompt")
                            .font(.headline)

                        TextEditor(text: $prompt)
                            .frame(height: 38)
                            .padding(.horizontal, 8.0)
                            .padding(.vertical, 10.0)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(10.0)
                    }

                    VStack(alignment: .leading) {
                        Text("Prompt Suffix")
                            .font(.headline)

                        TextEditor(text: $promptSuffix)
                            .frame(height: 38)
                            .padding(.horizontal, 8.0)
                            .padding(.vertical, 10.0)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(10.0)
                    }
                }
            }
            .padding(.vertical)
            #endif
        }
    }

    var promptSections: some View {
        Group {
            #if os(iOS)
            if isEditingPrompt {
                promptForm
            }
            else {
                promptSummary
            }
            #elseif os(macOS)
            promptForm
            #endif
        }
    }

    // 移除自动连续分析

    func distributeVideoFrames() async {
        // attach a stream to the camera -- this code will read this
        let frames = AsyncStream<CMSampleBuffer>(bufferingPolicy: .bufferingNewest(1)) {
            camera.attach(continuation: $0)
        }

        let (framesToDisplay, framesToDisplayContinuation) = AsyncStream.makeStream(
            of: CVImageBuffer.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.framesToDisplay = framesToDisplay

        // Only create analysis stream if in continuous mode
        // 精简：不再创建分析流

        // set up structured tasks (important -- this means the child tasks
        // are cancelled when the parent is cancelled)
        async let distributeFrames: () = {
            for await sampleBuffer in frames {
                if let frame = sampleBuffer.imageBuffer {
                    framesToDisplayContinuation.yield(frame)
                    await MainActor.run {
                        self.lastFrame = frame
                    }
                    // 不再在后台自动推理
                }
            }

            // detach from the camera controller and feed to the video view
            await MainActor.run {
                self.framesToDisplay = nil
                self.camera.detatch()
            }

            framesToDisplayContinuation.finish()
            //
        }()

        // Only analyze frames if in continuous mode
        await distributeFrames
    }

    /// Perform FastVLM inference on a single frame.
    /// - Parameter frame: The frame to analyze.
    func processSingleFrame(_ frame: CVImageBuffer) {
        // Reset Response UI (show spinner)
        Task { @MainActor in
            model.output = ""
        }

        // Construct request to model
        let userInput = UserInput(
            prompt: .text("\(prompt) \(promptSuffix)"),
            images: [.ciImage(CIImage(cvPixelBuffer: frame))]
        )

        // Post request to FastVLM
        Task {
            let t = await model.generate(userInput)
            _ = await t.result
            if isEmojiMode {
                let text = await MainActor.run { model.output }
                let emoji = extractFirstEmoji(from: text)
                if let emoji {
                    await MainActor.run {
                        emojiStore.add(entry: EmojiEntry(timestamp: Date(), emoji: emoji))
                    }
                }
            }
        }
    }

    func startTimedLoop() {
        timedRunning = true
        timedTask?.cancel()
        timedTask = Task {
            while !Task.isCancelled && timedRunning {
                let frame = await MainActor.run { self.lastFrame }
                if let frame { processSingleFrame(frame) }
                do {
                    try await Task.sleep(for: .seconds(timedIntervalSeconds))
                } catch { break }
            }
        }
    }

    func stopTimedLoop() {
        timedRunning = false
        timedTask?.cancel()
        timedTask = nil
    }

    func extractFirstEmoji(from text: String) -> String? {
        // 使用 Character 层级，保持完整的 emoji 字符簇（含变体/皮肤色/ZWJ组合）
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            if token.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
                // 返回第一个包含 emoji 的 token 作为整簇
                // 同时限制长度，避免非常长的串
                let s = String(token)
                return s.count > 8 ? String(s.prefix(8)) : s
            }
        }
        // 如果没有分词命中，则回退到整行扫描第一个 Character 为 emoji 的簇
        for ch in text {
            if ch.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
                return String(ch)
            }
        }
        return nil
    }
}

#Preview {
    ContentView()
}
