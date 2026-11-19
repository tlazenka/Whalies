import Foundation
import StadiumGame

// Snapshot simulation time so render callbacks neither advance it nor read main-actor state.
struct WaterLensFrame: Equatable, Sendable {
    var elapsed: Float
    var strength: Float

    init(spray: WaterSpray?, tick: Int) {
        elapsed = spray.map { Float(max(0, tick - $0.impactTick)) / 60 } ?? 0
        strength = Float(spray?.lensStrength(at: tick) ?? 0)
    }

    var uniforms: SIMD4<Float> { SIMD4(elapsed, strength, 0, 0) }
}

#if canImport(Metal)
import Metal
import OSLog

// RealityKit callbacks can run off the main thread. Lock shared frame/pipeline state; encoders stay callback-local.
final class WaterLensRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var frame = WaterLensFrame(spray: nil, tick: 0)
    private var pipeline: (any MTLComputePipelineState)?
    private var preparedDevice: UInt64?
    private let logger = Logger(subsystem: "com.muttniks.stadium", category: "WaterLens")

    enum ShaderError: Error {
        case missingResource
        case missingFunction
    }

    // Compile the bundled source for the render device, also used by the GPU test.
    static func makePipeline(device: any MTLDevice) throws -> any MTLComputePipelineState {
        guard let url = Bundle.module.url(forResource: "WaterLens", withExtension: "metal") else {
            throw ShaderError.missingResource
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "stadiumWaterLens") else {
            throw ShaderError.missingFunction
        }
        return try device.makeComputePipelineState(function: function)
    }

    func prepare(device: any MTLDevice) {
        let identifier = device.registryID
        lock.lock()
        guard preparedDevice != identifier else { lock.unlock(); return }
        preparedDevice = identifier
        pipeline = nil
        lock.unlock()
        do {
            let prepared = try Self.makePipeline(device: device)
            lock.lock()
            if preparedDevice == identifier { pipeline = prepared }
            lock.unlock()
        } catch {
            logger.error("Unable to prepare water lens shader: \(String(describing: error), privacy: .public)")
        }
    }

    func update(_ value: WaterLensFrame) {
        lock.lock()
        frame = value
        lock.unlock()
    }

    // Copy the frame when the effect is unavailable to avoid a black screen.
    @discardableResult
    func encode(commandBuffer: any MTLCommandBuffer, source: any MTLTexture, target: any MTLTexture) -> Bool {
        lock.lock()
        let current = frame
        let prepared = pipeline
        lock.unlock()

        guard current.strength > 0, let prepared,
              prepared.device.registryID == source.device.registryID else {
            Self.copy(commandBuffer: commandBuffer, source: source, target: target)
            return false
        }
        // Older Mac GPUs need a writable unorm view and explicit sRGB encoding.
        let output: (any MTLTexture)?
        let encodeSRGB = !target.device.supportsFamily(.apple2) && target.pixelFormat == .bgra8Unorm_srgb
        if encodeSRGB {
            output = target.makeTextureView(pixelFormat: .bgra8Unorm)
        } else {
            output = target
        }
        guard let output, let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Self.copy(commandBuffer: commandBuffer, source: source, target: target)
            return false
        }
        var uniforms = current.uniforms
        uniforms.z = encodeSRGB ? 1 : 0
        encoder.setComputePipelineState(prepared)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        let width = prepared.threadExecutionWidth
        let height = max(1, min(8, prepared.maxTotalThreadsPerThreadgroup / width))
        let group = MTLSize(width: width, height: height, depth: 1)
        let groups = MTLSize(width: (target.width + width - 1) / width,
                             height: (target.height + height - 1) / height, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: group)
        encoder.endEncoding()
        return true
    }

    private static func copy(commandBuffer: any MTLCommandBuffer, source: any MTLTexture, target: any MTLTexture) {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        encoder.copy(from: source, to: target)
        encoder.endEncoding()
    }
}
#endif
