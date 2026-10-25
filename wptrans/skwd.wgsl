// skwd-wall's wallpaper transitions (github.com/liixini/skwd-paper, crates/paper-shaders, MIT; most of them gl-transitions', MIT too),
// rewritten for a group's shader. Each of skwd's is one shader that reads the old picture and the new one and mixes them; a group's shader
// reads only what its group holds. So each is split in two layers, drawn by two groups with this one shader: the old picture as it is bent
// (opaque), and over it the new one as it is bent, covering by how much of it shows. `mix(old, new, w)` is exactly that: the old, and the
// new over it at `w`. What both pictures go through after the mix (a fade to a colour, ink, a light) is put on each of them, which comes to
// the same. The four whose mix reads both pictures at once (morph, colour-distance, glitch-displace, heat-melt) are left out, and so are the
// sand ones (each pixel a grain: a vertex shader).
//
// s.a.x progress (0..1) · s.a.y which one (1..26, the table in wptrans.luau) · s.a.z the layer: 0 the old picture, 1 the new one
// s.a.w 1 where the screen encodes a shader's output again (see hexreveal.wgsl) · s.b.x, s.b.y where it starts (0..1 of the screen; the
// iris, the circle and the inks open from there)

fn to_light(c: vec3<f32>) -> vec3<f32> {
    let v = max(c, vec3<f32>(0.0));
    return select(pow((v + vec3<f32>(0.055)) / 1.055, vec3<f32>(2.4)), v / 12.92, v <= vec3<f32>(0.04045));
}

const PI: f32 = 3.14159265358979;

// GLSL's smoothstep, for edges either way round
fn ss(e0: f32, e1: f32, x: f32) -> f32 {
    let t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// this layer's picture at `uv` (0..1), held inside the screen as GL's clamp to edge does. A group's box has a pixel of nothing round what
// it holds, so the edge it is held to is two pixels in: at the box's own edge a warp that reaches past the picture reads black.
fn pic(s: Shader, uv: vec2<f32>) -> vec3<f32> {
    let at = clamp(uv * s.size, vec2<f32>(2.0), s.size - vec2<f32>(2.0));
    return inside(s, at).rgb;
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// GLSL's mod
fn gmod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash1(i), hash1(i + vec2<f32>(1.0, 0.0)), f.x),
               mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), f.x), f.y);
}

fn fbm5(p0: vec2<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var p = p0;
    for (var i = 0; i < 5; i++) {
        v += amp * vnoise(p);
        p *= 2.1;
        amp *= 0.5;
    }
    return v;
}

fn fbm6(p0: vec2<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var p = p0;
    for (var i = 0; i < 6; i++) {
        v += amp * vnoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return v;
}

// how far the farthest corner is from `o`, with x in the screen's shape (so that a ring from there reaches every corner)
fn far_corner(o: vec2<f32>, ar: f32) -> f32 {
    let dx = max(o.x, 1.0 - o.x) * ar;
    let dy = max(o.y, 1.0 - o.y);
    return length(vec2<f32>(dx, dy));
}

// Each returns this layer's colour, and in .w how much the new layer covers (the old layer ignores it).
fn tr(s: Shader, k: i32, p: f32, uv: vec2<f32>, nl: bool) -> vec4<f32> {
    let ar = s.size.x / max(s.size.y, 1.0);
    let o = s.b.xy;
    let black = vec3<f32>(0.0);

    switch k {
        // crosswarp
        case 1: {
            let x = ss(0.0, 1.0, p * 2.0 + uv.x - 1.0);
            let c = select(pic(s, (uv - 0.5) * (1.0 - x) + 0.5), pic(s, (uv - 0.5) * x + 0.5), nl);
            return vec4<f32>(c, x);
        }
        // circle-crop: the old one closes to black, the new one opens from it
        case 2: {
            let sr = pow(2.0 * abs(p - 0.5), 3.0);
            let dist = length((uv - o) * vec2<f32>(1.0, 1.0 / ar));
            let out = step(sr, dist);
            if (p < 0.5) {
                return vec4<f32>(mix(pic(s, uv), black, out), 0.0);
            }
            return vec4<f32>(select(black, pic(s, uv), nl), 1.0 - out);
        }
        // directional: the old one slides up and the new one follows it
        case 3: {
            let q = uv + p * vec2<f32>(0.0, 1.0);
            let f = fract(q);
            let m = step(0.0, q.y) * step(q.y, 1.0) * step(0.0, q.x) * step(q.x, 1.0);
            return vec4<f32>(pic(s, f), 1.0 - m);
        }
        // directional-scaled
        case 4: {
            let e = pow(sin(p * PI / 2.0), 3.0);
            let q = uv + e * vec2<f32>(0.0, 1.0);
            var f = fract(q);
            let sc = 1.0 - (1.0 - (1.0 / 0.7)) * sin(p * PI);
            f = (f - 0.5) * sc + 0.5;
            let m = step(0.0, q.y) * step(q.y, 1.0) * step(0.0, q.x) * step(q.x, 1.0);
            let border = step(0.0, f.x) * step(0.0, 1.0 - f.x) * step(0.0, f.y) * step(0.0, 1.0 - f.y);
            return vec4<f32>(pic(s, f) * border, 1.0 - m);
        }
        // polka-dots-curtain
        case 5: {
            let hit = distance(fract(uv * 20.0), vec2<f32>(0.5)) < p / max(distance(uv, vec2<f32>(0.0)), 0.0001);
            return vec4<f32>(pic(s, uv), select(0.0, 1.0, hit));
        }
        // puzzle-right
        case 6: {
            let pause = 0.1;
            let dw = 0.005;
            let cell = floor(4.0 * uv);
            let lo = cell * 0.25;
            let hi = lo + vec2<f32>(0.25);
            let delta = min(min(abs(uv.x - lo.x), abs(uv.x - hi.x)), min(abs(uv.y - lo.y), abs(uv.y - hi.y)));
            if (p < pause) {
                let a = select(1.0, 1.0 - p / pause, delta < dw);
                return vec4<f32>(mix(black, pic(s, uv), a), 0.0);
            } else if (p < 1.0 - pause) {
                if (delta < dw) {
                    return vec4<f32>(black, 0.0);
                }
                let cp = (p - pause) / (1.0 - pause * 2.0);
                let r = rand(cell) - 0.1;
                let c = ss(0.0, 1.0 - r, cp);
                let left = cell.x * 0.25;
                let off = 0.125 + left;
                let half = max(abs(c - 0.5), 0.0001);
                let q = vec2<f32>((uv.x - off) / half * 0.5 + off, uv.y);
                let shown = step(abs(4.0 * (uv.x - left) - 0.5), abs(c - 0.5));
                return vec4<f32>(pic(s, q) * shown, 1.0 - step(c, 0.5));
            }
            let a = select(1.0, (p - 1.0 + pause) / pause, delta < dw);
            return vec4<f32>(select(black, pic(s, uv), nl), a);
        }
        // crosshatch
        case 7: {
            let dist = distance(vec2<f32>(0.5), uv) / 3.0;
            let r = p - min(rand(vec2<f32>(uv.y, 0.0)), rand(vec2<f32>(0.0, uv.x)));
            let w = mix(0.0, mix(step(dist, r), 1.0, ss(0.9, 1.0, p)), ss(0.0, 0.1, p));
            return vec4<f32>(pic(s, uv), w);
        }
        // directional-wipe: a soft edge, corner to corner
        case 8: {
            var v = normalize(vec2<f32>(1.0, -1.0));
            v /= abs(v.x) + abs(v.y);
            let d = v.x * 0.5 + v.y * 0.5;
            let w = (1.0 - step(p, 0.0)) * (1.0 - ss(-0.5, 0.0, v.x * uv.x + v.y * uv.y - (d - 0.5 + p * 1.5)));
            return vec4<f32>(pic(s, uv), w);
        }
        // fadecolor: through black
        case 9: {
            let a = select(ss(0.6, 0.0, p), ss(0.4, 1.0, p), nl);
            return vec4<f32>(mix(black, pic(s, uv), a), p);
        }
        // parametric-glitch: the old one spirals away
        case 10: {
            if (nl) {
                return vec4<f32>(pic(s, uv), p);
            }
            let c0 = pic(s, uv);
            let sphere = dot(c0, c0) - 1.0;
            let sx = cos(sphere - uv.x / (p + 0.01));
            let sy = sin(sphere - uv.y / (p + 0.01));
            let st = fract(uv * vec2<f32>(sx, sy));
            return vec4<f32>(pic(s, uv + p * (uv - st)), p);
        }
        // perlin
        case 11: {
            let st = uv * 4.0;
            let i = floor(st);
            let f = fract(st);
            let a = fract(sin(gmod(dot(i, vec2<f32>(12.9898, 78.233)), 3.14)) * 43758.5453);
            let b = fract(sin(gmod(dot(i + vec2<f32>(1.0, 0.0), vec2<f32>(12.9898, 78.233)), 3.14)) * 43758.5453);
            let c = fract(sin(gmod(dot(i + vec2<f32>(0.0, 1.0), vec2<f32>(12.9898, 78.233)), 3.14)) * 43758.5453);
            let dd = fract(sin(gmod(dot(i + vec2<f32>(1.0, 1.0), vec2<f32>(12.9898, 78.233)), 3.14)) * 43758.5453);
            let u = f * f * (3.0 - 2.0 * f);
            let n = mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (dd - b) * u.x * u.y;
            let pp = mix(-0.01, 1.01, p);
            return vec4<f32>(pic(s, uv), 1.0 - ss(pp - 0.01, pp + 0.01, n));
        }
        // randomsquares
        case 12: {
            let r = rand(floor(vec2<f32>(10.0) * uv));
            return vec4<f32>(pic(s, uv), ss(0.0, -0.5, r - p * 1.5));
        }
        // crossfade
        case 13: {
            return vec4<f32>(pic(s, uv), ss(0.0, 1.0, p));
        }
        // pixelate (square blocks, whatever the screen's shape)
        case 14: {
            let bump = 1.0 - abs(p - 0.5) * 2.0;
            let blocks = mix(800.0, 12.0, bump) * vec2<f32>(ar, 1.0);
            let q = floor(uv * blocks) / blocks + 0.5 / blocks;
            return vec4<f32>(pic(s, q), ss(0.0, 1.0, p));
        }
        // iris: a circle opens with a split of colour on its edge
        case 15: {
            var c = uv - o;
            c.x *= ar;
            let d = length(c);
            let r = p * far_corner(o, ar) * 1.18;
            let t = ss(r + 0.05, r - 0.05, d);
            if (!nl) {
                return vec4<f32>(pic(s, uv), t);
            }
            let edge = exp(-abs(d - r) * 100.0);
            let chrom = vec3<f32>(pic(s, uv + vec2<f32>(0.012, 0.0) * edge).r, pic(s, uv).g, pic(s, uv - vec2<f32>(0.012, 0.0) * edge).b);
            return vec4<f32>(chrom, t);
        }
        // glitch
        case 16: {
            let un = floor(vec2<f32>(p) * vec2<f32>(1200.0, 3500.0)) / vec2<f32>(64.0);
            let dist = select(vec2<f32>(0.0), (fract(un) - 0.5) * 0.3 * (1.0 - p), p > 0.0);
            let c = vec3<f32>(pic(s, uv + dist * 0.2).r, pic(s, uv + dist * 0.3).g, pic(s, uv + dist * 0.5).b);
            return vec4<f32>(c, p);
        }
        // voronoi-shatter: the old one breaks into shards that fly off
        case 17: {
            let sp = uv * 14.0;
            let g = floor(sp);
            let f = fract(sp);
            var min_d = 100.0;
            var cell = g;
            for (var y = -1; y <= 1; y++) {
                for (var x = -1; x <= 1; x++) {
                    let nb = vec2<f32>(f32(x), f32(y));
                    let h = fract(sin(vec2<f32>(dot(g + nb, vec2<f32>(127.1, 311.7)), dot(g + nb, vec2<f32>(269.5, 183.3)))) * 43758.5453);
                    let q = nb + h - f;
                    let d = dot(q, q);
                    if (d < min_d) {
                        min_d = d;
                        cell = g + nb;
                    }
                }
            }
            let hc = fract(sin(vec2<f32>(dot(cell, vec2<f32>(127.1, 311.7)), dot(cell, vec2<f32>(269.5, 183.3)))) * 43758.5453);
            let dir = normalize(hc - 0.5 + vec2<f32>(0.0001));
            let shard = ss(hc.x * 0.5, hc.x * 0.5 + 0.5, p);
            let c = select(pic(s, uv - dir * shard * 1.5), pic(s, uv), nl);
            return vec4<f32>(c, ss(0.0, 0.5, shard));
        }
        // plasma-flow
        case 18: {
            let flow = vec2<f32>(vnoise(uv * 5.0 + vec2<f32>(p * 2.0, 0.0)), vnoise(uv * 5.0 + vec2<f32>(0.0, p * 2.0))) - 0.5;
            let q = uv + flow * sin(p * PI) * 0.18;
            return vec4<f32>(pic(s, q), ss(0.2, 0.8, p));
        }
        // ink-splash: a blot of ink spreads from where it was picked
        case 19: {
            let blob = fbm5(uv * 3.5);
            let fingers = fbm5(uv * 14.0);
            let distortion = (blob - 0.5) * 0.5 + (fingers - 0.5) * 0.18;
            var c = uv - o;
            c.x *= ar;
            let diff = length(c) + distortion - (p * far_corner(o, ar) * 1.67 - 0.15);
            let reveal = ss(0.04, -0.04, diff);
            let edge = ss(0.16, 0.02, diff) * (1.0 - ss(0.02, -0.04, diff));
            let ink = vec3<f32>(0.03, 0.01, 0.06);
            var col = mix(pic(s, uv), ink, edge * 0.95);
            col = mix(col, ink, ss(0.25, 0.05, diff) * (1.0 - reveal) * fingers * 0.4);
            return vec4<f32>(col, reveal);
        }
        // smoke
        case 20: {
            let t = p * 12.0;
            let wp = uv * 2.0;
            let q = vec2<f32>(fbm6(wp), fbm6(wp + vec2<f32>(5.2, 1.3)));
            let wr = vec2<f32>(fbm6(wp + 6.0 * q + vec2<f32>(1.7, 9.2) + 0.25 * t), fbm6(wp + 6.0 * q + vec2<f32>(8.3, 2.8) + 0.22 * t));
            let fluid = fbm6(wp + 5.0 * wr);
            let vis = (1.0 - length((uv - 0.5) * vec2<f32>(1.0, 0.7))) * 1.2 + fluid * 0.7;
            let mask = ss(vis - 0.4, vis + 0.4, p * 2.5 - 0.4);
            let q2 = uv + (wr - 0.5) * sin(p * PI) * 0.35;
            return vec4<f32>(pic(s, q2), mask);
        }
        // chromatic-bloom (each picture blooms with its own light: skwd's blooms both with the new one's, which one layer cannot read)
        case 21: {
            let inten = sin(p * PI);
            let dir = (uv - 0.5) * inten * 0.15;
            var col = vec3<f32>(pic(s, uv + dir).r, pic(s, uv).g, pic(s, uv - dir).b);
            var bloom = vec3<f32>(0.0);
            for (var i = 1; i <= 4; i++) {
                let r = f32(i) * 0.01 * inten;
                bloom += pic(s, uv + vec2<f32>(r, 0.0)) + pic(s, uv - vec2<f32>(r, 0.0));
                bloom += pic(s, uv + vec2<f32>(0.0, r)) + pic(s, uv - vec2<f32>(0.0, r));
            }
            col += bloom / 16.0 * 0.5 * inten;
            return vec4<f32>(min(col, vec3<f32>(1.0)), ss(0.4, 0.6, p));
        }
        // inkwell-drop: rings run out from where it was picked
        case 22: {
            var c = uv - o;
            c.x *= ar;
            let d = length(c);
            let front = p * (far_corner(o, ar) + 0.2);
            let ring1 = sin((d - front) * 80.0) * exp(-abs(d - front) * 6.0);
            let ring2 = sin((d - front + 0.08) * 80.0) * exp(-abs(d - front + 0.08) * 8.0) * 0.6;
            let ring3 = sin((d - front + 0.16) * 80.0) * exp(-abs(d - front + 0.16) * 10.0) * 0.4;
            let ripple = (ring1 + ring2 + ring3) * 0.05 * (1.0 - p);
            let dir = select(vec2<f32>(0.0), normalize(c), d > 0.001);
            let crest = exp(-abs(d - front) * 25.0) * (1.0 - p);
            let col = pic(s, uv + dir * ripple) + vec3<f32>(0.6, 0.75, 0.95) * crest * 0.5;
            return vec4<f32>(min(col, vec3<f32>(1.0)), ss(0.05, -0.02, d - front));
        }
        // pixelfade-wave
        case 23: {
            let wave = ss(0.0, 1.0, p * 1.6 - (uv.x + uv.y) * 0.5 * 0.6);
            let blocks = mix(800.0, 8.0, sin(wave * PI)) * vec2<f32>(ar, 1.0);
            let q = floor(uv * blocks) / blocks + 0.5 / blocks;
            return vec4<f32>(pic(s, q), ss(0.0, 1.0, wave));
        }
        // soft-warp-fade
        case 24: {
            let warp = vec2<f32>(vnoise(uv * 3.0 + vec2<f32>(0.0, p * 0.5)), vnoise(uv * 3.0 + vec2<f32>(p * 0.5, 0.0))) - 0.5;
            var t = ss(0.05, 0.95, p);
            t = t * t * (3.0 - 2.0 * t);
            return vec4<f32>(pic(s, uv + warp * sin(p * PI) * 0.025), t);
        }
        // zoom-blur-pull
        case 25: {
            let center = vec2<f32>(0.25 + 0.5 * p, 0.5);
            var dissolve = p;
            if (p > 0.0 && p < 1.0) {
                let t2 = p * 2.0;
                dissolve = select(0.5 * (2.0 - pow(2.0, -10.0 * (t2 - 1.0))), 0.5 * pow(2.0, 10.0 * (t2 - 1.0)), t2 < 1.0);
            }
            let strength = 0.2 * (1.0 - cos(2.0 * PI * p));
            if (strength < 0.005) {
                return vec4<f32>(pic(s, uv), dissolve);
            }
            var col = vec3<f32>(0.0);
            var total = 0.0;
            let off = rand(uv);
            for (var i = 0; i <= 12; i++) {
                let pct = (f32(i) + off) / 12.0;
                let wt = 4.0 * (pct - pct * pct);
                col += pic(s, uv + (center - uv) * pct * strength) * wt;
                total += wt;
            }
            return vec4<f32>(col / max(total, 0.0001), dissolve);
        }
        // mosaic-tumble: the screen pulls back to a wall of tiles and flies to the new one
        case 26: {
            let q = uv - 0.5;
            let rpr = p * 2.0 - 1.0;
            let z = abs(-(rpr * rpr * 2.0) + 3.0);
            let ci = -cos(p * PI) / 2.0 + 0.5;
            let rp = q * z + mix(vec2<f32>(0.5, 0.5), vec2<f32>(2.5, -0.5), ci * ci);
            let mrp = fract(rp);
            let cr = floor(rp);
            if (cr.x == 2.0 && cr.y == -1.0) {
                return vec4<f32>(pic(s, mrp), 1.0);
            }
            if (cr.x == 0.0 && cr.y == 0.0) {
                return vec4<f32>(pic(s, mrp), 0.0);
            }
            let rr = rand(cr);
            let ang = floor(rr * 4.0) * 0.5 * PI;
            let m = mrp - 0.5;
            let rot = vec2<f32>(0.5) + vec2<f32>(cos(ang) * m.x + sin(ang) * m.y, -sin(ang) * m.x + cos(ang) * m.y);
            return vec4<f32>(pic(s, rot), select(0.0, 1.0, rr > 0.5));
        }
        default: {
            return vec4<f32>(pic(s, uv), p);
        }
    }
}

fn shade(s: Shader) -> vec4<f32> {
    let p = clamp(s.a.x, 0.0, 1.0);
    let nl = s.a.z > 0.5;
    var r: vec4<f32>;
    // Once it is over, the new picture itself, whole: what awww is about to show.
    if (p >= 0.999) {
        r = vec4<f32>(pic(s, s.uv), 1.0);
    } else {
        r = tr(s, i32(s.a.y + 0.5), p, s.uv, nl);
    }
    let rgb = select(r.rgb, to_light(r.rgb), s.a.w > 0.5);
    // the old layer covers the screen; the new one covers by how much of it shows
    return vec4<f32>(rgb, select(1.0, clamp(r.w, 0.0, 1.0), nl));
}
