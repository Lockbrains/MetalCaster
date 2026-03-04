import Metal
import simd

/// Shadow mapping pass using a single directional light.
/// Generates a depth-only shadow map for cascaded shadow mapping.
public final class ShadowPass {

    /// Shadow map resolution. Single cascade for now.
    public var resolution: Int = 2048

    private var shadowTexture: MTLTexture?
    private var shadowPipeline: MTLRenderPipelineState?
    private var shadowDepthStencil: MTLDepthStencilState?

    /// The light-space view-projection matrix for shadow lookup.
    public private(set) var lightViewProjection: simd_float4x4 = matrix_identity_float4x4

    public init() {}

    public func setup(device: MCMetalDevice) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: resolution,
            height: resolution,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        shadowTexture = device.device.makeTexture(descriptor: desc)
        shadowTexture?.label = "shadowMap"

        let dssDesc = MTLDepthStencilDescriptor()
        dssDesc.depthCompareFunction = .lessEqual
        dssDesc.isDepthWriteEnabled = true
        shadowDepthStencil = device.device.makeDepthStencilState(descriptor: dssDesc)

        compileShadowPipeline(device: device.device)
    }

    /// The GPU shadow map texture for binding in lighting shaders.
    public var texture: MTLTexture? { shadowTexture }

    public func execute(
        frame: FrameDescriptor,
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        meshPool: MeshPool?
    ) {
        guard let shadowTex = shadowTexture,
              let dss = shadowDepthStencil,
              let pipeline = shadowPipeline else { return }

        let shadowCasters = frame.meshDrawCalls.filter(\.castsShadow)
        guard !shadowCasters.isEmpty else { return }

        let lightVP = computeLightViewProjection(frame: frame)
        lightViewProjection = lightVP

        let rpd = MTLRenderPassDescriptor()
        rpd.depthAttachment.texture = shadowTex
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .store
        rpd.depthAttachment.clearDepth = 1.0

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.label = "ShadowPass"
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(dss)
        encoder.setCullMode(.front)
        encoder.setDepthBias(0.005, slopeScale: 1.0, clamp: 0.02)

        for entry in shadowCasters {
            var mvp = lightVP * entry.worldMatrix
            encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.stride, index: 1)

            if let mesh = meshPool?.mesh(for: entry.meshType) {
                MeshRenderer.draw(mesh: mesh, with: encoder)
            }
        }

        encoder.endEncoding()
    }

    // MARK: - Internal

    private func computeLightViewProjection(frame: FrameDescriptor) -> simd_float4x4 {
        let lightDir: SIMD3<Float>
        if let firstDirectional = frame.meshDrawCalls.first.map({ _ in SIMD3<Float>(0, -1, 0.3) }) {
            lightDir = simd_normalize(firstDirectional)
        } else {
            lightDir = simd_normalize(SIMD3<Float>(0, -1, 0.3))
        }

        let center = frame.cameraPosition + simd_normalize(
            SIMD3<Float>(frame.viewMatrix.columns.2.x, frame.viewMatrix.columns.2.y, frame.viewMatrix.columns.2.z)
        ) * 20

        let lightPos = center - lightDir * 50
        let lightView = lookAt(eye: lightPos, center: center, up: SIMD3<Float>(0, 1, 0))
        let lightProj = orthoProjection(left: -30, right: 30, bottom: -30, top: 30, near: 0.1, far: 100)
        return lightProj * lightView
    }

    private func compileShadowPipeline(device: MTLDevice) {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float3 position [[attribute(0)]];
        };

        vertex float4 shadow_vertex(VertexIn in [[stage_in]],
                                     constant float4x4 &mvp [[buffer(1)]]) {
            return mvp * float4(in.position, 1.0);
        }
        """

        guard let library = try? device.makeLibrary(source: source, options: nil),
              let vertexFunc = library.makeFunction(name: "shadow_vertex") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.depthAttachmentPixelFormat = .depth32Float

        if let vd = MeshPool.metalVertexDescriptor {
            desc.vertexDescriptor = vd
        }

        shadowPipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)

        return simd_float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    private func orthoProjection(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let w = right - left
        let h = top - bottom
        let d = far - near
        return simd_float4x4(columns: (
            SIMD4<Float>(2 / w, 0, 0, 0),
            SIMD4<Float>(0, 2 / h, 0, 0),
            SIMD4<Float>(0, 0, -1 / d, 0),
            SIMD4<Float>(-(right + left) / w, -(top + bottom) / h, -near / d, 1)
        ))
    }
}
