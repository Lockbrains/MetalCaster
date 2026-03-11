import Foundation
import Metal
import MetalKit
import simd
import MetalCasterRenderer

final class SceneComposerProRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // Terrain mesh
    private var terrainVertexBuffer: MTLBuffer?
    private var terrainIndexBuffer: MTLBuffer?
    private var terrainIndexCount: Int = 0

    // Heightmap
    private var heightmapTexture: MTLTexture?
    private var heightmapResolution: Int = 512

    // Pipelines
    private var terrainRenderPipeline: MTLRenderPipelineState?
    private var heightmapComputePipeline: MTLComputePipelineState?
    private var erosionComputePipeline: MTLComputePipelineState?
    private var normalComputePipeline: MTLComputePipelineState?
    private var brushComputePipeline: MTLComputePipelineState?
    private var gridRenderPipeline: MTLRenderPipelineState?
    private var skyRenderPipeline: MTLRenderPipelineState?
    private var waterRenderPipeline: MTLRenderPipelineState?
    private var depthStencilState: MTLDepthStencilState?
    private var depthStencilNoWrite: MTLDepthStencilState?

    // Normal map
    private var normalMapTexture: MTLTexture?

    // Camera
    var cameraYaw: Float = 0.6
    var cameraPitch: Float = 0.85
    var cameraDistance: Float = 280
    var cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 8, 0)
    var worldSize: SIMD2<Float> = SIMD2<Float>(200, 200)
    var maxHeight: Float = 30

    // Noise
    var noiseFrequency: Float = 1.0
    var noiseAmplitude: Float = 1.0
    var noiseOctaves: Int = 4
    var noiseSeed: UInt32 = 0
    var needsHeightmapRegeneration: Bool = true

    // Erosion
    var erosionIterations: Int = 50000
    var erosionStrength: Float = 1.0
    var erosionEnabled: Bool = false
    var needsErosion: Bool = false

    // Brush
    var pendingBrushStrokes: [BrushStroke] = []

    // Selection
    var selectedPosition: SIMD3<Float>? = nil

    // Water
    var waterLevel: Float = 5.0
    var showWater: Bool = false
    var waterDeepColor: SIMD3<Float> = SIMD3<Float>(0.02, 0.08, 0.18)
    var waterShallowColor: SIMD3<Float> = SIMD3<Float>(0.05, 0.25, 0.35)
    var waterOpacity: Float = 0.75
    var waterWaveScale: Float = 1.0
    var waterWaveSpeed: Float = 1.0

    // Sky
    var sunAltitude: Float = 0.4
    var sunAzimuth: Float = 0.8
    var fogDensity: Float = 0.002

    // Grid
    private var gridVertexBuffer: MTLBuffer?
    private var gridVertexCount: Int = 0

    // Water mesh
    private var waterVertexBuffer: MTLBuffer?

    init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)
        mtkView.delegate = self

        buildPipelines()
        buildGrid()
        buildTerrainMesh(resolution: 256)
        buildWaterMesh()
        createHeightmapTexture(resolution: heightmapResolution)
    }

    // MARK: - Pipeline Setup

    private func buildPipelines() {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            print("[SceneComposerProRenderer] Shader compile error: \(error)")
            return
        }

        // Terrain render
        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = library.makeFunction(name: "terrainVertex")
        rpd.fragmentFunction = library.makeFunction(name: "terrainFragment")
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        rpd.depthAttachmentPixelFormat = .depth32Float
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float2; vd.attributes[1].offset = 12; vd.attributes[1].bufferIndex = 0
        vd.layouts[0].stride = 20
        rpd.vertexDescriptor = vd
        terrainRenderPipeline = try? device.makeRenderPipelineState(descriptor: rpd)

        // Grid render
        let gpd = MTLRenderPipelineDescriptor()
        gpd.vertexFunction = library.makeFunction(name: "gridVertex")
        gpd.fragmentFunction = library.makeFunction(name: "gridFragment")
        gpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        gpd.colorAttachments[0].isBlendingEnabled = true
        gpd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        gpd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        gpd.depthAttachmentPixelFormat = .depth32Float
        gridRenderPipeline = try? device.makeRenderPipelineState(descriptor: gpd)

        // Sky render (fullscreen triangle, no vertex descriptor)
        let spd = MTLRenderPipelineDescriptor()
        spd.vertexFunction = library.makeFunction(name: "skyVertex")
        spd.fragmentFunction = library.makeFunction(name: "skyFragment")
        spd.colorAttachments[0].pixelFormat = .bgra8Unorm
        spd.depthAttachmentPixelFormat = .depth32Float
        skyRenderPipeline = try? device.makeRenderPipelineState(descriptor: spd)

        // Water render (alpha blended)
        let wpd = MTLRenderPipelineDescriptor()
        wpd.vertexFunction = library.makeFunction(name: "waterVertex")
        wpd.fragmentFunction = library.makeFunction(name: "waterFragment")
        wpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        wpd.colorAttachments[0].isBlendingEnabled = true
        wpd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        wpd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        wpd.colorAttachments[0].sourceAlphaBlendFactor = .one
        wpd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        wpd.depthAttachmentPixelFormat = .depth32Float
        waterRenderPipeline = try? device.makeRenderPipelineState(descriptor: wpd)

        // Compute pipelines
        if let f = library.makeFunction(name: "generateHeightmap") {
            heightmapComputePipeline = try? device.makeComputePipelineState(function: f)
        }
        if let f = library.makeFunction(name: "hydraulicErosion") {
            erosionComputePipeline = try? device.makeComputePipelineState(function: f)
        }
        if let f = library.makeFunction(name: "computeNormalMap") {
            normalComputePipeline = try? device.makeComputePipelineState(function: f)
        }
        if let f = library.makeFunction(name: "applyBrushStroke") {
            brushComputePipeline = try? device.makeComputePipelineState(function: f)
        }

        // Depth stencil states
        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .less
        dsd.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: dsd)

        let dsdNoWrite = MTLDepthStencilDescriptor()
        dsdNoWrite.depthCompareFunction = .always
        dsdNoWrite.isDepthWriteEnabled = false
        depthStencilNoWrite = device.makeDepthStencilState(descriptor: dsdNoWrite)
    }

    // MARK: - Textures

    private func createHeightmapTexture(resolution: Int) {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: resolution, height: resolution, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]
        td.storageMode = .private
        heightmapTexture = device.makeTexture(descriptor: td)

        let nd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: resolution, height: resolution, mipmapped: false)
        nd.usage = [.shaderRead, .shaderWrite]
        nd.storageMode = .private
        normalMapTexture = device.makeTexture(descriptor: nd)

        heightmapResolution = resolution
        needsHeightmapRegeneration = true
    }

    // MARK: - Mesh Builders

    private func buildTerrainMesh(resolution: Int) {
        var floats: [Float] = []
        floats.reserveCapacity((resolution + 1) * (resolution + 1) * 5)
        var indices: [UInt32] = []
        indices.reserveCapacity(resolution * resolution * 6)
        let step = 1.0 / Float(resolution)

        for z in 0...resolution {
            for x in 0...resolution {
                let u = Float(x) * step
                let v = Float(z) * step
                floats.append(u - 0.5)
                floats.append(0)
                floats.append(v - 0.5)
                floats.append(u)
                floats.append(v)
            }
        }
        let w = resolution + 1
        for z in 0..<resolution {
            for x in 0..<resolution {
                let tl = UInt32(z * w + x)
                let tr = tl + 1
                let bl = UInt32((z + 1) * w + x)
                let br = bl + 1
                indices.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }
        terrainVertexBuffer = device.makeBuffer(bytes: floats, length: MemoryLayout<Float>.stride * floats.count, options: .storageModeShared)
        terrainIndexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count, options: .storageModeShared)
        terrainIndexCount = indices.count
    }

    private func buildGrid() {
        var verts: [SIMD4<Float>] = []
        let gridSize: Float = 500
        let spacing: Float = 10
        let halfGrid = gridSize / 2
        var i: Float = -halfGrid
        while i <= halfGrid {
            verts.append(SIMD4<Float>(i, 0, -halfGrid, 1))
            verts.append(SIMD4<Float>(i, 0,  halfGrid, 1))
            verts.append(SIMD4<Float>(-halfGrid, 0, i, 1))
            verts.append(SIMD4<Float>( halfGrid, 0, i, 1))
            i += spacing
        }
        gridVertexCount = verts.count
        gridVertexBuffer = device.makeBuffer(bytes: verts, length: MemoryLayout<SIMD4<Float>>.stride * verts.count, options: .storageModeShared)
    }

    private func buildWaterMesh() {
        let h: Float = 500
        let verts: [Float] = [
            -h, 0, -h,  0, 0,
             h, 0, -h,  1, 0,
             h, 0,  h,  1, 1,
            -h, 0, -h,  0, 0,
             h, 0,  h,  1, 1,
            -h, 0,  h,  0, 1,
        ]
        waterVertexBuffer = device.makeBuffer(bytes: verts, length: MemoryLayout<Float>.stride * verts.count, options: .storageModeShared)
    }

    // MARK: - Brush API

    func queueBrushStroke(worldPos: SIMD3<Float>, radius: Float, strength: Float, mode: ComposerBrushMode, falloff: Float) {
        let u = (worldPos.x / worldSize.x) + 0.5
        let v = (worldPos.z / worldSize.y) + 0.5
        guard u >= 0 && u <= 1 && v >= 0 && v <= 1 else { return }

        let uvRadius = radius / max(worldSize.x, worldSize.y)
        let modeInt: Int32
        switch mode {
        case .raise:   modeInt = 0
        case .lower:   modeInt = 1
        case .smooth:  modeInt = 2
        case .flatten: modeInt = 3
        default:       modeInt = 0
        }

        pendingBrushStrokes.append(BrushStroke(
            posX: u, posY: v, radius: uvRadius, strength: strength,
            mode: modeInt, falloff: falloff, targetHeight: 0.5, resolution: Int32(heightmapResolution)
        ))
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = MTLSize(width: (heightmapResolution + 15) / 16, height: (heightmapResolution + 15) / 16, depth: 1)

        // -- Compute passes --

        if needsHeightmapRegeneration, let heightmap = heightmapTexture, let pipeline = heightmapComputePipeline {
            if let enc = commandBuffer.makeComputeCommandEncoder() {
                enc.setComputePipelineState(pipeline)
                enc.setTexture(heightmap, index: 0)
                var params = HeightmapParams(frequency: noiseFrequency, amplitude: noiseAmplitude, octaves: Int32(noiseOctaves), seed: noiseSeed, resolution: Int32(heightmapResolution))
                enc.setBytes(&params, length: MemoryLayout<HeightmapParams>.size, index: 0)
                enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
                enc.endEncoding()
            }
            needsHeightmapRegeneration = false
            needsErosion = erosionEnabled
        }

        if needsErosion, let heightmap = heightmapTexture, let pipeline = erosionComputePipeline {
            if let enc = commandBuffer.makeComputeCommandEncoder() {
                enc.setComputePipelineState(pipeline)
                enc.setTexture(heightmap, index: 0)
                var params = ErosionParams(iterations: Int32(min(erosionIterations, 1024)), strength: erosionStrength, resolution: Int32(heightmapResolution))
                enc.setBytes(&params, length: MemoryLayout<ErosionParams>.size, index: 0)
                enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
                enc.endEncoding()
            }
            needsErosion = false
        }

        // Brush strokes
        if !pendingBrushStrokes.isEmpty, let heightmap = heightmapTexture, let pipeline = brushComputePipeline {
            for var stroke in pendingBrushStrokes {
                if let enc = commandBuffer.makeComputeCommandEncoder() {
                    enc.setComputePipelineState(pipeline)
                    enc.setTexture(heightmap, index: 0)
                    enc.setBytes(&stroke, length: MemoryLayout<BrushStroke>.size, index: 0)
                    enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
                    enc.endEncoding()
                }
            }
            pendingBrushStrokes.removeAll()
        }

        // Recompute normals every frame (cheap on GPU)
        if let heightmap = heightmapTexture, let normalMap = normalMapTexture, let pipeline = normalComputePipeline {
            if let enc = commandBuffer.makeComputeCommandEncoder() {
                enc.setComputePipelineState(pipeline)
                enc.setTexture(heightmap, index: 0)
                enc.setTexture(normalMap, index: 1)
                var res = Int32(heightmapResolution)
                enc.setBytes(&res, length: MemoryLayout<Int32>.size, index: 0)
                enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
                enc.endEncoding()
            }
        }

        // -- Render pass --

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        var uniforms = makeUniforms(aspect: aspect)

        // Sky (fullscreen, behind everything)
        if let skyPipeline = skyRenderPipeline {
            renderEncoder.setDepthStencilState(depthStencilNoWrite)
            renderEncoder.setRenderPipelineState(skyPipeline)
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.size, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        renderEncoder.setDepthStencilState(depthStencilState)

        // Grid
        if let gridPipeline = gridRenderPipeline, let gridVB = gridVertexBuffer {
            renderEncoder.setRenderPipelineState(gridPipeline)
            renderEncoder.setVertexBuffer(gridVB, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.size, index: 1)
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridVertexCount)
        }

        // Terrain
        if let terrainPipeline = terrainRenderPipeline, let vb = terrainVertexBuffer, let ib = terrainIndexBuffer, let heightmap = heightmapTexture {
            renderEncoder.setRenderPipelineState(terrainPipeline)
            renderEncoder.setVertexBuffer(vb, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.size, index: 1)
            renderEncoder.setVertexTexture(heightmap, index: 0)
            var tp = TerrainRenderParams(worldSize: worldSize, maxHeight: maxHeight)
            renderEncoder.setVertexBytes(&tp, length: MemoryLayout<TerrainRenderParams>.size, index: 2)
            renderEncoder.setFragmentBytes(&tp, length: MemoryLayout<TerrainRenderParams>.size, index: 0)
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.size, index: 1)
            var sel = selectedPosition.map { SelectionParams(posX: $0.x, posY: $0.y, posZ: $0.z, radius: 5.0, isActive: 1.0) }
                ?? SelectionParams(posX: 0, posY: 0, posZ: 0, radius: 0, isActive: 0)
            renderEncoder.setFragmentBytes(&sel, length: MemoryLayout<SelectionParams>.size, index: 2)
            if let normalMap = normalMapTexture { renderEncoder.setFragmentTexture(normalMap, index: 0) }
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: terrainIndexCount, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
        }

        // Water
        if showWater, let waterPipeline = waterRenderPipeline, let waterVB = waterVertexBuffer {
            renderEncoder.setRenderPipelineState(waterPipeline)
            renderEncoder.setVertexBuffer(waterVB, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.size, index: 1)
            var wp = WaterParams(
                deepR: waterDeepColor.x, deepG: waterDeepColor.y, deepB: waterDeepColor.z, waterLevel: waterLevel,
                shallowR: waterShallowColor.x, shallowG: waterShallowColor.y, shallowB: waterShallowColor.z, opacity: waterOpacity,
                waveScale: waterWaveScale, waveSpeed: waterWaveSpeed
            )
            renderEncoder.setVertexBytes(&wp, length: MemoryLayout<WaterParams>.size, index: 2)
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.size, index: 0)
            renderEncoder.setFragmentBytes(&wp, length: MemoryLayout<WaterParams>.size, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Hit Testing

    func hitTest(screenPoint: NSPoint, viewSize: CGSize) -> SIMD3<Float>? {
        let aspect = Float(viewSize.width / viewSize.height)
        let eye = cameraEyePosition()
        let ndcX = Float(screenPoint.x / viewSize.width) * 2.0 - 1.0
        let ndcY = Float(screenPoint.y / viewSize.height) * 2.0 - 1.0

        let proj = perspectiveProjection(fovY: Float.pi / 4, aspect: aspect, near: 1.0, far: 5000)
        let view = lookAt(eye: eye, center: cameraTarget, up: SIMD3<Float>(0, 1, 0))
        let invVP = (proj * view).inverse

        let near4 = invVP * SIMD4<Float>(ndcX, ndcY, -1, 1)
        let far4  = invVP * SIMD4<Float>(ndcX, ndcY,  1, 1)
        let nearW = SIMD3<Float>(near4.x, near4.y, near4.z) / near4.w
        let farW  = SIMD3<Float>(far4.x, far4.y, far4.z) / far4.w
        let rayDir = normalize(farW - nearW)

        let planeY = maxHeight * 0.3
        guard abs(rayDir.y) > 1e-6 else { return nil }
        let t = (planeY - nearW.y) / rayDir.y
        guard t > 0 else { return nil }

        let hit = nearW + rayDir * t
        let halfW = worldSize.x * 0.5
        let halfD = worldSize.y * 0.5
        guard hit.x >= -halfW && hit.x <= halfW && hit.z >= -halfD && hit.z <= halfD else { return nil }
        return hit
    }

    func cameraEyePosition() -> SIMD3<Float> {
        cameraTarget + SIMD3<Float>(
            cameraDistance * cos(cameraPitch) * sin(cameraYaw),
            cameraDistance * sin(cameraPitch),
            cameraDistance * cos(cameraPitch) * cos(cameraYaw)
        )
    }

    // MARK: - Camera Math

    private func makeUniforms(aspect: Float) -> TerrainUniforms {
        let eye = cameraEyePosition()
        let view = lookAt(eye: eye, center: cameraTarget, up: SIMD3<Float>(0, 1, 0))
        let proj = perspectiveProjection(fovY: Float.pi / 4, aspect: aspect, near: 1.0, far: 5000)
        let sunDir = SIMD3<Float>(
            -cos(sunAltitude) * sin(sunAzimuth),
            -sin(sunAltitude),
            -cos(sunAltitude) * cos(sunAzimuth)
        )
        return TerrainUniforms(
            viewProjectionMatrix: proj * view, modelMatrix: matrix_identity_float4x4,
            cameraPosition: SIMD4<Float>(eye, 1),
            lightDirection: SIMD4<Float>(normalize(sunDir), 0),
            time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))
        )
    }
}

// MARK: - GPU Structs (all packed floats to avoid SIMD alignment traps)

struct BrushStroke {
    var posX: Float
    var posY: Float
    var radius: Float
    var strength: Float
    var mode: Int32
    var falloff: Float
    var targetHeight: Float
    var resolution: Int32
}

private struct TerrainUniforms {
    var viewProjectionMatrix: float4x4
    var modelMatrix: float4x4
    var cameraPosition: SIMD4<Float>
    var lightDirection: SIMD4<Float>
    var time: Float
    var _pad: SIMD3<Float> = .zero
}

private struct HeightmapParams {
    var frequency: Float; var amplitude: Float; var octaves: Int32; var seed: UInt32
    var resolution: Int32; var _pad: SIMD3<Float> = .zero
}

private struct ErosionParams {
    var iterations: Int32; var strength: Float; var resolution: Int32; var _pad: Float = 0
}

private struct TerrainRenderParams {
    var worldSize: SIMD2<Float>; var maxHeight: Float; var _pad: Float = 0
}

private struct SelectionParams {
    var posX: Float; var posY: Float; var posZ: Float; var radius: Float
    var isActive: Float; var _pad1: Float = 0; var _pad2: Float = 0; var _pad3: Float = 0
}

private struct WaterParams {
    var deepR: Float; var deepG: Float; var deepB: Float; var waterLevel: Float
    var shallowR: Float; var shallowG: Float; var shallowB: Float; var opacity: Float
    var waveScale: Float; var waveSpeed: Float; var _pad1: Float = 0; var _pad2: Float = 0
}

// MARK: - Matrix Helpers

private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let f = normalize(center - eye); let s = normalize(cross(f, up)); let u = cross(s, f)
    var m = matrix_identity_float4x4
    m[0][0] =  s.x; m[1][0] =  s.y; m[2][0] =  s.z; m[3][0] = -dot(s, eye)
    m[0][1] =  u.x; m[1][1] =  u.y; m[2][1] =  u.z; m[3][1] = -dot(u, eye)
    m[0][2] = -f.x; m[1][2] = -f.y; m[2][2] = -f.z; m[3][2] =  dot(f, eye)
    return m
}

private func perspectiveProjection(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
    let yScale = 1 / tan(fovY * 0.5); let xScale = yScale / aspect; let zRange = far - near
    var m = float4x4(0)
    m[0][0] = xScale; m[1][1] = yScale
    m[2][2] = -(far + near) / zRange; m[2][3] = -1; m[3][2] = -2 * far * near / zRange
    return m
}

// MARK: - Embedded MSL Shaders

extension SceneComposerProRenderer {
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct TerrainUniforms {
        float4x4 viewProjectionMatrix;
        float4x4 modelMatrix;
        float4   cameraPosition;
        float4   lightDirection;
        float    time;
        float3   _pad;
    };
    struct TerrainRenderParams { float2 worldSize; float maxHeight; float _pad; };
    struct HeightmapParams { float frequency; float amplitude; int octaves; uint seed; int resolution; float3 _pad; };
    struct ErosionParams { int iterations; float strength; int resolution; float _pad; };
    struct SelectionParams { float posX; float posY; float posZ; float radius; float isActive; float _p1; float _p2; float _p3; };
    struct BrushStrokeParams { float posX; float posY; float radius; float strength; int mode; float falloff; float targetHeight; int resolution; };

    // ── Noise ──

    float hash2D(float2 p, uint seed) {
        float h = dot(p, float2(127.1 + float(seed), 311.7 + float(seed)));
        return fract(sin(h) * 43758.5453123);
    }
    float gradientNoise(float2 p, uint seed) {
        float2 i = floor(p); float2 f = fract(p); float2 u = f*f*(3.0-2.0*f);
        float a = hash2D(i, seed), b = hash2D(i+float2(1,0), seed);
        float c = hash2D(i+float2(0,1), seed), d = hash2D(i+float2(1,1), seed);
        return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
    }
    float fbmNoise(float2 p, int oct, float freq, float amp, uint seed) {
        float v=0, f=freq, a=amp;
        for(int i=0;i<oct&&i<12;i++){v+=a*gradientNoise(p*f,seed+uint(i));f*=2;a*=0.5;}
        return v;
    }
    float ridgedNoise(float2 p, int oct, float freq, float amp, uint seed) {
        float v=0, f=freq, a=amp;
        for(int i=0;i<oct&&i<12;i++){float n=gradientNoise(p*f,seed+uint(i));n=1-abs(n*2-1);v+=a*n*n;f*=2;a*=0.5;}
        return v;
    }

    // ── Compute: Heightmap ──

    kernel void generateHeightmap(texture2d<float, access::write> out [[texture(0)]], constant HeightmapParams &p [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if(gid.x>=uint(p.resolution)||gid.y>=uint(p.resolution)) return;
        float2 uv = float2(gid)/float(p.resolution);
        float h = fbmNoise(uv, p.octaves, p.frequency, p.amplitude*0.6, p.seed);
        float r = ridgedNoise(uv, max(p.octaves-2,1), p.frequency*0.8, p.amplitude*0.25, p.seed+100u);
        h = mix(h, r, 0.25);
        float2 ed = min(uv, 1.0-uv);
        h *= smoothstep(0.0, 0.08, min(ed.x, ed.y));
        out.write(float4(clamp(h,0.0,1.0), 0,0,1), gid);
    }

    // ── Compute: Erosion ──

    kernel void hydraulicErosion(texture2d<float, access::read_write> hm [[texture(0)]], constant ErosionParams &p [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        int res=p.resolution;
        if(int(gid.x)>=res||int(gid.y)>=res||int(gid.x)<1||int(gid.y)<1||int(gid.x)>=res-1||int(gid.y)>=res-1) return;
        float h=hm.read(gid).r;
        float avg=(hm.read(uint2(gid.x-1,gid.y)).r+hm.read(uint2(gid.x+1,gid.y)).r+hm.read(uint2(gid.x,gid.y-1)).r+hm.read(uint2(gid.x,gid.y+1)).r)*0.25;
        hm.write(float4(clamp(h-(h-avg)*p.strength*0.01,0.0,1.0),0,0,1), gid);
    }

    // ── Compute: Normal Map ──

    kernel void computeNormalMap(texture2d<float, access::read> hm [[texture(0)]], texture2d<float, access::write> nm [[texture(1)]], constant int &res [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if(int(gid.x)>=res||int(gid.y)>=res) return;
        float hL=hm.read(uint2(max(int(gid.x)-1,0),gid.y)).r;
        float hR=hm.read(uint2(min(int(gid.x)+1,res-1),gid.y)).r;
        float hU=hm.read(uint2(gid.x,max(int(gid.y)-1,0))).r;
        float hD=hm.read(uint2(gid.x,min(int(gid.y)+1,res-1))).r;
        float sc=40.0;
        float3 n = normalize(float3((hL-hR)*sc, 2.0, (hU-hD)*sc));
        nm.write(float4(n*0.5+0.5, 1.0-n.y), gid);
    }

    // ── Compute: Brush ──

    kernel void applyBrushStroke(texture2d<float, access::read_write> hm [[texture(0)]], constant BrushStrokeParams &b [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        int res = b.resolution;
        if(int(gid.x)>=res||int(gid.y)>=res) return;
        float2 uv = float2(gid)/float(res);
        float dist = length(uv - float2(b.posX, b.posY));
        if(dist > b.radius) return;

        float t = dist / b.radius;
        float weight = 1.0 - pow(t, max(b.falloff*4.0, 0.1));
        weight = smoothstep(0.0, 1.0, weight);

        float cur = hm.read(gid).r;
        float delta = b.strength * weight * 0.005;
        float nv;

        if(b.mode == 0) { nv = cur + delta; }
        else if(b.mode == 1) { nv = cur - delta; }
        else if(b.mode == 2) {
            float avg = 0; int cnt = 0;
            for(int dy=-3;dy<=3;dy++) for(int dx=-3;dx<=3;dx++) {
                int nx=int(gid.x)+dx, ny=int(gid.y)+dy;
                if(nx>=0&&nx<res&&ny>=0&&ny<res){avg+=hm.read(uint2(nx,ny)).r;cnt++;}
            }
            nv = mix(cur, avg/float(cnt), weight*b.strength*0.1);
        }
        else if(b.mode == 3) { nv = mix(cur, b.targetHeight, weight*b.strength*0.05); }
        else { nv = cur; }

        hm.write(float4(clamp(nv,0.0,1.0),0,0,1), gid);
    }

    // ── Sky ──

    struct SkyOut { float4 position [[position]]; float2 uv; };

    vertex SkyOut skyVertex(uint vid [[vertex_id]]) {
        float2 pos[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        SkyOut o; o.position = float4(pos[vid], 0.9999, 1.0); o.uv = pos[vid]*0.5+0.5;
        return o;
    }
    fragment float4 skyFragment(SkyOut in [[stage_in]], constant TerrainUniforms &u [[buffer(0)]]) {
        float t = in.uv.y;
        float3 zenith  = float3(0.06, 0.10, 0.22);
        float3 horizon = float3(0.35, 0.50, 0.72);
        float3 ground  = float3(0.02, 0.02, 0.04);
        float3 c;
        if(t>0.48) { float s = saturate((t-0.48)/0.52); c = mix(horizon, zenith, s*s); }
        else { float s = saturate(t/0.48); c = mix(ground, horizon, s*s); }

        // Sun disc
        float3 lightDir = normalize(-u.lightDirection.xyz);
        float2 sunUV = float2(0.5 + lightDir.x*0.3, 0.5 + lightDir.y*0.4 + 0.3);
        float sunDist = length(in.uv - sunUV);
        float sun = smoothstep(0.06, 0.0, sunDist);
        float glow = smoothstep(0.25, 0.0, sunDist) * 0.15;
        c += float3(1.0, 0.9, 0.7) * (sun + glow);

        return float4(c, 1.0);
    }

    // ── Terrain ──

    struct TVIn { float3 position [[attribute(0)]]; float2 uv [[attribute(1)]]; };
    struct TVOut { float4 position [[position]]; float3 worldPos; float2 uv; float height; };

    vertex TVOut terrainVertex(TVIn in [[stage_in]], constant TerrainUniforms &u [[buffer(1)]], constant TerrainRenderParams &tp [[buffer(2)]], texture2d<float> hm [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float h = hm.sample(s, in.uv).r;
        float3 wp = float3(in.position.x*tp.worldSize.x, h*tp.maxHeight, in.position.z*tp.worldSize.y);
        TVOut o; o.position = u.viewProjectionMatrix * u.modelMatrix * float4(wp,1); o.worldPos=wp; o.uv=in.uv; o.height=h;
        return o;
    }

    fragment float4 terrainFragment(TVOut in [[stage_in]], constant TerrainRenderParams &tp [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]], constant SelectionParams &sel [[buffer(2)]], texture2d<float> nm [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float4 nd = nm.sample(s, in.uv);
        float3 normal = normalize(nd.rgb*2.0-1.0);
        float slope = nd.a; float h = in.height;

        float3 sand=float3(0.76,0.70,0.50), grass=float3(0.22,0.35,0.12), rock=float3(0.38,0.33,0.28), snow=float3(0.92,0.94,0.96), dirt=float3(0.45,0.35,0.25);
        float sw=smoothstep(0.0,0.12,h)*(1-smoothstep(0.12,0.22,h));
        float gw=smoothstep(0.10,0.22,h)*(1-smoothstep(0.45,0.60,h));
        float rw=smoothstep(0.35,0.55,h)*(1-smoothstep(0.72,0.85,h));
        float snw=smoothstep(0.68,0.82,h);
        float sb=smoothstep(0.3,0.6,slope); gw*=(1-sb); snw*=(1-sb*0.7);
        float tw=max(sw+gw+rw+snw+sb*0.5, 0.001);
        float3 color = (sand*sw+grass*gw+rock*rw+snow*snw+dirt*sb*0.5)/tw;

        float3 ld=normalize(-u.lightDirection.xyz);
        float NdotL=max(dot(normal,ld),0.0);
        float3 vd=normalize(u.cameraPosition.xyz-in.worldPos);
        float3 hv=normalize(ld+vd);
        float spec=pow(max(dot(normal,hv),0.0),32.0)*0.15*snw;
        color *= (0.25 + NdotL*0.75);
        color += spec;

        // Selection marker
        if(sel.isActive > 0.5) {
            float2 fxz=float2(in.worldPos.x,in.worldPos.z), sxz=float2(sel.posX,sel.posZ);
            float d=length(fxz-sxz);
            float pulse=1.0+0.08*sin(u.time*5.0);
            float r=sel.radius*pulse;
            float ring=smoothstep(0.6,0.0,abs(d-r));
            float inner=smoothstep(0.3,0.0,abs(d-r*0.5))*0.4;
            float2 dl=fxz-sxz; float tl=r*0.35, tw2=0.25;
            float ax=step(abs(dl.y),tw2)*step(r-tl,abs(dl.x))*step(abs(dl.x),r+tl);
            float az=step(abs(dl.x),tw2)*step(r-tl,abs(dl.y))*step(abs(dl.y),r+tl);
            float ticks=max(ax,az)*0.7;
            float ctr=smoothstep(0.8,0.0,d)*0.5;
            float sa=max(max(ring*0.85,inner),max(ticks,ctr));
            float3 sc=float3(0.95,0.55,0.15);
            color=mix(color,sc,sa);
            color=mix(color,sc,smoothstep(r+1.0,r-2.0,d)*0.04);
        }
        return float4(color, 1.0);
    }

    // ── Water ──

    struct WaterParams { float deepR; float deepG; float deepB; float waterLevel; float shallowR; float shallowG; float shallowB; float opacity; float waveScale; float waveSpeed; float _p1; float _p2; };
    struct WOut { float4 position [[position]]; float3 worldPos; float2 uv; };

    vertex WOut waterVertex(uint vid [[vertex_id]], const device float *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]], constant WaterParams &wp [[buffer(2)]]) {
        uint b = vid*5;
        float3 pos = float3(v[b], wp.waterLevel, v[b+2]);

        // Gerstner-style vertex displacement
        float t = u.time * wp.waveSpeed;
        float s = wp.waveScale;
        pos.y += sin(pos.x*0.08*s + t*1.1) * 0.3 * s;
        pos.y += sin(pos.z*0.06*s + t*0.8) * 0.25 * s;
        pos.y += sin((pos.x+pos.z)*0.05*s + t*1.5) * 0.15 * s;

        WOut o; o.position = u.viewProjectionMatrix * u.modelMatrix * float4(pos,1); o.worldPos=pos; o.uv=float2(v[b+3],v[b+4]);
        return o;
    }

    fragment float4 waterFragment(WOut in [[stage_in]], constant TerrainUniforms &u [[buffer(0)]], constant WaterParams &wp [[buffer(1)]]) {
        float t = u.time * wp.waveSpeed;
        float s = wp.waveScale;
        float3 pos = in.worldPos;

        // Compute analytical wave normal from multiple octaves
        float2 dh = float2(0);
        dh.x += cos(pos.x*0.08*s + t*1.1) * 0.08*s * 0.3*s;
        dh.x += cos((pos.x+pos.z)*0.05*s + t*1.5) * 0.05*s * 0.15*s;
        dh.y += cos(pos.z*0.06*s + t*0.8) * 0.06*s * 0.25*s;
        dh.y += cos((pos.x+pos.z)*0.05*s + t*1.5) * 0.05*s * 0.15*s;

        // High-frequency detail normals
        float detail1 = sin(pos.x*0.5*s + pos.z*0.3*s + t*2.0) * 0.02;
        float detail2 = sin(pos.x*0.3*s - pos.z*0.7*s + t*1.7) * 0.015;
        dh += float2(detail1, detail2);

        float3 normal = normalize(float3(-dh.x, 1.0, -dh.y));

        float3 viewDir = normalize(u.cameraPosition.xyz - pos);
        float3 lightDir = normalize(-u.lightDirection.xyz);

        // Fresnel (Schlick approximation)
        float NdotV = max(dot(normal, viewDir), 0.0);
        float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);

        // Deep vs shallow color blend based on viewing angle
        float3 deepColor = float3(wp.deepR, wp.deepG, wp.deepB);
        float3 shallowColor = float3(wp.shallowR, wp.shallowG, wp.shallowB);
        float3 waterColor = mix(shallowColor, deepColor, fresnel);

        // Ambient + diffuse lighting
        float NdotL = max(dot(normal, lightDir), 0.0);
        waterColor *= (0.4 + 0.6 * NdotL);

        // Sun specular (Blinn-Phong)
        float3 halfVec = normalize(lightDir + viewDir);
        float spec = pow(max(dot(normal, halfVec), 0.0), 256.0);
        float3 sunColor = float3(1.0, 0.95, 0.85);
        waterColor += sunColor * spec * 0.8;

        // Secondary broader specular for soft highlight
        float spec2 = pow(max(dot(normal, halfVec), 0.0), 32.0);
        waterColor += sunColor * spec2 * 0.12;

        // Sky reflection approximation
        float3 reflectDir = reflect(-viewDir, normal);
        float skyBlend = saturate(reflectDir.y * 0.5 + 0.5);
        float3 skyReflect = mix(float3(0.15, 0.25, 0.40), float3(0.05, 0.08, 0.18), skyBlend);
        waterColor = mix(waterColor, skyReflect, fresnel * 0.5);

        float alpha = mix(wp.opacity * 0.6, wp.opacity, fresnel);
        return float4(waterColor, alpha);
    }

    // ── Grid ──

    struct GOut { float4 position [[position]]; };
    vertex GOut gridVertex(const device float4 *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]], uint vid [[vertex_id]]) {
        GOut o; o.position = u.viewProjectionMatrix * u.modelMatrix * v[vid]; return o;
    }
    fragment float4 gridFragment(GOut in [[stage_in]]) { return float4(1,1,1,0.08); }
    """
}
