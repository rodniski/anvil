#include <metal_stdlib>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * valueNoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return v;
}

// Blueprint vivo: malha técnica que refrata com o calor perto do centro,
// onde a bigorna assenta. ShapeStyle (.fill) → assinatura (position, args...).
// `heat` (0–1) intensifica a distorção e o brilho molten.
[[ stitchable ]] half4 blueprint(float2 pos, float time, float2 size, float heat) {
    float2 uv = pos / size;

    // Calor concentrado no centro, respirando.
    float2 c = uv - float2(0.5, 0.5);
    float pulse = 0.55 + 0.45 * sin(time * 0.8);
    float hot = exp(-3.5 * dot(c, c)) * pulse * (0.35 + 0.65 * heat);

    // Refração: o ar quente distorce as linhas da malha.
    float2 duv = uv + float2(fbm(uv * 9.0 + time * 0.35),
                             fbm(uv * 9.0 - time * 0.35)) * 0.02 * hot;

    // Malha ~26 células na largura.
    float2 cell = float2(size.x / 26.0, size.y / 26.0);
    float2 g = abs(fract(duv * cell) - 0.5);
    float line = smoothstep(0.0, 0.045, min(g.x, g.y));

    half3 bg   = half3(0.035, 0.045, 0.062);
    half3 grid = half3(0.5, 0.7, 0.83) * 0.22;
    half3 col  = mix(grid, bg, half(line));

    // Brilho molten irradiando do centro.
    col += half3(1.0, 0.45, 0.15) * half(hot) * 0.28;

    return half4(col, 1.0);
}
