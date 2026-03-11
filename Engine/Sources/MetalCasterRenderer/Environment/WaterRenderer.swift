import Foundation
import Metal
import simd

/// GPU water surface rendering with animated waves and basic reflections.
public final class WaterRenderer: @unchecked Sendable {

    private let device: MTLDevice
    private var renderPipeline: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    public init?(device: MTLDevice) {
        self.device = device
        buildMesh()
        buildPipeline()
    }

    // MARK: - Mesh (flat plane subdivided for wave displacement)

    private func buildMesh() {
        struct WaterVertex {
            var position: SIMD3<Float>
            var uv: SIMD2<Float>
        }

        let resolution = 128
        let step = 1.0 / Float(resolution)
        var vertices: [WaterVertex] = []
        var indices: [UInt32] = []

        for z in 0...resolution {
            for x in 0...resolution {
                let u = Float(x) * step
                let v = Float(z) * step
                vertices.append(WaterVertex(
                    position: SIMD3<Float>(u - 0.5, 0, v - 0.5),
                    uv: SIMD2<Float>(u, v)
                ))
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

        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<WaterVertex>.stride * vertices.count)
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count)
        indexCount = indices.count
    }

    // MARK: - Pipeline

    private func buildPipeline() {
        guard let library = try? device.makeLibrary(source: Self.waterShaderSource, options: nil) else { return }

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = library.makeFunction(name: "waterVertex")
        rpd.fragmentFunction = library.makeFunction(name: "waterFragment")
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        rpd.colorAttachments[0].isBlendingEnabled = true
        rpd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        rpd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        rpd.colorAttachments[0].sourceAlphaBlendFactor = .one
        rpd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        rpd.depthAttachmentPixelFormat = .depth32Float

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float2; vd.attributes[1].offset = 12; vd.attributes[1].bufferIndex = 0
        vd.layouts[0].stride = 20
        rpd.vertexDescriptor = vd

        renderPipeline = try? device.makeRenderPipelineState(descriptor: rpd)
    }

    // MARK: - Water Shader

    static let waterShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct WaterUniforms {
        float4x4 viewProjectionMatrix;
        float4   cameraPosition;
        float    time;
        float    surfaceHeight;
        float2   extent;
        float3   waterColor;
        float    transparency;
        float    waveAmplitude;
        float    waveFrequency;
        float2   _pad;
    };

    struct WaterVertexIn {
        float3 position [[attribute(0)]];
        float2 uv       [[attribute(1)]];
    };

    struct WaterVertexOut {
        float4 position [[position]];
        float3 worldPos;
        float2 uv;
    };

    float waveHeight(float2 pos, float time, float amp, float freq) {
        float w = 0.0;
        w += sin(pos.x * freq * 1.0 + time * 1.2) * amp * 0.5;
        w += sin(pos.y * freq * 0.8 + time * 0.9) * amp * 0.3;
        w += sin((pos.x + pos.y) * freq * 0.6 + time * 1.5) * amp * 0.2;
        return w;
    }

    vertex WaterVertexOut waterVertex(
        WaterVertexIn in [[stage_in]],
        constant WaterUniforms &u [[buffer(1)]]
    ) {
        float3 worldPos = float3(
            in.position.x * u.extent.x,
            u.surfaceHeight + waveHeight(in.position.xz * u.extent, u.time, u.waveAmplitude, u.waveFrequency),
            in.position.z * u.extent.y
        );

        WaterVertexOut out;
        out.position = u.viewProjectionMatrix * float4(worldPos, 1.0);
        out.worldPos = worldPos;
        out.uv = in.uv;
        return out;
    }

    fragment float4 waterFragment(
        WaterVertexOut in [[stage_in]],
        constant WaterUniforms &u [[buffer(1)]]
    ) {
        float3 viewDir = normalize(u.cameraPosition.xyz - in.worldPos);
        float fresnel = pow(1.0 - max(dot(float3(0, 1, 0), viewDir), 0.0), 3.0);

        float3 color = u.waterColor;
        color = mix(color, float3(0.6, 0.8, 1.0), fresnel * 0.4);

        float foam = smoothstep(0.7, 1.0, sin(in.uv.x * 40.0 + u.time) * sin(in.uv.y * 40.0 + u.time * 0.7));
        color = mix(color, float3(1.0), foam * 0.15);

        float alpha = mix(u.transparency, 1.0, fresnel * 0.5);
        return float4(color, alpha);
    }
    """
}
