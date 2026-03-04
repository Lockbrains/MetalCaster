#if canImport(CoreText)
import Metal
import simd
import MetalCasterCore

/// Renders SDF text using the FontAtlas. Generates per-character quads
/// and draws them in a single batched draw call.
public final class TextRenderer {

    /// Per-vertex data for text quads.
    private struct TextVertex {
        var position: SIMD2<Float>
        var texCoord: SIMD2<Float>
        var color: SIMD4<Float>
    }

    private let device: MTLDevice
    private var pipeline: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private let maxQuads = 4096
    private var vertexCount = 0

    public var fontAtlas: FontAtlas?

    public init(device: MTLDevice) {
        self.device = device
        let bufferSize = maxQuads * 6 * MemoryLayout<TextVertex>.stride
        vertexBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        compilePipeline()
    }

    /// Builds text geometry for a string at a given screen position.
    /// Call before encode() for each text to render.
    public func prepare(
        text: String,
        position: SIMD2<Float>,
        scale: Float = 1.0,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        screenSize: SIMD2<Float>
    ) {
        guard let atlas = fontAtlas, let buffer = vertexBuffer else { return }

        let ptr = buffer.contents().bindMemory(to: TextVertex.self, capacity: maxQuads * 6)
        var cursor = position
        var idx = vertexCount

        let toNDC: (SIMD2<Float>) -> SIMD2<Float> = { pos in
            SIMD2<Float>(
                pos.x / screenSize.x * 2.0 - 1.0,
                1.0 - pos.y / screenSize.y * 2.0
            )
        }

        for char in text {
            guard let glyph = atlas.glyph(for: char) else {
                cursor.x += 10 * scale
                continue
            }

            guard idx + 6 <= maxQuads * 6 else { break }

            let x = cursor.x + glyph.bearing.x * scale
            let y = cursor.y - glyph.bearing.y * scale
            let w = glyph.size.x * scale
            let h = glyph.size.y * scale

            let p0 = toNDC(SIMD2<Float>(x, y))
            let p1 = toNDC(SIMD2<Float>(x + w, y))
            let p2 = toNDC(SIMD2<Float>(x + w, y + h))
            let p3 = toNDC(SIMD2<Float>(x, y + h))

            let uv0 = glyph.uvMin
            let uv1 = SIMD2<Float>(glyph.uvMax.x, glyph.uvMin.y)
            let uv2 = glyph.uvMax
            let uv3 = SIMD2<Float>(glyph.uvMin.x, glyph.uvMax.y)

            ptr[idx]     = TextVertex(position: p0, texCoord: uv0, color: color)
            ptr[idx + 1] = TextVertex(position: p1, texCoord: uv1, color: color)
            ptr[idx + 2] = TextVertex(position: p2, texCoord: uv2, color: color)
            ptr[idx + 3] = TextVertex(position: p0, texCoord: uv0, color: color)
            ptr[idx + 4] = TextVertex(position: p2, texCoord: uv2, color: color)
            ptr[idx + 5] = TextVertex(position: p3, texCoord: uv3, color: color)

            idx += 6
            cursor.x += glyph.advance * scale
        }

        vertexCount = idx
    }

    /// Resets the vertex buffer for a new frame.
    public func beginFrame() {
        vertexCount = 0
    }

    /// Encodes all prepared text draws into the given render command encoder.
    public func encode(encoder: MTLRenderCommandEncoder) {
        guard let pipeline = pipeline,
              let buffer = vertexBuffer,
              let atlas = fontAtlas?.texture,
              vertexCount > 0 else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }

    // MARK: - Internal

    private func compilePipeline() {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct TextVertex {
            float2 position;
            float2 texCoord;
            float4 color;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
            float4 color;
        };

        vertex VertexOut text_vertex(const device TextVertex *vertices [[buffer(0)]],
                                      uint vid [[vertex_id]]) {
            VertexOut out;
            TextVertex v = vertices[vid];
            out.position = float4(v.position, 0, 1);
            out.texCoord = v.texCoord;
            out.color = v.color;
            return out;
        }

        fragment float4 text_fragment(VertexOut in [[stage_in]],
                                       texture2d<float> sdfTexture [[texture(0)]]) {
            constexpr sampler s(address::clamp_to_edge, filter::linear);
            float dist = sdfTexture.sample(s, in.texCoord).r;
            float alpha = smoothstep(0.4, 0.6, dist);
            return float4(in.color.rgb, in.color.a * alpha);
        }
        """

        guard let lib = try? device.makeLibrary(source: source, options: nil),
              let vf = lib.makeFunction(name: "text_vertex"),
              let ff = lib.makeFunction(name: "text_fragment") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vf
        desc.fragmentFunction = ff
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }
}
#endif
