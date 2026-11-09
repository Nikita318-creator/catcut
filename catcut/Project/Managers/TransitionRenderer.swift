// MARK: - Managers/TransitionRenderer.swift

import UIKit
import CoreImage

// =====================================================================
// MARK: - Transition renderer (Mega Unified Metal GPU Engine)
// =====================================================================

enum TransitionRenderer {

    // MARK: - Metal GPU Warp Kernels

    private static var sineRippleKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 sineRipple(destination coordinates, float t, float freq, float amp, vec2 center) {
            vec2 p = destCoord() - center;
            float d = length(p);
            float angle = atan2(p.y, p.x);
            float dr = d + sin(d * freq - t * 12.566) * amp;
            return center + vec2(dr * cos(angle), dr * sin(angle));
        }
        """)
    }()

    private static var hyperbolicKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 hyperbolicSaddle(destination coordinates, float t, float strength, vec2 center) {
            vec2 p = (destCoord() - center) / 400.0;
            float k = sin(t * 3.14159) * strength;
            vec2 warped = p + vec2(p.x * p.y * k, -p.x * p.y * k);
            return center + warped * 400.0;
        }
        """)
    }()

    private static var liquidWarpKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 liquidWarp(destination coordinates, float t, float freq, float amp, vec2 center) {
            vec2 p = destCoord() - center;
            float d = length(p);
            float angle = atan2(p.y, p.x);
            float dr = d + sin(d * freq - t * 12.566) * amp;
            return center + vec2(dr * cos(angle), dr * sin(angle));
        }
        """)
    }()

    private static var perspectiveMorphKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 perspectiveMorph(destination coordinates, float t, float angle, vec2 center) {
            vec2 p = (destCoord() - center) / 400.0;
            float k = sin(t * 3.14159) * angle;
            vec2 warped = p + vec2(p.x * p.y * k, -p.x * p.y * k);
            return center + warped * 400.0;
        }
        """)
    }()

    private static var glassRefractionKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 glassRefraction(destination coordinates, float t, float strength, vec2 center) {
            vec2 p = destCoord() - center;
            float r = length(p);
            float factor = 1.0 + sin(t * 3.14159) * (strength / (r + 1.0));
            return center + p * factor;
        }
        """)
    }()

    private static var fisheyeKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 fisheyeLens(destination coordinates, float t, float strength, vec2 center) {
            vec2 p = destCoord() - center;
            float r = length(p);
            if (r < 0.001) return destCoord();
            float factor = 1.0 + sin(t * 3.14159) * strength * (r / 500.0);
            return center + p * factor;
        }
        """)
    }()

    private static var warpSlideKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 warpSlide(destination coordinates, float t, vec2 dir, float elasticity, vec2 center) {
            vec2 p = destCoord() - center;
            float wave = sin(p.y * 0.02 + t * 6.283) * elasticity * 30.0 * sin(t * 3.14159);
            return destCoord() + dir * wave;
        }
        """)
    }()

    private static var blockGlitchKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 blockGlitch(destination coordinates, float t, float blockSize, vec2 center) {
            vec2 p = destCoord();
            float blockY = floor(p.y / blockSize);
            float noise = sin(blockY * 12.9898 + t * 78.233) * 43758.5453;
            float shift = (fract(noise) - 0.5) * 80.0 * sin(t * 3.14159);
            return vec2(p.x + shift, p.y);
        }
        """)
    }()

    private static var heatWaveKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 heatWave(destination coordinates, float t, float distortion, vec2 center) {
            vec2 p = destCoord();
            float dx = sin(p.y * 0.05 + t * 15.0) * distortion * sin(t * 3.14159);
            float dy = cos(p.x * 0.05 + t * 12.0) * (distortion * 0.5) * sin(t * 3.14159);
            return vec2(p.x + dx, p.y + dy);
        }
        """)
    }()

    private static var liquidRippleKernel: CIWarpKernel? = {
        CIWarpKernel(source: """
        kernel vec2 liquidRipple(destination coordinates, float t, float freq, float amp, vec2 center) {
            vec2 p = destCoord() - center;
            float d = length(p);
            float angle = atan2(p.y, p.x);
            float dr = d + sin(d * freq - t * 12.566) * amp;
            return center + vec2(dr * cos(angle), dr * sin(angle));
        }
        """)
    }()
    

    // =====================================================================
    // MARK: - RiCH GPU kernels (Core Image Kernel Language)
    // Один CIKernel на переход: многотаповый motion/radial blur, поля смещения (fbm + domain warp),
    // диаграммы Вороного, покадровая хроматическая аберрация, mirror-repeat сэмплинг.
    // Если ядро не скомпилировалось — переход мягко падает в обычный кроссфейд (см. Xcode console).
    // =====================================================================

    private static let richLock = NSLock()
    private static var richKernels: [RichKind: CIKernel] = [:]
    private static var richFailed: Set<RichKind> = []

    private static func richKernel(_ kind: RichKind) -> CIKernel? {
        richLock.lock()
        defer { richLock.unlock() }
        if let k = richKernels[kind] { return k }
        if richFailed.contains(kind) { return nil }
        if let k = CIKernel(source: richPrelude + richBody(kind)) {
            richKernels[kind] = k
            return k
        }
        richFailed.insert(kind)
        #if DEBUG
        print("[RiCH] kernel '\(kind)' failed to compile - fallback to crossfade")
        #endif
        return nil
    }

    private static func renderRich(_ kind: RichKind, from: CIImage, to: CIImage, e: CGFloat,
                                   a: CGFloat, b: CGFloat, rect: CGRect) -> CIImage? {
        guard let k = richKernel(kind) else { return nil }
        var src = from, dst = to, p = e, p1 = a, p2 = b
        if kind == .chromaBarrel {
            // a >= 0.5: наезд (push), иначе отъезд (pull) = тот же ход со сменой кадров и обратным временем
            if a < 0.5 { src = to; dst = from; p = 1 - e }
            p1 = 0
            p2 = b
        }
        let args: [Any] = [
            src.clampedToExtent(), dst.clampedToExtent(),
            NSNumber(value: Double(p)),
            CIVector(x: rect.width, y: rect.height),
            CIVector(x: rect.minX, y: rect.minY),
            NSNumber(value: Double(p1)), NSNumber(value: Double(p2))
        ]
        return k.apply(extent: rect, roiCallback: { _, _ in rect }, arguments: args)
    }

    private static func richBody(_ kind: RichKind) -> String {
        switch kind {
        case .flowMorph: return richSrc_flowMorph
        case .chromaBarrel: return richSrc_chromaBarrel
        case .whipPro: return richSrc_whipPro
        case .orbitSpin: return richSrc_orbitSpin
        case .shardRefract: return richSrc_shardRefract
        case .shockwave: return richSrc_shockwave
        case .smokeDissolve: return richSrc_smokeDissolve
        case .tileCascade: return richSrc_tileCascade
        case .lenticular: return richSrc_lenticular
        case .vortexPull: return richSrc_vortexPull
        case .anamorphicFlare: return richSrc_anamorphicFlare
        case .depthParallax: return richSrc_depthParallax
        case .lightLeak: return richSrc_lightLeak
        case .aquaRefract: return richSrc_aquaRefract
        case .radialSweep: return richSrc_radialSweep
        case .bokehRack: return richSrc_bokehRack
        }
    }

    private static let richPrelude = """
float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, vec3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, vec3(p3.y, p3.z, p3.x) + 33.33);
    return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
    vec2 pp = p;
    float v = 0.0;
    float a = 0.5;
    for (float i = 0.0; i < 4.0; i += 1.0) {
        v = v + a * vnoise(pp);
        pp = pp * 2.03 + vec2(17.1, 9.2);
        a = a * 0.5;
    }
    return v;
}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float sstep(float a, float b, float x) {
    float t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
vec2 rot(vec2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}
vec2 mir(vec2 q) { return abs(mod(q + 1.0, 2.0) - 1.0); }
vec3 chanMask(float ch) {
    return vec3(1.0 - step(0.5, ch), step(0.5, ch) * (1.0 - step(1.5, ch)), step(1.5, ch));
}
"""

    private static let richSrc_flowMorph = """
kernel vec4 flowMorph(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float s = sin(e * 3.14159265);
    vec2 q = vec2(uv.x * asp, uv.y) * p1;
    vec2 w = vec2(fbm(q + vec2(0.0, e * 1.3)), fbm(q + vec2(5.2, 1.7 - e * 1.3)));
    vec2 flow = (w - 0.5) * 2.0;
    vec2 uA = uv + flow * p2 * e;
    vec2 uB = uv - flow * p2 * (1.0 - e);
    vec2 ch = flow * 0.006 * s;
    vec3 cA = vec3(sample(A, samplerTransform(A, org + mir(uA + ch) * size)).r, sample(A, samplerTransform(A, org + mir(uA) * size)).g, sample(A, samplerTransform(A, org + mir(uA - ch) * size)).b);
    vec3 cB = vec3(sample(B, samplerTransform(B, org + mir(uB + ch) * size)).r, sample(B, samplerTransform(B, org + mir(uB) * size)).g, sample(B, samplerTransform(B, org + mir(uB - ch) * size)).b);
    float n = fbm(q * 0.7 + 11.0);
    float x = mix(-0.3, 1.3, e);
    float m = sstep(n - 0.2, n + 0.2, x);
    return vec4(mix(cA, cB, m), 1.0);
}
"""

    private static let richSrc_chromaBarrel = """
kernel vec4 chromaBarrel(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float s = sin(e * 3.14159265);
    vec2 p = (uv - 0.5) * vec2(asp, 1.0);
    float zA = 1.0 + 0.9 * e * e;
    float zB = 1.0 + 0.5 * (1.0 - e) * (1.0 - e);
    vec3 cA = vec3(0.0);
    vec3 cB = vec3(0.0);
    for (float i = 0.0; i < 8.0; i += 1.0) {
        float f = i / 7.0 - 0.5;
        float k = 1.0 + f * s * 0.12;
        for (float ch = 0.0; ch < 3.0; ch += 1.0) {
            float cs = 1.0 + (ch - 1.0) * 0.12 * s;
            vec2 pa = p * k;
            float r2 = dot(pa, pa);
            vec2 pd = pa * (1.0 + p2 * s * r2 * cs);
            vec2 ua = (pd / zA) / vec2(asp, 1.0) + 0.5;
            vec2 ub = (pd / zB) / vec2(asp, 1.0) + 0.5;
            vec3 msk = chanMask(ch);
            cA = cA + sample(A, samplerTransform(A, org + mir(ua) * size)).rgb * msk;
            cB = cB + sample(B, samplerTransform(B, org + mir(ub) * size)).rgb * msk;
        }
    }
    cA = cA / 8.0;
    cB = cB / 8.0;
    float m = sstep(0.3, 0.7, e);
    return vec4(mix(cA, cB, m), 1.0);
}
"""

    private static let richSrc_whipPro = """
kernel vec4 whipPro(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    vec2 v = vec2(p1, p2);
    float s = sin(e * 3.14159265);
    float blurLen = s * 0.22;
    vec3 acc = vec3(0.0);
    for (float i = 0.0; i < 10.0; i += 1.0) {
        float f = i / 9.0 - 0.5;
        for (float ch = 0.0; ch < 3.0; ch += 1.0) {
            vec2 qq = uv + v * (f * blurLen + (ch - 1.0) * 0.012 * s);
            float ua = ((v.x + v.y) > 0.0) ? dot(qq, v) : (1.0 + dot(qq, v));
            vec4 c = vec4(0.0);
            if (ua >= e) {
                c = sample(A, samplerTransform(A, org + mir(qq - v * e) * size));
            } else {
                c = sample(B, samplerTransform(B, org + mir(qq + v * (1.0 - e)) * size));
            }
            acc = acc + c.rgb * chanMask(ch);
        }
    }
    acc = acc / 10.0;
    acc = acc * (1.0 + 0.12 * s);
    return vec4(acc, 1.0);
}
"""

    private static let richSrc_orbitSpin = """
kernel vec4 orbitSpin(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float s = sin(e * 3.14159265);
    vec2 p = (uv - 0.5) * vec2(asp, 1.0);
    float thA = p2 * p1 * e * e;
    float thB = -p2 * p1 * (1.0 - e) * (1.0 - e);
    float zA = 1.0 + 0.3 * e;
    float zB = 1.0 + 0.3 * (1.0 - e);
    float spread = 0.5 * s;
    vec3 cA = vec3(0.0);
    vec3 cB = vec3(0.0);
    for (float i = 0.0; i < 12.0; i += 1.0) {
        float f = i / 11.0 - 0.5;
        vec2 pa = rot(p, -(thA + f * spread)) / zA;
        vec2 pb = rot(p, -(thB + f * spread)) / zB;
        cA = cA + sample(A, samplerTransform(A, org + mir(pa / vec2(asp, 1.0) + 0.5) * size)).rgb;
        cB = cB + sample(B, samplerTransform(B, org + mir(pb / vec2(asp, 1.0) + 0.5) * size)).rgb;
    }
    cA = cA / 12.0;
    cB = cB / 12.0;
    float m = sstep(0.35, 0.65, e);
    return vec4(mix(cA, cB, m), 1.0);
}
"""

    private static let richSrc_shardRefract = """
kernel vec4 shardRefract(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    vec2 p = vec2(uv.x * asp, uv.y) * p1;
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    float md = 8.0;
    float md2 = 8.0;
    vec2 cid = vec2(0.0);
    for (float j = -1.0; j <= 1.0; j += 1.0) {
        for (float i = -1.0; i <= 1.0; i += 1.0) {
            vec2 g = vec2(i, j);
            vec2 o = hash22(ip + g + p2);
            vec2 r = g + o - fp;
            float dd = dot(r, r);
            if (dd < md) {
                md2 = md;
                md = dd;
                cid = ip + g;
            } else if (dd < md2) {
                md2 = dd;
            }
        }
    }
    float edge = 1.0 - smoothstep(0.0, 0.09, sqrt(md2) - sqrt(md));
    float h = hash21(cid + p2 * 1.7);
    float lp = sstep(h * 0.45, h * 0.45 + 0.55, e);
    float s = sin(lp * 3.14159265);
    vec2 dv = (hash22(cid + 3.1) - 0.5) * 2.0;
    vec2 off = dv * 0.09 * s;
    vec2 ch = off * 0.15;
    vec3 cA = vec3(sample(A, samplerTransform(A, org + mir(uv + off + ch) * size)).r, sample(A, samplerTransform(A, org + mir(uv + off) * size)).g, sample(A, samplerTransform(A, org + mir(uv + off - ch) * size)).b);
    vec3 cB = vec3(sample(B, samplerTransform(B, org + mir(uv - off + ch) * size)).r, sample(B, samplerTransform(B, org + mir(uv - off) * size)).g, sample(B, samplerTransform(B, org + mir(uv - off - ch) * size)).b);
    float m = sstep(0.4, 0.6, lp);
    vec3 col = mix(cA, cB, m);
    col = col * (1.0 + (h - 0.5) * 0.35 * s) + vec3(edge * s * 0.28);
    return vec4(col, 1.0);
}
"""

    private static let richSrc_shockwave = """
kernel vec4 shockwave(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    vec2 p = (uv - 0.5) * vec2(asp, 1.0);
    float r = length(p);
    float maxR = length(vec2(asp, 1.0)) * 0.5 + p1 * 2.5;
    float R = mix(-2.5 * p1, maxR, e);
    float d = r - R;
    float ring = exp(-(d * d) / (p1 * p1));
    vec2 dv = p / max(r, 0.0001);
    float tail = sin(d * 55.0) * exp(-abs(d) * 9.0) * (1.0 - step(0.0, d)) * (1.0 - e);
    vec2 off = dv * (ring * p2 * (d / p1) + tail * p2 * 0.35);
    vec2 o = off / vec2(asp, 1.0);
    vec3 cA = vec3(sample(A, samplerTransform(A, org + mir(uv - o * 1.3) * size)).r, sample(A, samplerTransform(A, org + mir(uv - o) * size)).g, sample(A, samplerTransform(A, org + mir(uv - o * 0.7) * size)).b);
    vec3 cB = vec3(sample(B, samplerTransform(B, org + mir(uv - o * 1.3) * size)).r, sample(B, samplerTransform(B, org + mir(uv - o) * size)).g, sample(B, samplerTransform(B, org + mir(uv - o * 0.7) * size)).b);
    float m = 1.0 - smoothstep(-p1 * 0.5, p1 * 0.5, d);
    vec3 col = mix(cA, cB, m) + vec3(ring * 0.14);
    return vec4(col, 1.0);
}
"""

    private static let richSrc_smokeDissolve = """
kernel vec4 smokeDissolve(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    vec2 q = vec2(uv.x * asp, uv.y) * p1;
    vec2 w = vec2(fbm(q + vec2(1.7, 9.2) + e * 0.6), fbm(q + vec2(8.3, 2.8) - e * 0.6));
    float n = fbm(q + 2.2 * w);
    float x = mix(-0.2, 1.2, e);
    float m = sstep(n - 0.12, n + 0.12, x);
    float dx = (x - n) / 0.07;
    float band = exp(-dx * dx);
    vec2 disp = (w - 0.5) * 0.04 * band;
    vec3 cA = sample(A, samplerTransform(A, org + mir(uv + disp) * size)).rgb;
    vec3 cB = sample(B, samplerTransform(B, org + mir(uv - disp) * size)).rgb;
    vec3 col = mix(cA, cB, m) + vec3(1.0, 0.86, 0.62) * band * p2 * 0.6;
    return vec4(col, 1.0);
}
"""

    private static let richSrc_tileCascade = """
kernel vec4 tileCascade(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float ny = max(1.0, floor(p1 / asp + 0.5));
    vec2 cells = vec2(p1, ny);
    vec2 cuv = uv * cells;
    vec2 id = floor(cuv);
    vec2 lc = fract(cuv);
    float delay = (id.x / p1) * 0.65 + (id.y / ny) * 0.35;
    float lp = sstep(delay * 0.5, delay * 0.5 + 0.5, e);
    float phi = lp * 3.14159265;
    float ax = max(abs(cos(phi)), 0.0001);
    float xl = (lc.x - 0.5) / ax + 0.5;
    float inside = step(0.0, xl) * (1.0 - step(1.0, xl));
    vec2 tuv = (id + vec2(clamp(xl, 0.0, 1.0), lc.y)) / cells;
    vec4 cs = vec4(0.0);
    if (lp < 0.5) {
        cs = sample(A, samplerTransform(A, org + mir(tuv) * size));
    } else {
        cs = sample(B, samplerTransform(B, org + mir(tuv) * size));
    }
    float s = sin(phi);
    vec3 col = cs.rgb * (1.0 - 0.32 * s);
    float gap = min(min(lc.x, 1.0 - lc.x), min(lc.y, 1.0 - lc.y));
    float ln = smoothstep(0.0, 0.035, gap);
    col = mix(vec3(0.02), col, mix(1.0, ln, s));
    col = mix(vec3(0.02), col, inside);
    return vec4(col, 1.0);
}
"""

    private static let richSrc_lenticular = """
kernel vec4 lenticular(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float cell = uv.x * p1;
    float id = floor(cell);
    float lx = (fract(cell) - 0.5) * 2.0;
    float delay = id / p1;
    float lp = sstep(delay * 0.55, delay * 0.55 + 0.45, e);
    float s = sin(lp * 3.14159265);
    float off = lx * p2 * s;
    float zy = 1.0 - 0.05 * s * (1.0 - lx * lx);
    float yy = (uv.y - 0.5) * zy + 0.5;
    vec2 uA = vec2(uv.x + off, yy);
    vec2 uB = vec2(uv.x - off, yy);
    vec2 ch = vec2(off * 0.35, 0.0);
    vec3 cA = vec3(sample(A, samplerTransform(A, org + mir(uA + ch) * size)).r, sample(A, samplerTransform(A, org + mir(uA) * size)).g, sample(A, samplerTransform(A, org + mir(uA - ch) * size)).b);
    vec3 cB = vec3(sample(B, samplerTransform(B, org + mir(uB + ch) * size)).r, sample(B, samplerTransform(B, org + mir(uB) * size)).g, sample(B, samplerTransform(B, org + mir(uB - ch) * size)).b);
    float m = sstep(0.35, 0.65, lp);
    float lx2 = lx * lx;
    vec3 col = mix(cA, cB, m);
    col = col * (1.0 - 0.28 * s * lx2 * lx2) + vec3(0.10 * s * (1.0 - abs(lx)));
    return vec4(col, 1.0);
}
"""

    private static let richSrc_vortexPull = """
kernel vec4 vortexPull(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    vec2 p = (uv - 0.5) * vec2(asp, 1.0);
    float r = length(p);
    float fall = exp(-r * 2.4);
    float s = sin(e * 3.14159265);
    float zA = 1.0 + p2 * e * e;
    float zB = 1.0 + p2 * 0.6 * (1.0 - e) * (1.0 - e);
    vec3 cA = vec3(0.0);
    vec3 cB = vec3(0.0);
    for (float i = 0.0; i < 8.0; i += 1.0) {
        float f = i / 7.0 - 0.5;
        for (float ch = 0.0; ch < 3.0; ch += 1.0) {
            float cs = 1.0 + (ch - 1.0) * 0.08 * s;
            float aA = (e * p1 * fall + f * 0.10 * s) * cs;
            float aB = (-(1.0 - e) * p1 * fall + f * 0.10 * s) * cs;
            vec2 pa = rot(p, -aA) / zA;
            vec2 pb = rot(p, -aB) / zB;
            vec3 msk = chanMask(ch);
            cA = cA + sample(A, samplerTransform(A, org + mir(pa / vec2(asp, 1.0) + 0.5) * size)).rgb * msk;
            cB = cB + sample(B, samplerTransform(B, org + mir(pb / vec2(asp, 1.0) + 0.5) * size)).rgb * msk;
        }
    }
    cA = cA / 8.0;
    cB = cB / 8.0;
    float m = sstep(0.3, 0.7, e);
    return vec4(mix(cA, cB, m), 1.0);
}
"""

    private static let richSrc_anamorphicFlare = """
kernel vec4 anamorphicFlare(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float s = sin(e * 3.14159265);
    float m = sstep(0.35, 0.65, e);
    vec3 base = mix(sample(A, samplerTransform(A, org + mir(uv) * size)).rgb, sample(B, samplerTransform(B, org + mir(uv) * size)).rgb, m);
    vec3 streak = vec3(0.0);
    float wsum = 0.0;
    for (float i = 0.0; i < 14.0; i += 1.0) {
        float f = i / 13.0 * 2.0 - 1.0;
        vec2 qq = vec2(uv.x + f * p1, uv.y);
        vec3 c = mix(sample(A, samplerTransform(A, org + mir(qq) * size)).rgb, sample(B, samplerTransform(B, org + mir(qq) * size)).rgb, m);
        float hl = max(luma(c) - 0.35, 0.0);
        float w = exp(-abs(f) * 2.5);
        streak = streak + c * hl * w;
        wsum = wsum + w;
    }
    streak = streak / wsum;
    vec3 tint = vec3(1.0, 0.93, 0.80);
    vec3 col = base * (1.0 + 0.35 * s) + streak * tint * p2 * 2.2 * s;
    return vec4(col, 1.0);
}
"""

    private static let richSrc_depthParallax = """
kernel vec4 depthParallax(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    vec2 dv = vec2(p2, 0.0);
    float zA = 1.0 + 0.22 * e;
    float zB = 1.0 + 0.12 * (1.0 - e);
    float dA = sqrt(clamp(luma(sample(A, samplerTransform(A, org + mir(uv) * size)).rgb), 0.0, 1.0));
    float dB = sqrt(clamp(luma(sample(B, samplerTransform(B, org + mir(uv) * size)).rgb), 0.0, 1.0));
    vec2 uA = (uv - 0.5) / zA + 0.5 + dv * (dA - 0.5) * p1 * e * 2.0;
    vec2 uB = (uv - 0.5) / zB + 0.5 - dv * (dB - 0.5) * p1 * (1.0 - e) * 2.0;
    vec3 cA = sample(A, samplerTransform(A, org + mir(uA) * size)).rgb;
    vec3 cB = sample(B, samplerTransform(B, org + mir(uB) * size)).rgb;
    float m = sstep(0.3, 0.7, e);
    return vec4(mix(cA, cB, m), 1.0);
}
"""

    private static let richSrc_lightLeak = """
kernel vec4 lightLeak(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float s = sin(e * 3.14159265);
    float m = sstep(0.4, 0.6, e);
    vec3 base = clamp(mix(sample(A, samplerTransform(A, org + mir(uv) * size)).rgb, sample(B, samplerTransform(B, org + mir(uv) * size)).rgb, m), 0.0, 1.0);
    vec2 q = vec2(uv.x * asp, uv.y) * p1;
    float n1 = fbm(q + vec2(-e * 2.2, 0.0));
    float n2 = fbm(q * 1.7 + vec2(4.0, -e * 1.5));
    float body = smoothstep(0.30, 0.85, n1) * (0.55 + 0.45 * (1.0 - uv.x));
    vec3 leakCol = mix(vec3(1.0, 0.50, 0.18), vec3(1.0, 0.80, 0.55), n2);
    vec3 leak = clamp(leakCol * body * s * p2 * 1.6, 0.0, 1.0);
    vec3 col = 1.0 - (1.0 - base) * (1.0 - leak);
    return vec4(col, 1.0);
}
"""

    private static let richSrc_aquaRefract = """
kernel vec4 aquaRefract(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float s = sin(e * 3.14159265);
    vec2 q = vec2(uv.x * asp, uv.y) * p1;
    vec2 nrm = vec2(fbm(q + vec2(e * 2.0, 0.0)), fbm(q + vec2(3.3, -e * 2.0))) - 0.5;
    vec2 off = nrm * p2 * 4.0 * s;
    vec2 ch = off * 0.3;
    vec3 cA = vec3(sample(A, samplerTransform(A, org + mir(uv + off + ch) * size)).r, sample(A, samplerTransform(A, org + mir(uv + off) * size)).g, sample(A, samplerTransform(A, org + mir(uv + off - ch) * size)).b);
    vec3 cB = vec3(sample(B, samplerTransform(B, org + mir(uv - off + ch) * size)).r, sample(B, samplerTransform(B, org + mir(uv - off) * size)).g, sample(B, samplerTransform(B, org + mir(uv - off - ch) * size)).b);
    float m = sstep(0.3, 0.7, e);
    float caus = smoothstep(0.55, 0.85, fbm(q * 1.6 + vec2(e * 3.0, 0.0))) * s * 0.22;
    vec3 col = mix(cA, cB, m) + vec3(0.90, 0.97, 1.0) * caus;
    return vec4(col, 1.0);
}
"""

    private static let richSrc_radialSweep = """
kernel vec4 radialSweep(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float s = sin(e * 3.14159265);
    vec2 p = (uv - 0.5) * vec2(asp, 1.0);
    float a = atan(p.y, p.x);
    float n = fract((p2 - a) / 6.28318531);
    float pos = e * (1.0 + p1);
    float m = 1.0 - smoothstep(pos - p1, pos, n);
    float dl = (n - (pos - p1 * 0.5)) / (p1 * 0.35);
    float glow = exp(-dl * dl) * s;
    vec2 uB = (uv - 0.5) / (1.0 + 0.06 * (1.0 - e)) + 0.5;
    vec3 cA = sample(A, samplerTransform(A, org + mir(uv) * size)).rgb;
    vec3 cB = sample(B, samplerTransform(B, org + mir(uB) * size)).rgb;
    vec3 col = mix(cA, cB, m) + vec3(1.0, 0.96, 0.88) * glow * 0.45;
    return vec4(col, 1.0);
}
"""

    private static let richSrc_bokehRack = """
kernel vec4 bokehRack(sampler A, sampler B, float e, vec2 size, vec2 org, float p1, float p2) {
    vec2 uv = (destCoord() - org) / size;
    float asp = size.x / size.y;
    float s = sin(e * 3.14159265);
    float rA = p1 * sstep(0.0, 0.65, e);
    float rB = p1 * (1.0 - sstep(0.35, 1.0, e));
    vec3 accA = vec3(0.0);
    vec3 accB = vec3(0.0);
    float wA = 0.0;
    float wB = 0.0;
    for (float i = 0.0; i < 20.0; i += 1.0) {
        float rr = sqrt((i + 0.5) / 20.0);
        float th = i * 2.39996323;
        vec2 o = vec2(cos(th), sin(th)) * rr * vec2(1.0 / asp, 1.0);
        vec3 ca = sample(A, samplerTransform(A, org + mir(uv + o * rA) * size)).rgb;
        vec3 cb = sample(B, samplerTransform(B, org + mir(uv + o * rB) * size)).rgb;
        float wa = 1.0 + p2 * pow(clamp(luma(ca), 0.0, 1.0), 3.0);
        float wb = 1.0 + p2 * pow(clamp(luma(cb), 0.0, 1.0), 3.0);
        accA = accA + ca * wa;
        wA = wA + wa;
        accB = accB + cb * wb;
        wB = wB + wb;
    }
    float m = sstep(0.35, 0.65, e);
    vec3 col = mix(accA / wA, accB / wB, m) * (1.0 + 0.1 * s);
    return vec4(col, 1.0);
}
"""

    // MARK: - Main Render Entry

    static func render(id: Int, from: CIImage, to: CIImage, t: CGFloat, rect: CGRect) -> CIImage {
        guard let spec = TransitionCatalog.spec(id) else { return t < 0.5 ? from : to }
        let e = spec.ease.apply(t)
        var out = renderBase(spec.base, from: from, to: to, e: e, rect: rect)
        out = applyFx(spec.fx, out, t: t, rect: rect)
        return out.composited(over: black(rect)).cropped(to: rect)
    }

    // MARK: - Helpers & Utilities

    private static func black(_ r: CGRect) -> CIImage { CIImage(color: CIColor.black).cropped(to: r) }
    private static func solid(_ c: CIColor, _ r: CGRect) -> CIImage { CIImage(color: c).cropped(to: r) }
    private static func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }

    private static func opacity(_ image: CIImage, _ a: CGFloat) -> CIImage {
        let a = clamp01(a)
        guard a < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: a),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    private static func crossfade(_ a: CIImage, _ b: CIImage, _ t: CGFloat) -> CIImage {
        opacity(b, t).composited(over: a)
    }

    private static func move(_ img: CIImage, _ x: CGFloat, _ y: CGFloat) -> CIImage {
        img.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private static func scaledXY(_ img: CIImage, _ sx: CGFloat, _ sy: CGFloat, _ r: CGRect) -> CIImage {
        let t = CGAffineTransform(translationX: -r.midX, y: -r.midY)
            .concatenating(CGAffineTransform(scaleX: max(0.001, sx), y: max(0.001, sy)))
            .concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
        return img.transformed(by: t)
    }

    private static func scaled(_ img: CIImage, _ s: CGFloat, _ r: CGRect) -> CIImage { scaledXY(img, s, s, r) }

    private static func rotated(_ img: CIImage, angle: CGFloat, scale: CGFloat, _ r: CGRect) -> CIImage {
        let t = CGAffineTransform(translationX: -r.midX, y: -r.midY)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
        return img.transformed(by: t)
    }

    private static func ciFilter(_ name: String, _ image: CIImage, _ params: [String: Any]) -> CIImage? {
        guard let f = CIFilter(name: name) else { return nil }
        f.setValue(image, forKey: kCIInputImageKey)
        for (k, v) in params where f.inputKeys.contains(k) { f.setValue(v, forKey: k) }
        return f.outputImage
    }

    private static func blurred(_ img: CIImage, sigma: CGFloat, _ r: CGRect) -> CIImage {
        guard sigma > 0.5 else { return img }
        return img.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: r)
    }

    private static func vec(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: p.y) }

    // MARK: - Premium helpers

    private static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp01((x - a) / max(0.0001, b - a))
        return t * t * (3 - 2 * t)
    }

    private static func cubicInOut(_ x: CGFloat) -> CGFloat {
        let v = clamp01(x)
        return v < 0.5 ? 4 * v * v * v : 1 - pow(-2 * v + 2, 3) / 2
    }

    private static func evAdjust(_ img: CIImage, ev: CGFloat) -> CIImage {
        guard abs(ev) > 0.001 else { return img }
        return img.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev])
    }

    /// Размытие в движении. Вызывать ДО сдвига изображения (иначе clampedToExtent растянет края).
    private static func motionBlurred(_ img: CIImage, radius: CGFloat, angle: CGFloat) -> CIImage {
        guard radius > 0.5 else { return img }
        let extent = img.extent
        return img.clampedToExtent()
            .applyingFilter("CIMotionBlur", parameters: ["inputRadius": radius, "inputAngle": angle])
            .cropped(to: extent)
    }

    /// Минимальный масштаб, при котором повёрнутый кадр полностью закрывает rect (без чёрных углов).
    private static func coverScale(angle: CGFloat, _ r: CGRect) -> CGFloat {
        let a = abs(angle)
        let ratio = max(r.width / max(1, r.height), r.height / max(1, r.width))
        return cos(a) + ratio * sin(a)
    }

    private static func scaleMask(_ m: CIImage, _ k: CGFloat) -> CIImage {
        m.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    /// Полоса между двумя масками (a - b).
    private static func maskBand(_ a: CIImage, minus b: CIImage, _ r: CGRect) -> CIImage {
        a.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b]).cropped(to: r)
    }

    private static func chromaSplit(_ img: CIImage, shift d: CGFloat, _ rect: CGRect) -> CIImage {
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
            img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]).clampedToExtent()
        }
        let red = move(channel(1, 0, 0), d, 0)
        let green = channel(0, 1, 0)
        let blue = move(channel(0, 0, 1), -d, 0)
        let rg = green.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: red])
        return blue.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rg]).cropped(to: rect)
    }

    // MARK: - Masks & Fields

    private static func threshold(_ g: CIImage, e: CGFloat, soft: CGFloat, _ r: CGRect) -> CIImage {
        let s = max(0.001, soft)
        let a = -1 / s
        let bias = e * (1 + s) / s
        return g
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: r)
    }

    private static func revealWithMask(_ to: CIImage, over from: CIImage, mask: CIImage, _ r: CGRect) -> CIImage {
        to.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: from,
            kCIInputMaskImageKey: mask
        ]).cropped(to: r)
    }

    private static func linearField(angle: CGFloat, _ r: CGRect) -> CIImage? {
        guard let f = CIFilter(name: "CILinearGradient") else { return nil }
        let dx = cos(angle), dy = sin(angle)
        let len = abs(r.width * dx) + abs(r.height * dy)
        f.setValue(CIVector(x: r.midX - dx * len / 2, y: r.midY - dy * len / 2), forKey: "inputPoint0")
        f.setValue(CIVector(x: r.midX + dx * len / 2, y: r.midY + dy * len / 2), forKey: "inputPoint1")
        f.setValue(CIColor.black, forKey: "inputColor0")
        f.setValue(CIColor.white, forKey: "inputColor1")
        return f.outputImage?.cropped(to: r)
    }

    private static func radialField(center: CGPoint, radius: CGFloat, invert: Bool, _ r: CGRect) -> CIImage? {
        guard let f = CIFilter(name: "CIRadialGradient") else { return nil }
        f.setValue(vec(center), forKey: "inputCenter")
        f.setValue(0, forKey: "inputRadius0")
        f.setValue(radius, forKey: "inputRadius1")
        f.setValue(invert ? CIColor.white : CIColor.black, forKey: "inputColor0")
        f.setValue(invert ? CIColor.black : CIColor.white, forKey: "inputColor1")
        return f.outputImage?.cropped(to: r)
    }

    private static func stripeField(halfWidth: CGFloat, angle: CGFloat, _ r: CGRect) -> CIImage? {
        guard let f = CIFilter(name: "CIStripesGenerator") else { return nil }
        f.setValue(CIVector(x: r.midX, y: r.midY), forKey: "inputCenter")
        f.setValue(CIColor.black, forKey: "inputColor0")
        f.setValue(CIColor.white, forKey: "inputColor1")
        f.setValue(max(2, halfWidth), forKey: "inputWidth")
        f.setValue(0, forKey: "inputSharpness")
        guard var img = f.outputImage else { return nil }
        if angle != 0 {
            let t = CGAffineTransform(translationX: -r.midX, y: -r.midY)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
            img = img.transformed(by: t)
        }
        return img.cropped(to: r)
    }

    private static func noiseField(grain: CGFloat, cloud: Bool, _ r: CGRect) -> CIImage? {
        guard let rg = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        var g = rg.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        if grain > 1 {
            if !cloud { g = g.samplingNearest() }
            g = g.transformed(by: CGAffineTransform(scaleX: grain, y: grain))
        }
        return g.cropped(to: r)
    }

    // MARK: - Pipeline Renderer

    private static func renderBase(_ base: Base, from: CIImage, to: CIImage, e: CGFloat, rect: CGRect) -> CIImage {
        let W = rect.width, H = rect.height
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let ec = clamp01(e)
        let fallback = crossfade(from, to, ec)

        switch base {
        case .dissolve: return fallback
        case .dip(let color):
            let bg = solid(color, rect)
            return ec < 0.5 ? opacity(from, 1 - 2 * ec).composited(over: bg)
                            : opacity(to, 2 * ec - 1).composited(over: bg)
        case .push(let d):
            let v = d.vector
            return move(to, v.x * W * (e - 1), v.y * H * (e - 1))
                .composited(over: move(from, v.x * W * e, v.y * H * e))
        case .cover(let d):
            let v = d.vector
            return move(to, v.x * W * (e - 1), v.y * H * (e - 1)).composited(over: from)
        case .reveal(let d):
            let v = d.vector
            return move(from, v.x * W * e, v.y * H * e).composited(over: to)
        case .wipe(let angle, let soft):
            guard let g = linearField(angle: angle, rect) else { return fallback }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)
        case .iris(let inward, let sx, let soft, let cx, let cy):
            let center = CGPoint(x: cx * W, y: cy * H)
            var R: CGFloat = 0
            for corner in [CGPoint(x: 0, y: 0), CGPoint(x: W, y: 0), CGPoint(x: 0, y: H), CGPoint(x: W, y: H)] {
                R = max(R, hypot((corner.x - center.x) / sx, corner.y - center.y))
            }
            guard var g = radialField(center: center, radius: max(1, R), invert: inward, rect.insetBy(dx: -W, dy: -H)) else { return fallback }
            if sx != 1 {
                let t = CGAffineTransform(translationX: -center.x, y: -center.y)
                    .concatenating(CGAffineTransform(scaleX: sx, y: 1))
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
                g = g.transformed(by: t)
            }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)
        case .blinds(let count, let angle, let soft):
            guard let g = stripeField(halfWidth: W / CGFloat(2 * count), angle: angle, rect) else { return fallback }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)
        case .grid(let cells, let diagonal, let sweep):
            let half = W / CGFloat(2 * cells)
            let rot: CGFloat = diagonal ? .pi / 4 : 0
            guard let gx = stripeField(halfWidth: half, angle: rot, rect),
                  let gy = stripeField(halfWidth: half, angle: rot + .pi / 2, rect) else { return fallback }
            var g = gx.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: gy]).cropped(to: rect)
            if sweep == 1, let lin = linearField(angle: 0, rect) { g = crossfade(g, lin, 0.5) }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: 0.12, rect), rect)
        case .noise(let grain, let cloud, let soft):
            guard let g = noiseField(grain: grain, cloud: cloud, rect) else { return fallback }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)
        case .slices(let count, let vertical):
            var acc = to
            for k in 0..<count {
                let sign: CGFloat = k % 2 == 0 ? 1 : -1
                let strip: CGRect
                var dx: CGFloat = 0, dy: CGFloat = 0
                if vertical {
                    let w = W / CGFloat(count)
                    strip = CGRect(x: CGFloat(k) * w, y: 0, width: w + 0.5, height: H)
                    dy = sign * H * ec
                } else {
                    let h = H / CGFloat(count)
                    strip = CGRect(x: 0, y: CGFloat(k) * h, width: W, height: h + 0.5)
                    dx = sign * W * ec
                }
                acc = move(from.cropped(to: strip), dx, dy).composited(over: acc)
            }
            return acc
        case .doors(let vertical, let open):
            let src = open ? from : to
            let bg = open ? to : from
            let k = open ? ec : (1 - ec)
            if vertical {
                let l = move(src.cropped(to: CGRect(x: 0, y: 0, width: W / 2, height: H)), -W / 2 * k, 0)
                let r = move(src.cropped(to: CGRect(x: W / 2, y: 0, width: W / 2, height: H)), W / 2 * k, 0)
                return l.composited(over: r.composited(over: bg))
            } else {
                let b = move(src.cropped(to: CGRect(x: 0, y: 0, width: W, height: H / 2)), 0, -H / 2 * k)
                let u = move(src.cropped(to: CGRect(x: 0, y: H / 2, width: W, height: H / 2)), 0, H / 2 * k)
                return b.composited(over: u.composited(over: bg))
            }
        case .zoom(let inward, let s):
            if inward {
                return crossfade(scaled(from, 1 + s * ec, rect), scaled(to, 1 + s * (1 - ec), rect), ec)
            } else {
                let under = scaled(to, 1 + 0.75 * s * (1 - ec), rect)
                let top = opacity(scaled(from, 1 - 0.8 * s * ec, rect), 1 - ec)
                return top.composited(over: under)
            }
        case .spin(let cw, let angle):
            let sign: CGFloat = cw ? -1 : 1
            let f = rotated(from, angle: sign * angle * ec, scale: 1 + 0.6 * ec, rect)
            let t = rotated(to, angle: -sign * angle * (1 - ec), scale: 1 + 0.6 * (1 - ec), rect)
            return crossfade(f.composited(over: black(rect)), t.composited(over: black(rect)), ec)
        case .flip(let vertical):
            let useFrom = ec < 0.5
            let img = useFrom ? from : to
            let k = abs(cos((useFrom ? ec : (1 - ec)) * .pi))
            return vertical ? scaledXY(img, 1, k, rect) : scaledXY(img, k, 1, rect)
        case .cube(let left):
            func cubeLeft(_ a: CIImage, _ b: CIImage) -> CIImage {
                let cy = H / 2
                let seam = H * (1 + 0.12 * sin(ec * .pi))
                let fromOuter = H * (1 - 0.3 * ec)
                let toOuter = H * (1 - 0.3 * (1 - ec))
                let xs = W * (1 - ec)
                func face(_ img: CIImage, tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) -> CIImage {
                    ciFilter("CIPerspectiveTransform", img.cropped(to: rect), [
                        "inputTopLeft": vec(tl), "inputTopRight": vec(tr),
                        "inputBottomRight": vec(br), "inputBottomLeft": vec(bl)
                    ]) ?? img
                }
                if xs < 2 { return b }
                if W - xs < 2 { return a }
                let fa = face(a, tl: CGPoint(x: 0, y: cy + fromOuter / 2), tr: CGPoint(x: xs, y: cy + seam / 2),
                              br: CGPoint(x: xs, y: cy - seam / 2), bl: CGPoint(x: 0, y: cy - fromOuter / 2))
                let fb = face(b, tl: CGPoint(x: xs, y: cy + seam / 2), tr: CGPoint(x: W, y: cy + toOuter / 2),
                              br: CGPoint(x: W, y: cy - toOuter / 2), bl: CGPoint(x: xs, y: cy - seam / 2))
                return fb.composited(over: fa)
            }
            func flipX(_ img: CIImage) -> CIImage {
                img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: W, y: 0)))
            }
            return left ? cubeLeft(from, to) : flipX(cubeLeft(flipX(from), flipX(to)))
        case .twirl(let cw, let s):
            let sign: CGFloat = cw ? 1 : -1
            let R = hypot(W, H) * 0.6
            func tw(_ img: CIImage, _ a: CGFloat) -> CIImage {
                ciFilter("CITwirlDistortion", img.clampedToExtent(), ["inputCenter": vec(c), "inputRadius": R, "inputAngle": a])?.cropped(to: rect) ?? img
            }
            return crossfade(tw(from, sign * s * ec), tw(to, -sign * s * (1 - ec)), ec)
        case .bump(let sign):
            let R = min(W, H) * 0.7
            func bp(_ img: CIImage, _ a: CGFloat) -> CIImage {
                ciFilter("CIBumpDistortion", img.clampedToExtent(), ["inputCenter": vec(c), "inputRadius": R, "inputScale": a])?.cropped(to: rect) ?? img
            }
            return crossfade(bp(from, sign * 1.6 * ec), bp(to, sign * 1.6 * (1 - ec)), ec)
        case .pinch(let sign):
            let R = min(W, H) * 0.8
            func pn(_ img: CIImage, _ a: CGFloat) -> CIImage {
                ciFilter("CIPinchDistortion", img.clampedToExtent(), ["inputCenter": vec(c), "inputRadius": R, "inputScale": a])?.cropped(to: rect) ?? img
            }
            return crossfade(pn(from, sign * 1.5 * ec), pn(to, sign * 1.5 * (1 - ec)), ec)
        case .mosaic(let kind, let strength):
            let amount = sin(ec * .pi) * strength * min(W, H) * 0.06
            func mo(_ img: CIImage) -> CIImage {
                guard amount > 1.5 else { return img }
                let src = img.clampedToExtent()
                let out: CIImage?
                switch kind {
                case .pixel: out = ciFilter("CIPixellate", src, ["inputScale": amount, "inputCenter": CIVector(x: 0, y: 0)])
                case .hex: out = ciFilter("CIHexagonalPixellate", src, ["inputScale": amount, "inputCenter": CIVector(x: 0, y: 0)])
                case .crystal: out = ciFilter("CICrystallize", src, ["inputRadius": amount * 0.8, "inputCenter": CIVector(x: 0, y: 0)])
                }
                return out?.cropped(to: rect) ?? img
            }
            return crossfade(mo(from), mo(to), ec)

        // Математические ядра
        case .sineRipple(let freq, let amp):
            let strength = sin(ec * .pi) * amp
            let f = sineRippleKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, freq, strength, c]) ?? from
            let tImg = sineRippleKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, freq, strength, c]) ?? to
            return crossfade(f, tImg, ec)
        case .hyperbolicSaddle(let strength):
            let f = hyperbolicKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, strength, c]) ?? from
            let tImg = hyperbolicKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, strength, c]) ?? to
            return crossfade(f, tImg, ec)
        case .fibonacciSpiral(let turns):
            let angle = ec * turns * 2 * .pi
            let f = rotated(from, angle: angle, scale: 1.0 + 0.5 * ec, rect)
            let tImg = rotated(to, angle: -angle, scale: 1.0 + 0.5 * (1 - ec), rect)
            return crossfade(f.composited(over: black(rect)), tImg.composited(over: black(rect)), ec)
        case .matrixQuantize(let gridSize):
            let amount = sin(ec * .pi) * gridSize * 3.0
            let pix = ciFilter("CIPixellate", from.clampedToExtent(), ["inputScale": max(1, amount), "inputCenter": vec(c)])?.cropped(to: rect) ?? from
            return crossfade(pix, to, ec)

        // Ворпы
        case .liquidWarp(let freq, let amp):
            let strength = sin(ec * .pi) * amp
            let f = liquidWarpKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, freq, strength, c]) ?? from
            let tImg = liquidWarpKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, freq, strength, c]) ?? to
            return crossfade(f, tImg, ec)
        case .perspectiveMorph(let angle):
            let f = perspectiveMorphKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, angle, c]) ?? from
            let tImg = perspectiveMorphKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, angle, c]) ?? to
            return crossfade(f, tImg, ec)
        case .vortexSwirl(let turns):
            let angle = ec * turns * 2 * .pi
            let f = rotated(from, angle: angle, scale: 1.0 + 0.3 * ec, rect)
            let tImg = rotated(to, angle: -angle, scale: 1.0 + 0.3 * (1 - ec), rect)
            return crossfade(f.composited(over: black(rect)), tImg.composited(over: black(rect)), ec)
        case .glassRefraction(let strength):
            let f = glassRefractionKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, strength, c]) ?? from
            let tImg = glassRefractionKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, strength, c]) ?? to
            return crossfade(f, tImg, ec)

        // Новые современные кейсы
        case .whipPan(let d, _):
            let v = d.vector
            let slideFrom = move(from, v.x * W * ec, v.y * H * ec)
            let slideTo = move(to, v.x * W * (ec - 1), v.y * H * (ec - 1))
            return slideTo.composited(over: slideFrom)
        case .velocityZoom(let inward, let ramp):
            let factor = pow(ec, ramp)
            let sFrom = inward ? 1.0 + 1.2 * factor : 1.0 - 0.5 * factor
            let sTo = inward ? 0.4 + 0.6 * factor : 1.5 - 0.5 * factor
            return crossfade(scaled(from, sFrom, rect), scaled(to, sTo, rect), factor)
        case .bounceSnap(let d):
            let v = d.vector
            let offset = sin(ec * .pi) * 0.2
            let moveFrom = move(from, v.x * W * (ec + offset), v.y * H * (ec + offset))
            let moveTo = move(to, v.x * W * (ec - 1 + offset), v.y * H * (ec - 1 + offset))
            return moveTo.composited(over: moveFrom)
        case .crossZoomSpeedRamp:
            let rampFrom = scaled(from, 1.0 + 1.5 * ec * ec, rect)
            let rampTo = scaled(to, 2.5 - 1.5 * ec, rect)
            return crossfade(rampFrom, rampTo, ec)
        case .spatial3DSpin(let axisX, let angle):
            let rot = ec * angle
            let k = abs(cos(rot))
            return axisX ? scaledXY(ec < 0.5 ? from : to, 1, k, rect) : scaledXY(ec < 0.5 ? from : to, k, 1, rect)
        case .vortexSwirlZoom(let turns):
            let a = ec * turns * 2 * .pi
            let f = rotated(from, angle: a, scale: 1.0 + 0.8 * ec, rect)
            let tImg = rotated(to, angle: -a, scale: 1.8 - 0.8 * ec, rect)
            return crossfade(f.composited(over: black(rect)), tImg.composited(over: black(rect)), ec)
        case .fisheyeLens(let str):
            let f = fisheyeKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, str, c]) ?? from
            let tImg = fisheyeKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, str, c]) ?? to
            return crossfade(f, tImg, ec)
        case .warpSlide(let d, let elasticity):
            let v = d.vector
            let f = warpSlideKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, vec(v), elasticity, c]) ?? from
            let tImg = warpSlideKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, vec(v), elasticity, c]) ?? to
            return move(tImg, v.x * W * (ec - 1), v.y * H * (ec - 1)).composited(over: move(f, v.x * W * ec, v.y * H * ec))
        case .rgbAberrationSplit(let shift):
            let d = sin(ec * .pi) * W * shift
            let f = move(from, d, 0)
            let tImg = move(to, -d, 0)
            return crossfade(f, tImg, ec)
        case .displacementBlockGlitch(let blockSize):
            let f = blockGlitchKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, blockSize, c]) ?? from
            let tImg = blockGlitchKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, blockSize, c]) ?? to
            return crossfade(f, tImg, ec)
        case .vhsScanlineStatic(let grain):
            guard let noise = noiseField(grain: grain, cloud: false, rect) else { return fallback }
            let blendedNoise = opacity(noise, sin(ec * .pi) * 0.4)
            return crossfade(from, to, ec).composited(over: blendedNoise)
        case .cyberStrobeQuantize(let bands):
            let step = floor(ec * bands) / bands
            return crossfade(from, to, step)
        case .filmBurnFlash(let warmth):
            let burnColor = solid(CIColor(red: 1.0, green: 0.4 * warmth, blue: 0.1, alpha: 1.0), rect)
            let flashStrength = sin(ec * .pi) * 0.95
            let burnedFrom = opacity(burnColor, flashStrength).composited(over: from)
            return crossfade(burnedFrom, to, ec)
        case .whiteCameraFlash:
            let white = solid(CIColor.white, rect)
            let s = sin(ec * .pi)
            let flashed = opacity(white, s * s * 0.98).composited(over: from)
            return crossfade(flashed, to, ec)
        case .cyberNeonFlare(let color):
            let flare = solid(color, rect)
            let s = sin(ec * .pi)
            let flared = opacity(flare, s * 0.7).composited(over: from)
            return crossfade(flared, to, ec)
        case .lightLeakSweep(let angle):
            let sweepProgress = ec * W * 2 - W
            let sweepRect = CGRect(x: sweepProgress, y: 0, width: W * 0.4, height: H)
            let beam = opacity(solid(CIColor(red: 1, green: 0.85, blue: 0.5), sweepRect), sin(ec * .pi) * 0.8)
            return crossfade(from, to, ec).composited(over: beam)
        case .liquidRipple(let freq, let amp):
            let strength = sin(ec * .pi) * amp
            let f = liquidRippleKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, freq, strength, c]) ?? from
            let tImg = liquidRippleKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, freq, strength, c]) ?? to
            return crossfade(f, tImg, ec)
        case .glassRefractionMesh(let refractIndex):
            let f = glassRefractionKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, refractIndex, c]) ?? from
            let tImg = glassRefractionKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, refractIndex, c]) ?? to
            return crossfade(f, tImg, ec)
        case .heatWaveMirage(let distortion):
            let f = heatWaveKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [from, ec, distortion, c]) ?? from
            let tImg = heatWaveKernel?.apply(extent: rect, roiCallback: { _, r in r }, arguments: [to, 1 - ec, distortion, c]) ?? to
            return crossfade(f, tImg, ec)
        case .blackHolePinch(let gravity):
            let R = min(W, H) * 0.8
            let pFrom = ciFilter("CIPinchDistortion", from.clampedToExtent(), ["inputCenter": vec(c), "inputRadius": R, "inputScale": gravity * ec])?.cropped(to: rect) ?? from
            let pTo = ciFilter("CIPinchDistortion", to.clampedToExtent(), ["inputCenter": vec(c), "inputRadius": R, "inputScale": gravity * (1 - ec)])?.cropped(to: rect) ?? to
            return crossfade(pFrom, pTo, ec)

        // =================================================================
        // PREMIUM-КОЛЛЕКЦИЯ
        // =================================================================

        case .glide(let d, let parallax, let blurK):
            let v = d.vector
            let s = sin(ec * .pi)
            let ang = atan2(v.y, v.x)
            let rad = s * blurK * min(W, H) * 0.045
            let bf = motionBlurred(evAdjust(from, ev: -0.9 * ec), radius: rad, angle: ang)
            let bt = motionBlurred(to, radius: rad, angle: ang)
            let mf = move(bf, v.x * W * ec * parallax, v.y * H * ec * parallax)
            let mt = move(bt, v.x * W * (ec - 1), v.y * H * (ec - 1))
            return mt.composited(over: mf)

        case .dolly(let inward, let depth):
            let mix = smoothstep(0.25, 0.75, ec)
            let settle = scaled(to, 1 + depth * 0.6 * (1 - ec), rect)
            if inward {
                return crossfade(scaled(from, 1 + depth * ec, rect), settle, mix)
            } else {
                let top = opacity(scaled(from, 1 - depth * 0.5 * ec, rect), 1 - mix)
                return top.composited(over: settle)
            }

        case .blurDissolve(let k):
            let r = sin(ec * .pi) * k * min(W, H) * 0.05
            let mix = smoothstep(0.2, 0.8, ec)
            return crossfade(blurred(from, sigma: r, rect), blurred(to, sigma: r, rect), mix)

        case .stretchSwap(let vertical, let amount):
            let mix = smoothstep(0.35, 0.65, ec)
            let kf = 1 + amount * ec * ec
            let kt = 1 + amount * (1 - ec) * (1 - ec)
            let f = vertical ? scaledXY(from, 1, kf, rect) : scaledXY(from, kf, 1, rect)
            let tImg = vertical ? scaledXY(to, 1, kt, rect) : scaledXY(to, kt, 1, rect)
            return crossfade(f, tImg, mix)

        case .driftRotate(let angle, let cw):
            let sign: CGFloat = cw ? -1 : 1
            let a1 = sign * angle * ec
            let a2 = -sign * angle * (1 - ec)
            let f = rotated(from, angle: a1, scale: coverScale(angle: a1, rect), rect)
            let tImg = rotated(to, angle: a2, scale: coverScale(angle: a2, rect), rect)
            return crossfade(f, tImg, smoothstep(0.25, 0.75, ec))

        case .cardStack(let d, let depth):
            let v = d.vector
            let back = scaled(evAdjust(from, ev: -1.4 * ec), 1 - depth * ec, rect)
            let front = move(to, v.x * W * (ec - 1), v.y * H * (ec - 1))
            return front.composited(over: back)

        case .cardPeel(let d, let depth):
            let v = d.vector
            let under = scaled(evAdjust(to, ev: -1.4 * (1 - ec)), 1 - depth * (1 - ec), rect)
            let top = move(from, v.x * W * ec, v.y * H * ec)
            return top.composited(over: under)

        case .featherWipe(let angle, let soft, let blurK):
            guard let g = linearField(angle: angle, rect) else { return fallback }
            let mask = threshold(g, e: ec, soft: soft, rect)
            let r = sin(ec * .pi) * blurK * min(W, H) * 0.03
            return revealWithMask(blurred(to, sigma: r, rect), over: blurred(from, sigma: r, rect), mask: mask, rect)

        case .glassSweep(let angle, let band, let blurK):
            guard let g = linearField(angle: angle, rect) else { return fallback }
            let sf: CGFloat = 0.12
            let pr = ec * (1 + band) - band * 0.5
            let revealed = revealWithMask(to, over: from, mask: threshold(g, e: pr, soft: sf, rect), rect)
            let hi = threshold(g, e: pr + band * 0.5, soft: sf, rect)
            let lo = threshold(g, e: pr - band * 0.5, soft: sf, rect)
            let frosted = evAdjust(blurred(revealed, sigma: min(W, H) * 0.035 * blurK, rect), ev: 0.15)
            return revealWithMask(frosted, over: revealed, mask: maskBand(hi, minus: lo, rect), rect)

        case .lineWipe(let angle, let width):
            guard let g = linearField(angle: angle, rect) else { return fallback }
            let sf: CGFloat = 0.006
            let ep = ec * (1 + width * 12)
            let m0 = threshold(g, e: ep, soft: sf, rect)
            let wiped = revealWithMask(to, over: from, mask: m0, rect)
            func band(_ w: CGFloat) -> CIImage {
                maskBand(m0, minus: threshold(g, e: ep - w, soft: sf, rect), rect)
            }
            let glow = revealWithMask(evAdjust(wiped, ev: 0.8), over: wiped, mask: scaleMask(band(width * 10), 0.55), rect)
            return revealWithMask(solid(CIColor(red: 1, green: 1, blue: 1), rect), over: glow, mask: scaleMask(band(width), 0.9), rect)

        case .staggerPanels(let count, let vertical, let reverse):
            var acc = from
            let n = CGFloat(max(1, count))
            let spread: CGFloat = 0.45
            let sgn: CGFloat = reverse ? 1 : -1
            for k in 0..<max(1, count) {
                let idx = reverse ? CGFloat(max(1, count) - 1 - k) : CGFloat(k)
                let delay = spread * idx / max(1, n - 1)
                let p = cubicInOut((ec - delay) / (1 - spread))
                if p <= 0.0005 { continue }
                let strip: CGRect
                var dx: CGFloat = 0, dy: CGFloat = 0
                if vertical {
                    let w = W / n
                    strip = CGRect(x: rect.minX + CGFloat(k) * w, y: rect.minY, width: w + 0.5, height: H)
                    dy = sgn * (1 - p) * H
                } else {
                    let h = H / n
                    strip = CGRect(x: rect.minX, y: rect.minY + CGFloat(k) * h, width: W, height: h + 0.5)
                    dx = sgn * (1 - p) * W
                }
                acc = move(to.cropped(to: strip), dx, dy).composited(over: acc)
            }
            return acc

        case .dipHold(let color, let hold):
            let bg = solid(color, rect)
            let a = 0.5 - hold / 2, b = 0.5 + hold / 2
            if ec < a {
                return opacity(from, 1 - smoothstep(0, a, ec)).composited(over: bg)
            } else if ec > b {
                return opacity(to, smoothstep(b, 1, ec)).composited(over: bg)
            }
            return bg

        case .rich(let kind, let a, let b):
            return renderRich(kind, from: from, to: to, e: ec, a: a, b: b, rect: rect)
                ?? crossfade(from, to, smoothstep(0.2, 0.8, ec))
        }
    }

    // MARK: - Post FX Engine

    private static func applyFx(_ fx: Fx, _ img: CIImage, t: CGFloat, rect: CGRect) -> CIImage {
        let W = rect.width, H = rect.height
        let s = sin(clamp01(t) * .pi)
        guard s > 0.001 else { return img }

        func addColor(_ c: CIColor, _ amount: CGFloat) -> CIImage {
            let overlay = solid(CIColor(red: c.red * amount, green: c.green * amount, blue: c.blue * amount, alpha: 1), rect)
            return overlay.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: rect)
        }

        switch fx {
        case .none: return img
        case .blur: return blurred(img, sigma: s * min(W, H) * 0.035, rect)
        case .zoomBlur:
            let amount = s * 80
            return ciFilter("CIZoomBlur", img.clampedToExtent(), ["inputCenter": vec(CGPoint(x: rect.midX, y: rect.midY)), "inputAmount": amount])?.cropped(to: rect) ?? img
        case .directionalBlur:
            let amount = s * W * 0.06
            return move(img, sin(t * .pi) * amount, 0).composited(over: blurred(img, sigma: s * 10, rect))
        case .rgb:
            let d = s * W * 0.05
            func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
                img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ])
            }
            let red = move(channel(1, 0, 0), d, 0)
            let green = channel(0, 1, 0)
            let blue = move(channel(0, 0, 1), -d, 0)
            let rg = green.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: red])
            return blue.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rg]).cropped(to: rect)
        case .dualAberration:
            let d = s * W * 0.08
            let cyan = ciFilter("CIColorMatrix", img, [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0)
            ]) ?? img
            let red = ciFilter("CIColorMatrix", img, [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]) ?? img
            let shiftedRed = move(red, d * sin(t * 12), d * cos(t * 12))
            return shiftedRed.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: cyan]).cropped(to: rect)
        case .shake:
            let big = scaled(img, 1.08, rect)
            return move(big, sin(t * 60) * s * W * 0.04, cos(t * 45) * s * H * 0.02)
        case .flash: return addColor(CIColor(red: 1, green: 1, blue: 1), s * s * 0.98)
        case .goldFlash: return addColor(CIColor(red: 1, green: 0.78, blue: 0.35), s * s * 0.92)
        case .filmBurn:
            let orange = CIColor(red: 1.0, green: 0.35, blue: 0.05)
            return addColor(orange, s * s * 0.95)
        case .neonFlare:
            let cyan = CIColor(red: 0.0, green: 0.85, blue: 1.0)
            return addColor(cyan, s * 0.85)
        case .cyberpunk:
            let cyan = CIColor(red: 0, green: 0.8, blue: 1)
            let flashed = addColor(cyan, s * 0.6)
            return ciFilter("CIHueAdjustment", flashed.clampedToExtent(), [kCIInputAngleKey: s * 1.5])?.cropped(to: rect) ?? flashed
        case .chromatic:
            let d = s * W * 0.06
            return ciFilter("CIZoomBlur", img.clampedToExtent(), [
                "inputCenter": vec(CGPoint(x: rect.midX, y: rect.midY)), "inputAmount": s * 55
            ])?.cropped(to: rect) ?? img
        case .tilt:
            return rotated(img, angle: s * 0.18, scale: 1 + 0.2 * s, rect)

        // Premium-эффекты: деликатные, без кислотных цветов
        case .softBlur:
            return blurred(img, sigma: s * min(W, H) * 0.018, rect)
        case .zoomBlurSoft:
            return ciFilter("CIZoomBlur", img.clampedToExtent(), [
                "inputCenter": vec(CGPoint(x: rect.midX, y: rect.midY)), "inputAmount": s * 28
            ])?.cropped(to: rect) ?? img
        case .bloom:
            let radius = min(60, s * min(W, H) * 0.03)
            return ciFilter("CIBloom", img.clampedToExtent(), [
                "inputRadius": radius, "inputIntensity": s * 0.9
            ])?.cropped(to: rect) ?? img
        case .softGlow:
            let glow = blurred(img, sigma: s * min(W, H) * 0.03, rect)
            return crossfade(img, glow, s * 0.7)
        case .vignette:
            return ciFilter("CIVignette", img, [
                "inputIntensity": s, "inputRadius": 1.2
            ])?.cropped(to: rect) ?? img
        case .grain:
            guard let rg = CIFilter(name: "CIRandomGenerator")?.outputImage else { return img }
            let k = floor(t * 24)
            let noise = rg
                .transformed(by: CGAffineTransform(translationX: k * 131, y: k * 73))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
                ])
                .cropped(to: rect)
            let grained = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: rect)
            return crossfade(img, grained, s * 0.4)
        case .exposure:
            return evAdjust(img, ev: s * 0.9)
        case .mono:
            return ciFilter("CIColorControls", img, [
                "inputSaturation": 1 - 0.85 * s, "inputContrast": 1 + 0.08 * s
            ])?.cropped(to: rect) ?? img
        case .champagne:
            return addColor(CIColor(red: 0.93, green: 0.80, blue: 0.58), s * s * 0.38)
        case .pearl:
            return addColor(CIColor(red: 0.90, green: 0.93, blue: 1.0), s * s * 0.34)
        case .subtleChroma:
            return chromaSplit(img, shift: s * W * 0.012, rect)
        case .lensBreath:
            return scaled(img, 1 + 0.035 * s, rect)
        }
    }
}
