// MARK: - Core/Retouch.metal
// Обычный compute-шейдер. Никаких специальных флагов сборки не нужно:
// просто добавить файл в таргет (попадёт в default.metallib).

#include <metal_stdlib>
using namespace metal;

// ВАЖНО: раскладка должна совпадать со Swift-структурой WarpOp (40 байт).
struct WarpOp {
    float2 center;     // центр, пиксели, origin сверху-слева
    float2 axis;       // единичный вектор «вдоль» (для kind 1/2 — вдоль конечности/лица)
    float2 radii;      // x — радиус вдоль axis, y — поперёк
    float2 vec;        // сдвиг (kind 3), пиксели
    float strength;
    int kind;          // 0 радиальная «выпуклость», 1 сужение поперёк, 2 растяжение вдоль, 3 сдвиг
};

constexpr sampler lin(coord::normalized, address::clamp_to_edge, filter::linear);

kernel void retouchWarp(texture2d<float, access::sample> src [[texture(0)]],
                        texture2d<float, access::write> dst [[texture(1)]],
                        constant WarpOp *ops [[buffer(0)]],
                        constant uint &count [[buffer(1)]],
                        uint2 gid [[thread_position_in_grid]])
{
    uint W = dst.get_width();
    uint H = dst.get_height();
    if (gid.x >= W || gid.y >= H) return;

    // Обратное отображение: из точки результата идём в точку исходника.
    float2 p = float2(gid) + 0.5;

    for (uint i = 0; i < count; i++) {
        WarpOp op = ops[i];
        float2 d = p - op.center;
        float2 ax = op.axis;
        float2 pr = float2(-ax.y, ax.x);
        float a = dot(d, ax);
        float b = dot(d, pr);
        float n = length(float2(a / op.radii.x, b / op.radii.y));
        if (n >= 1.0) continue;

        if (op.kind == 0) {
            float w = 1.0 - smoothstep(0.0, 1.0, n);
            p = op.center + d * (1.0 - op.strength * w * w);
        } else if (op.kind == 1) {
            float w = 1.0 - smoothstep(0.65, 1.0, n);
            b *= (1.0 + op.strength * w);
            p = op.center + ax * a + pr * b;
        } else if (op.kind == 2) {
            float w = 1.0 - smoothstep(0.65, 1.0, n);
            a *= (1.0 - op.strength * w);
            p = op.center + ax * a + pr * b;
        } else {
            float w = 1.0 - smoothstep(0.0, 1.0, n);
            p = p - op.vec * w;
        }
    }

    float2 uv = p / float2(W, H);
    dst.write(src.sample(lin, uv), gid);
}
