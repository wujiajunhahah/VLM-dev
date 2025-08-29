//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import Foundation
#if os(iOS)
import ARKit
#endif

enum SceneMeshExporterError: Error {
    case emptyMesh
}

/// A simple OBJ exporter for ARKit LiDAR meshes.
/// USDZ 导出在移动端依赖 ModelIO/RealityKit 的较复杂转换；为稳健先提供 OBJ 导出。
struct SceneMeshExporter {
    static func exportOBJ(anchors: [ARMeshAnchor]) throws -> URL {
        guard !anchors.isEmpty else { throw SceneMeshExporterError.emptyMesh }

        var obj = "# FastVLM Scene Mesh\n"
        var vertexOffset: Int = 0

        for anchor in anchors {
            let transform = anchor.transform
            let geometry = anchor.geometry

            // Vertices
            let vertices = geometry.vertices
            let vertexBuffer = vertices.buffer
            let vertexStride = vertices.stride
            let vertexCount = vertices.count

            let basePtr = vertexBuffer.contents().advanced(by: vertices.offset)
            for i in 0..<vertexCount {
                let ptr = basePtr.advanced(by: i * vertexStride)
                let v = ptr.assumingMemoryBound(to: (Float, Float, Float).self).pointee
                let position = SIMD4<Float>(v.0, v.1, v.2, 1.0)
                let world = transform * position
                obj += String(format: "v %.6f %.6f %.6f\n", world.x, world.y, world.z)
            }

            // Faces (triangles)
            let faces = geometry.faces
            let indexCountPerPrimitive = faces.indexCountPerPrimitive
            let faceCount = faces.count

            precondition(indexCountPerPrimitive == 3, "Expect triangle faces")

            let indexBuffer = faces.buffer
            let bytesPerIndex = faces.bytesPerIndex
            let indicesPerFace = faces.indexCountPerPrimitive
            let faceStride = indicesPerFace * bytesPerIndex
            let indexBasePtr = indexBuffer.contents()

            for i in 0..<faceCount {
                let facePtr = indexBasePtr.advanced(by: i * faceStride)
                let a: Int
                let b: Int
                let c: Int
                if bytesPerIndex == 2 {
                    let i0 = UInt32(facePtr.assumingMemoryBound(to: UInt16.self).pointee)
                    let i1 = UInt32(facePtr.advanced(by: 1 * bytesPerIndex).assumingMemoryBound(to: UInt16.self).pointee)
                    let i2 = UInt32(facePtr.advanced(by: 2 * bytesPerIndex).assumingMemoryBound(to: UInt16.self).pointee)
                    a = Int(i0) + 1 + vertexOffset
                    b = Int(i1) + 1 + vertexOffset
                    c = Int(i2) + 1 + vertexOffset
                } else {
                    let i0 = facePtr.assumingMemoryBound(to: UInt32.self).pointee
                    let i1 = facePtr.advanced(by: bytesPerIndex).assumingMemoryBound(to: UInt32.self).pointee
                    let i2 = facePtr.advanced(by: 2 * bytesPerIndex).assumingMemoryBound(to: UInt32.self).pointee
                    a = Int(i0) + 1 + vertexOffset
                    b = Int(i1) + 1 + vertexOffset
                    c = Int(i2) + 1 + vertexOffset
                }
                obj += "f \(a) \(b) \(c)\n"
            }

            vertexOffset += vertexCount
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneMesh_\(Int(Date().timeIntervalSince1970)).obj")
        try obj.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}


