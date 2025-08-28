//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AVFoundation
import CoreImage
import Photos

#if os(iOS)
    import UIKit
#endif

@Observable
public class CameraController: NSObject {

    private var framesContinuation: AsyncStream<CMSampleBuffer>.Continuation?

    public var backCamera = true {
        didSet {
            stop()
            start()
        }
    }

    public var devices = [AVCaptureDevice]()

    public var device: AVCaptureDevice = AVCaptureDevice.default(for: .video)! {
        didSet {
            stop()
            start()
        }
    }

    private var permissionGranted = true
    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    @objc dynamic private var rotationCoordinator : AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var photoOutput: AVCapturePhotoOutput?

    public func attach(continuation: AsyncStream<CMSampleBuffer>.Continuation) {
        sessionQueue.async {
            self.framesContinuation = continuation
        }
    }

    public func detatch() {
        sessionQueue.async {
            self.framesContinuation = nil
        }
    }

    public func stop() {
        sessionQueue.sync { [self] in
            captureSession?.stopRunning()
            captureSession = nil
        }

    }

    public func start() {
        sessionQueue.async { [self] in
            let captureSession = AVCaptureSession()
            self.captureSession = captureSession

            self.checkPermission()
            self.setupCaptureSession(position: backCamera ? .back : .front)
            captureSession.startRunning()
        }
    }

    #if os(iOS)
        private func setOrientation(_ orientation: UIDeviceOrientation) {
            guard let captureSession else { return }

            let angle: Double?
            switch orientation {
            case .unknown, .faceDown:
                angle = nil
            case .portrait, .faceUp:
                angle = 90
            case .portraitUpsideDown:
                angle = 270
            case .landscapeLeft:
                angle = 0
            case .landscapeRight:
                angle = 180
            @unknown default:
                angle = nil
            }

            if let angle {
                for output in captureSession.outputs {
                    output.connection(with: .video)?.videoRotationAngle = angle
                }
            }
        }
    
    private func updateRotation(rotation : CGFloat) {
        guard let captureSession else { return }
        for output in captureSession.outputs {
            output.connection(with: .video)?.videoRotationAngle = rotation
        }
    }
    #endif

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            self.permissionGranted = true

        case .notDetermined:
            // The user has not yet been asked for camera access.
            self.requestPermission()

        // Combine the two other cases into the default case
        default:
            self.permissionGranted = false
        }
    }

    func requestPermission() {
        // Strong reference not a problem here but might become one in the future.
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.permissionGranted = granted
        }
    }

    func setupCaptureSession(position: AVCaptureDevice.Position) {
        guard let captureSession else { return }

        let videoOutput = AVCaptureVideoDataOutput()

        guard permissionGranted else {
            print("No permission for camera")
            return
        }

        let deviceTypes: [AVCaptureDevice.DeviceType]
        #if os(iOS)
            deviceTypes = [.builtInDualCamera, .builtInWideAngleCamera]
        #else
            deviceTypes = [.external, .continuityCamera, .builtInWideAngleCamera]
        #endif

        let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position)

        let videoDevice: AVCaptureDevice?
        if videoDeviceDiscoverySession.devices.contains(self.device) {
            videoDevice = self.device
        } else {
            videoDevice = videoDeviceDiscoverySession.devices.first
        }

        if devices.isEmpty {
            self.devices = videoDeviceDiscoverySession.devices
        }

        guard
            let videoDevice
        else {
            print("Unable to find video device")
            return
        }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Unable to create AVCaptureDeviceInput")
            return
        }
        guard captureSession.canAddInput(videoDeviceInput) else {
            print("Unable to add input")
            return
        }
        captureSession.addInput(videoDeviceInput)

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput(videoOutput)
        captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080

        // Configure photo output for spatial snapshot
        let photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            // Enable depth delivery when supported
            if photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = true
            }
            self.photoOutput = photoOutput
        }

        #if os(iOS)
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: videoDevice, previewLayer: nil)
        rotationObservation = observe(\.rotationCoordinator!.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] _, change in
            if let nv = change.newValue {
                self?.updateRotation(rotation: nv)
            }
        }
        #endif
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if sampleBuffer.isValid && sampleBuffer.imageBuffer != nil {
            framesContinuation?.yield(sampleBuffer)
        }
    }
}

// MARK: - Spatial Snapshot
extension CameraController: AVCapturePhotoCaptureDelegate {
    public func captureSpatialPhoto() {
        sessionQueue.async { [weak self] in
            guard let self, let photoOutput = self.photoOutput else { return }

            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            if photoOutput.isDepthDataDeliverySupported {
                settings.isDepthDataDeliveryEnabled = true
            }
            // High-resolution if available
            settings.isHighResolutionPhotoEnabled = photoOutput.isHighResolutionCaptureEnabled

            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { print("Photo capture error: \(error)"); return }

        guard let data = photo.fileDataRepresentation() else { return }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                print("No photo library permission")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: options)
            }, completionHandler: { success, err in
                if !success { print("Save photo failed: \(String(describing: err))") }
            })
        }
    }
}
