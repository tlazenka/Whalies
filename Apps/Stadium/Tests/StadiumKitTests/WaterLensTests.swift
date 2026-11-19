#if canImport(Metal)
import Foundation
import Metal
import Testing
import StadiumGame
@testable import StadiumKit

// Private textures need staging buffers; discrete Mac GPUs also need managed-memory synchronization.
@Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil),
      arguments: [MTLPixelFormat.bgra8Unorm, .bgra8Unorm_srgb])
func waterLensRefractsPixelsAndRestoresTheDryFrame(format: MTLPixelFormat) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let width = 64, height = 64, bytesPerRow = 64 * 4
    let byteCount = bytesPerRow * height
    let size = MTLSize(width: width, height: height, depth: 1)
    let origin = MTLOrigin(x: 0, y: 0, z: 0)
    #if os(macOS)
    let bufferOptions: MTLResourceOptions = device.hasUnifiedMemory ? .storageModeShared : .storageModeManaged
    #else
    let bufferOptions: MTLResourceOptions = .storageModeShared
    #endif

    var checkerboard = [UInt8](repeating: 255, count: byteCount)
    for y in 0..<height {
        for x in 0..<width {
            let value: UInt8 = ((x / 4 + y / 4) % 2 == 0) ? 32 : 224
            let offset = y * bytesPerRow + x * 4
            checkerboard[offset] = value
            checkerboard[offset + 1] = value
            checkerboard[offset + 2] = value
        }
    }
    let upload = try #require(checkerboard.withUnsafeBytes {
        device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: bufferOptions)
    })
    let empty = try #require(device.makeBuffer(length: byteCount, options: bufferOptions))
    empty.contents().initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    #if os(macOS)
    if upload.storageMode == .managed {
        upload.didModifyRange(NSRange(location: 0, length: byteCount))
        empty.didModifyRange(NSRange(location: 0, length: byteCount))
    }
    #endif
    let readback = try #require(device.makeBuffer(length: byteCount, options: bufferOptions))

    func texture(usage: MTLTextureUsage) throws -> any MTLTexture {
        // Use linear storage with an sRGB view because older GPUs cannot allocate writable sRGB textures.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                 width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = usage.union(.pixelFormatView)
        let storage = try #require(device.makeTexture(descriptor: descriptor))
        if format == .bgra8Unorm { return storage }
        return try #require(storage.makeTextureView(pixelFormat: format))
    }
    let source = try texture(usage: .shaderRead)
    let target = try texture(usage: .shaderWrite)
    let renderer = WaterLensRenderer()
    renderer.prepare(device: device)

    func render(_ frame: WaterLensFrame) throws -> (usedShader: Bool, pixels: [UInt8]) {
        let commands = try #require(queue.makeCommandBuffer())
        let input = try #require(commands.makeBlitCommandEncoder())
        input.copy(from: upload, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: 0,
                   sourceSize: size, to: source, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
        // Transparent black exposes pixels left unwritten by either path.
        input.copy(from: empty, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: 0,
                   sourceSize: size, to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
        input.endEncoding()

        renderer.update(frame)
        let usedShader = renderer.encode(commandBuffer: commands, source: source, target: target)
        let output = try #require(commands.makeBlitCommandEncoder())
        output.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size,
                    to: readback, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: 0)
        #if os(macOS)
        if readback.storageMode == .managed { output.synchronize(resource: readback) }
        #endif
        output.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        try #require(commands.status == .completed, "Water lens GPU command failed: \(String(describing: commands.error))")
        let pixels = Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self), count: byteCount))
        return (usedShader, pixels)
    }

    let spray = WaterSpray(round: 1, startTick: 100)
    let wet = try render(WaterLensFrame(spray: spray, tick: spray.impactTick))
    try #require(wet.usedShader, "The wet frame must execute the bundled Metal shader, not its fallback copy")
    #expect(wet.pixels != checkerboard)
    #expect(stride(from: 3, to: byteCount, by: 4).allSatisfy { wet.pixels[$0] == 255 },
            "The shader fills every pixel and retains opaque scene alpha")
    #expect((0..<3).allSatisfy { abs(Int(wet.pixels[$0]) - 32) <= 1 },
            "The clear corner retains its brightness, including through an sRGB output view")
    #expect(stride(from: 0, to: byteCount, by: 4).contains { offset in
        (60...195).contains(Int(wet.pixels[offset]))
            && (60...195).contains(Int(wet.pixels[offset + 1]))
            && (60...195).contains(Int(wet.pixels[offset + 2]))
    }, "Refraction resamples the checkerboard edges into intermediate colors")

    let dry = try render(WaterLensFrame(spray: spray, tick: spray.endTick))
    #expect(!dry.usedShader)
    #expect(dry.pixels == checkerboard, "A fully dry frame copies the source exactly")
}
#endif
