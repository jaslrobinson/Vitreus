// The Paper theme's e-ink texture. Nothing here reads s.time, so it costs nothing while a drawer is still.
// s.a.y is the mode:
//   0  grain: still paper fibre over a drawer. s.a.x how strong, s.color the ink.
//   1  dithered shadow: the box is the drawer grown by s.a.z on every side. The drawer (corner s.a.w) is left clear; round it,
//      a copy moved by (s.b.x, s.b.y) is filled with ordered-dither dots at density s.a.x, thinning to nothing over s.b.z. s.b.w the dots' opacity.
//   2  dither fade: s.color solid at the top of the box, dithered away to nothing at the bottom (the edge of a drawer's pastel tab).

fn hash(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(0.1031, 0.1030));
    q = q + dot(q, q.yx + vec2<f32>(33.33, 33.33));
    return fract((q.x + q.y) * q.x);
}

// The 4 by 4 Bayer threshold for a cell, 0 to 1: how e-ink fakes grey with dots.
fn bayer4(c: vec2<f32>) -> f32 {
    let x = i32(c.x) & 3;
    let y = i32(c.y) & 3;
    var m = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    return (m[y * 4 + x] + 0.5) / 16.0;
}

fn rrect(p: vec2<f32>, c: vec2<f32>, h: vec2<f32>, r: f32) -> f32 {
    let q = abs(p - c) - h + vec2<f32>(r, r);
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn shade(s: Shader) -> vec4<f32> {
    let cell = floor(s.pos / 2.0);                       // dots two logical pixels square
    if (s.a.y < 0.5) {
        let n = hash(floor(s.pos));
        let fibre = hash(vec2<f32>(floor(s.pos.y / 1.5), floor(s.pos.x / 23.0)));
        let fleck = clamp((n - 0.93) / 0.07, 0.0, 1.0);
        let a = max(fleck * 0.9, step(0.985, fibre) * 0.5);
        return vec4<f32>(s.color.rgb, a * s.a.x);
    }
    if (s.a.y < 1.5) {
        let c = s.size * 0.5;
        let h = s.size * 0.5 - vec2<f32>(s.a.z, s.a.z);
        if (rrect(s.pos, c, h, s.a.w) < 0.0) {
            return vec4<f32>(0.0, 0.0, 0.0, 0.0);
        }
        // Only below and to the right, like light from the top left: nothing left of the drawer or above it (on the left it is joined to the strip).
        if (s.pos.x < s.a.z + s.b.x || s.pos.y < s.a.z + s.b.y) {
            return vec4<f32>(0.0, 0.0, 0.0, 0.0);
        }
        let d = rrect(s.pos, c + vec2<f32>(s.b.x, s.b.y), h, s.a.w);
        let fall = clamp(1.0 - max(d, 0.0) / max(s.b.z, 1.0), 0.0, 1.0);
        let dens = fall * fall * s.a.x;
        let on = step(bayer4(cell), dens);
        return vec4<f32>(s.color.rgb, on * s.b.w);
    }
    let dens = 1.0 - s.uv.y;
    return vec4<f32>(s.color.rgb, step(bayer4(cell), dens));
}
