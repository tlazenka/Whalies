#include <metal_stdlib>
using namespace metal;

// Use simulation time so the effect pauses with the game.
kernel void stadiumWaterLens(texture2d<half, access::sample> source [[texture(0)]],
                             texture2d<half, access::write> target [[texture(1)]],
                             constant float4 &frame [[buffer(0)]],
                             uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= target.get_width() || pixel.y >= target.get_height()) { return; }
    const float2 size = float2(target.get_width(), target.get_height());
    const float2 uv = (float2(pixel) + 0.5f) / size;
    constexpr sampler lensSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float time = frame.x;
    const float strength = clamp(frame.y, 0.0f, 1.0f);
    const float2 aspect = float2(size.x / size.y, 1.0f);
    const float2 fromImpact = (uv - float2(0.5f, 0.46f)) * aspect;
    const float distance = length(fromImpact);
    const float wave = sin(distance * 45.0f - time * 16.0f)
                     * exp(-distance * 3.5f - time * 1.6f);
    float2 displacement = fromImpact / max(distance, 0.001f) / aspect
                        * wave * 0.012f * strength;
    float highlight = 0.0f;
    float wet = 0.0f;

    for (uint i = 0; i < 12; ++i) {
        const float n = float(i);
        const float spread = fract(n * 0.61803399f + 0.17f);
        const float2 centre = float2(0.06f + spread * 0.88f,
            0.02f + fract(n * 0.38196601f + 0.23f) * 0.85f
            + time * (0.025f + 0.018f * spread));
        const float2 radius = float2((0.035f + spread * 0.018f) / aspect.x,
                                    0.055f + spread * 0.035f);
        const float2 delta = (uv - centre) / radius;
        const float r = length(delta);
        const float drop = 1.0f - smoothstep(0.55f, 1.0f, r);
        displacement += delta * radius * drop * 0.24f * strength;
        const float rim = (1.0f - smoothstep(0.08f, 0.2f, abs(r - 0.78f)))
                        * (1.0f - smoothstep(0.85f, 1.05f, r));
        highlight += rim * max(0.0f, -delta.x - delta.y) * 0.035f;
        wet = max(wet, drop);
    }

    const half4 scene = source.sample(lensSampler, uv + displacement);
    const float3 blue = float3(0.10f, 0.58f, 0.95f);
    float3 color = mix(float3(scene.rgb), blue, wet * strength * 0.045f);
    color += float3(highlight * strength);
    if (frame.z > 0.5f) {
        // An sRGB sample is linear; explicitly re-encode when writing through an unorm view.
        color = max(color, float3(0.0f));
        const float3 low = color * 12.92f;
        const float3 high = 1.055f * pow(color, float3(1.0f / 2.4f)) - 0.055f;
        color = select(high, low, color <= float3(0.0031308f));
    }
    target.write(half4(half3(color), scene.a), pixel);
}
