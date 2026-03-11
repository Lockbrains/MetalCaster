import Foundation
import Metal
import simd

/// Atmospheric scattering sky dome renderer using Rayleigh + Mie models.
public final class AtmosphereRenderer: @unchecked Sendable {

    private let device: MTLDevice
    private var renderPipeline: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    public init?(device: MTLDevice) {
        self.device = device
        buildSkyDome()
        buildPipeline()
    }

    // MARK: - Sky Dome Mesh

    private func buildSkyDome() {
        let latSteps = 32
        let lonSteps = 64
        var vertices: [SIMD4<Float>] = []
        var indices: [UInt32] = []

        for lat in 0...latSteps {
            let theta = Float(lat) / Float(latSteps) * Float.pi * 0.5
            let y = sin(theta)
            let r = cos(theta)
            for lon in 0...lonSteps {
                let phi = Float(lon) / Float(lonSteps) * Float.pi * 2
                let x = r * cos(phi)
                let z = r * sin(phi)
                vertices.append(SIMD4<Float>(x, y, z, 1))
            }
        }

        let w = lonSteps + 1
        for lat in 0..<latSteps {
            for lon in 0..<lonSteps {
                let tl = UInt32(lat * w + lon)
                let tr = tl + 1
                let bl = UInt32((lat + 1) * w + lon)
                let br = bl + 1
                indices.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }

        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<SIMD4<Float>>.stride * vertices.count)
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count)
        indexCount = indices.count
    }

    // MARK: - Pipeline

    private func buildPipeline() {
        guard let library = try? device.makeLibrary(source: Self.atmosphereShaderSource, options: nil) else { return }

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = library.makeFunction(name: "atmosphereVertex")
        rpd.fragmentFunction = library.makeFunction(name: "atmosphereFragment")
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        rpd.depthAttachmentPixelFormat = .depth32Float

        renderPipeline = try? device.makeRenderPipelineState(descriptor: rpd)
    }

    // MARK: - Atmosphere Shader (Rayleigh + Mie Scattering)

    static let atmosphereShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct AtmosphereUniforms {
        float4x4 viewProjectionMatrix;
        float4   sunDirection;
        float    time;
        float    rayleighCoeff;
        float    mieCoeff;
        float    mieG;
    };

    struct AtmosphereVertexOut {
        float4 position [[position]];
        float3 direction;
    };

    vertex AtmosphereVertexOut atmosphereVertex(
        const device float4 *vertices [[buffer(0)]],
        constant AtmosphereUniforms &u [[buffer(1)]],
        uint vid [[vertex_id]]
    ) {
        float4 v = vertices[vid];
        float3 dir = v.xyz * 1000.0;

        AtmosphereVertexOut out;
        out.position = u.viewProjectionMatrix * float4(dir, 1.0);
        out.position.z = out.position.w;
        out.direction = v.xyz;
        return out;
    }

    fragment float4 atmosphereFragment(
        AtmosphereVertexOut in [[stage_in]],
        constant AtmosphereUniforms &u [[buffer(1)]]
    ) {
        float3 dir = normalize(in.direction);
        float3 sunDir = normalize(-u.sunDirection.xyz);
        float sunAngle = max(dot(dir, sunDir), 0.0);

        // Rayleigh scattering (blue sky)
        float3 rayleighColor = float3(0.3, 0.5, 1.0);
        float rayleigh = u.rayleighCoeff * (1.0 + sunAngle * sunAngle);

        // Mie scattering (sun halo)
        float g = u.mieG;
        float miePhase = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * sunAngle, 1.5);
        float3 mieColor = float3(1.0, 0.95, 0.85);
        float mie = u.mieCoeff * miePhase;

        // Horizon blend
        float horizon = 1.0 - max(dir.y, 0.0);
        horizon = horizon * horizon;

        float3 skyColor = rayleighColor * rayleigh + mieColor * mie;

        // Sunset colors near horizon
        float3 sunsetColor = float3(1.0, 0.5, 0.2);
        float sunsetBlend = pow(horizon, 4.0) * max(sunDir.y + 0.1, 0.0);
        skyColor = mix(skyColor, sunsetColor, sunsetBlend * 0.5);

        // Darken toward zenith
        float zenith = max(dir.y, 0.0);
        skyColor *= (0.4 + 0.6 * zenith);

        skyColor = clamp(skyColor, 0.0, 1.5);

        return float4(skyColor, 1.0);
    }
    """
}
