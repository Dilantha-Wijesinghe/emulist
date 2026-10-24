/// Metal source, compiled at runtime by `MetalContext` (no offline Metal toolchain needed).
///
/// Shaders contain no color science constants: transfer functions, matrices and the film response all
/// arrive from Swift as uniforms, 1D tables or 3D LUTs. Struct layouts mirror `RenderUniforms.swift`.
enum ShaderSource {
    static let code = #"""
    #include <metal_stdlib>
    using namespace metal;

    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler mipClamp(filter::linear, mip_filter::linear, address::repeat);

    // MARK: Input

    struct InputUniforms {
        float4 ycbcrRows[3];   // code RGB = rows · (Y', Cb, Cr)
        float4 ycbcrNorm;      // Y' = y * x - y ; C = c * z - w
        float4 workingRows[3]; // working linear = rows · camera linear
        float4 transfer;       // x: decode table size
        float4 orientation[2]; // upright output uv -> stored buffer uv (rows of a 2×3 affine)
    };

    static float decode(float v, constant float *table, float size) {
        float x = clamp(v, 0.0f, 1.0f) * (size - 1);
        int i = min(int(x), int(size) - 2);
        return mix(table[i], table[i + 1], x - float(i));
    }

    kernel void input_transform(texture2d<float, access::sample> luma [[texture(0)]],
                                texture2d<float, access::sample> chroma [[texture(1)]],
                                texture2d<float, access::write> out [[texture(2)]],
                                constant InputUniforms &u [[buffer(0)]],
                                constant float *table [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        float3 upright = float3((float2(gid) + 0.5) / float2(out.get_width(), out.get_height()), 1);
        float2 uv = float2(dot(u.orientation[0].xyz, upright), dot(u.orientation[1].xyz, upright));
        float3 ycc = float3(luma.sample(linearClamp, uv).r * u.ycbcrNorm.x - u.ycbcrNorm.y,
                            chroma.sample(linearClamp, uv).rg * u.ycbcrNorm.z - u.ycbcrNorm.w);
        float3 code = float3(dot(u.ycbcrRows[0].xyz, ycc), dot(u.ycbcrRows[1].xyz, ycc), dot(u.ycbcrRows[2].xyz, ycc));
        float n = u.transfer.x;
        float3 camera = float3(decode(code.r, table, n), decode(code.g, table, n), decode(code.b, table, n));
        float3 working = float3(dot(u.workingRows[0].xyz, camera),
                                dot(u.workingRows[1].xyz, camera),
                                dot(u.workingRows[2].xyz, camera));
        out.write(float4(working, 1), gid);
    }

    // MARK: Light effects

    struct PrefilterUniforms {
        float4 thresholds; // x: bloom luminance threshold, y: halation red threshold, z: energy limit
        float4 luminance;
    };

    // Runs at half resolution: one bilinear tap averages a 2×2 block of the source.
    kernel void effects_prefilter(texture2d<float, access::sample> src [[texture(0)]],
                                  texture2d<float, access::write> out [[texture(1)]],
                                  constant PrefilterUniforms &u [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(out.get_width(), out.get_height());
        float3 e = max(src.sample(linearClamp, uv).rgb, 0.0f);
        float l = dot(e, u.luminance.xyz);
        // Only the energy above the threshold glows, keeping the light's own hue.
        float3 bloom = e * (max(l - u.thresholds.x, 0.0f) / max(l, 1e-4f));
        float halation = max(e.r - u.thresholds.y, 0.0f);
        // Soft-limit extreme sources (sun, bare bulbs) so a single light cannot flood the frame.
        float limit = u.thresholds.z;
        bloom *= limit / (limit + dot(bloom, u.luminance.xyz));
        halation *= limit / (limit + halation);
        out.write(float4(bloom, halation), gid);
    }

    // MARK: Grain

    static uint pcg(uint v) {
        uint state = v * 747796405u + 2891336453u;
        uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
        return (word >> 22u) ^ word;
    }

    // Approximately normal (Irwin–Hall of 4 uniforms), unit variance.
    static float gaussian(uint seed) {
        float sum = 0;
        for (int i = 0; i < 4; i++) {
            seed = pcg(seed);
            sum += float(seed) * (1.0f / 4294967295.0f);
        }
        return (sum - 2.0f) * 1.7320508f;
    }

    // Deterministic per frame: the same frame index always yields the same grain.
    kernel void grain_generate(texture2d<float, access::write> out [[texture(0)]],
                               constant uint4 &seed [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        uint base = pcg(gid.x ^ pcg(gid.y ^ pcg(seed.x ^ pcg(seed.y))));
        out.write(float4(gaussian(base), gaussian(base + 0x9E3779B9u),
                         gaussian(base + 0x3C6EF372u), gaussian(base + 0xDAA66D2Bu)), gid);
    }

    // MARK: Primary grade (mirrors PrimaryGrade.apply; every constant arrives in the uniforms)

    struct GradeUniforms {
        float4 lift, gamma, gain, offset;
        float4 exposure;  // xyz: stops, w: 1 when active
        float4 space;     // x: stops floor, y: stops range, z: contrast, w: pivot
        float4 tone;      // shadow edges (xy), highlight edges (zw)
        float4 color;     // x: shadows, y: highlights, z: saturation, w: boost
        float4 density;   // x: depth, y: darkening
        float4 luminance;
    };

    static float gamma_curve(float t, float g) {
        if (g == 0 || t <= 0) return t;
        float p = exp2(-2 * g);
        return t < 1 ? pow(t, p) : 1 + (t - 1) * p;
    }

    static float spread_of(float3 e) { return max3(e.r, e.g, e.b) - min3(e.r, e.g, e.b); }

    // Log exposure (stops per channel) -> graded log exposure.
    static float3 apply_grade(float3 stops, constant GradeUniforms &g) {
        if (g.exposure.w == 0) return stops;
        float3 e = stops + g.exposure.xyz;

        float3 t = (e - g.space.x) / g.space.y;
        t += g.lift.xyz * (1 - t);
        t *= 1 + g.gain.xyz;
        t = float3(gamma_curve(t.r, g.gamma.r), gamma_curve(t.g, g.gamma.g), gamma_curve(t.b, g.gamma.b));
        t += g.offset.xyz;
        t = g.space.w + (t - g.space.w) * g.space.z;
        e = t * g.space.y + g.space.x;

        float luma = dot(e, g.luminance.xyz);
        e += g.color.x * (1 - smoothstep(g.tone.x, g.tone.y, luma)) + g.color.y * smoothstep(g.tone.z, g.tone.w, luma);

        float mean = dot(e, g.luminance.xyz);
        float spread = spread_of(e);
        e = mean + (e - mean) * (g.color.z * (1 + g.color.w / (1 + spread * spread)));
        if (g.density.x > 0) {
            spread = spread_of(e);
            e += (e - max3(e.r, e.g, e.b)) * g.density.x - g.density.y * spread;
        }
        return e;
    }

    // MARK: Film

    struct FilmUniforms {
        float4 luminance;
        float4 shaper;        // x: min stops, y: range in stops, z: mid grey, w: LUT size
        float4 bloom;         // x: amount
        float4 halation;      // x: amount, yzw: tint
        float4 grain;         // x: amount in stops, y: chroma, z: mip level, w: normalization
        float4 beforeRows[3]; // undoes exposure / white balance for the "before" view
        float4 compare;       // x: pixels left of this fraction of the width render "before"
    };

    static float3 toStops(float3 e, constant FilmUniforms &u) {
        float floorValue = u.shaper.z * exp2(u.shaper.x);
        return log2(max(e, floorValue) / u.shaper.z);
    }

    static float3 sampleLUT(texture3d<float, access::sample> lut, float3 stops, constant FilmUniforms &u) {
        float3 s = saturate((stops - u.shaper.x) / u.shaper.y);
        float n = u.shaper.w;
        return lut.sample(linearClamp, s * ((n - 1) / n) + 0.5f / n).rgb;
    }

    kernel void film_render(texture2d<float, access::read> working [[texture(0)]],
                            texture2d<float, access::read> original [[texture(1)]],
                            texture2d<float, access::sample> bloom [[texture(2)]],
                            texture2d<float, access::sample> halation [[texture(3)]],
                            texture2d<float, access::sample> grain [[texture(4)]],
                            texture3d<float, access::sample> lookLUT [[texture(5)]],
                            texture3d<float, access::sample> beforeLUT [[texture(6)]],
                            texture2d<float, access::write> out [[texture(7)]],
                            constant FilmUniforms &u [[buffer(0)]],
                            constant GradeUniforms &grade [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(out.get_width(), out.get_height());

        if (uv.x < u.compare.x) {
            float3 e = original.read(gid).rgb;
            e = float3(dot(u.beforeRows[0].xyz, e), dot(u.beforeRows[1].xyz, e), dot(u.beforeRows[2].xyz, e));
            out.write(float4(sampleLUT(beforeLUT, toStops(e, u), u), 1), gid);
            return;
        }

        // Light scatter happens in the emulsion, so it is added as exposure before the film curve.
        float3 e = working.read(gid).rgb;
        e += u.bloom.x * bloom.sample(linearClamp, uv).rgb;
        e += u.halation.x * halation.sample(linearClamp, uv).a * u.halation.yzw;

        // Grain lives in the negative's density: it perturbs log exposure, so the print curve shapes it
        // and it naturally fades into pure black and paper white.
        float3 stops = toStops(e, u);
        if (u.grain.x > 0) {
            float4 g = grain.sample(mipClamp, uv, level(u.grain.z)) * u.grain.w;
            float3 noise = mix(float3(g.a), g.rgb, u.grain.y);
            float tone = dot(stops, u.luminance.xyz) - 0.5f;
            float weight = 0.55f + 0.45f * exp(-tone * tone / 12.5f);
            stops += u.grain.x * weight * noise;
        }
        out.write(float4(sampleLUT(lookLUT, apply_grade(stops, grade), u), 1), gid);
    }

    // MARK: Reference wipe

    struct WipeUniforms {
        float4 split;   // x: pixels left of this fraction of the width show the reference
        float4 rect;    // the reference, fitted inside the frame: origin and size as fractions of it
    };

    /// Another clip's graded frame on the left of the split (letterboxed), this clip on the right.
    kernel void reference_wipe(texture2d<float, access::read> current [[texture(0)]],
                               texture2d<float, access::sample> reference [[texture(1)]],
                               texture2d<float, access::write> out [[texture(2)]],
                               constant WipeUniforms &u [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(out.get_width(), out.get_height());
        if (uv.x >= u.split.x) {
            out.write(current.read(gid), gid);
            return;
        }
        float2 r = (uv - u.rect.xy) / u.rect.zw;
        bool inside = all(r >= 0.0f) && all(r <= 1.0f);
        out.write(inside ? float4(reference.sample(linearClamp, r).rgb, 1) : float4(0, 0, 0, 1), gid);
    }

    // MARK: Utilities

    kernel void copy_texture(texture2d<float, access::read> src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
        dst.write(src.read(gid), gid);
    }

    struct PresentVertex {
        float4 position [[position]];
        float2 uv;
    };

    vertex PresentVertex present_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        PresentVertex out;
        out.position = float4(p * 2.0f - 1.0f, 0, 1);
        out.uv = float2(p.x, 1.0f - p.y);
        return out;
    }

    fragment float4 present_fragment(PresentVertex in [[stage_in]],
                                     texture2d<float, access::sample> image [[texture(0)]]) {
        return image.sample(linearClamp, in.uv);
    }
    """#
}
