# Paper Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fifth Vitreus look, "Paper": cream paper drawers, pure-black text, a pastel tab per drawer, still paper grain and dithered e-ink shadows, Literata.

**Architecture:** Follows upstream's Cyber theme (commit 8f2f42c): a theme number in `vitreus.luau` (`iris_fx.PAPER = 11`) that applies a fixed palette and sets `fact paper_on`; a `paper_k` blend in `vitreus.plm` that joins the plastic body (`pk`); a new body layer in `pages/bar_glass.plm` and `pages/overview.plm`; decorations in a new part `pages/paper_deco.plm` drawing a new shader `paper.wgsl`; a fifth card on `pages/theme.plm`.

**Tech Stack:** pleamar 0.4.0 (`.plm` scenes, Luau logic, WGSL shaders), Hyprland.

**Spec:** `docs/superpowers/specs/2026-10-14-paper-theme-design.md`

## Global Constraints

- Repo: `~/.config/pleamar/shells/vitreus`, branch `fx`. Commit there; never push.
- Palette exactly: tint `#f4efe4`, panel `#ebe5d6`, ink `#000000`, faint `#8a857a`, off `#d9d3c4`, mint `#9d8fd6`, mintlo `#8a7cc6`, minthi `#d9d0f5`, onmint `#000000`, deep `#f2b8a0`, alert `#e07a7a`.
- Pastels exactly, as named lets (never inline hex at use sites): `pp_lav #d8d0f2`, `pp_peach #f7d6c6`, `pp_mint #cde9da`, `pp_sky #cfe0f3`, `pp_butter #f4e7b8`, `pp_rose #f2cfdc`.
- Drawer → pastel: `dk` controls → pp_lav · `dc` calendar → pp_peach · `dm` player/tray → pp_mint · `do` volume/notifications → pp_sky · `dz` desk → pp_sky · `ds` settings → pp_butter · `dl` launcher → pp_rose.
- Paper keeps the liquid (it joins `pk`, NOT `sq` and NOT `cas_k`).
- Static check (the repo's only automated test): `cd ~/.config/pleamar/shells/vitreus && pleamar --check vitreus.plm` must end with `vitreus.plm: ok`. The two existing `note` lines about `osd_drawer.plm` are pre-existing and fine.
- Live check: the running shell is under `vitreus-keep`; restart with `pleamar --say vitreus quit` (the keeper relaunches it in ~2 s). Log: `/tmp/vitreus.log`. Screenshot: `grim <file>.png` (one 2560x1600 output). Open things with `pleamar --say vitreus "fact panel controls|settings|none"`, switch themes with `pleamar --say vitreus "emit theme_pick N"` (0 Glass, 8 Retro, 9 UwU, 10 Cyber, 11 Paper).

---

### Task 1: Paper switch, palette and paper body

**Files:**
- Modify: `vitreus.luau` (iris_fx constants ~2765; iris.json load ~2779/2782; `push_look`/`show()` ~2793–2807; start-up palette ~2816–2820; `theme_pick` ~2835–2852; `HY_ROUND_DEFAULT` ~4468)
- Modify: `vitreus.plm` (look facts ~300–332, `shader matrix` declaration)
- Modify: `pages/bar_glass.plm` (after the UwU body, ~line 80)
- Modify: `pages/overview.plm` (after its UwU body, ~line 94)
- Modify: `pages/bar_icons.plm:7` (icon halo)

**Interfaces:**
- Produces: `iris_fx.PAPER = 11`, `iris_fx.paper` (palette table), `fact paper_on`, `prop paper_k` (0..1), `shader paper = file "paper.wgsl"` declaration (file created in Task 2), theme key `"paper"` passed to `hy_theme_changed`.

- [ ] **Step 1: Constants and palette.** In `vitreus.luau`, directly after the `iris_fx.cyber = { … }` table, add:

```lua
-- Paper (preset 11): dreamy e-ink. Cream paper, pure-black ink, lavender for the accent and peach for the second colour. Fixed: Iris does not colour it.
iris_fx.PAPER = 11
iris_fx.paper = { ink = "#000000", faint = "#8a857a", mint = "#9d8fd6", mintlo = "#8a7cc6", minthi = "#d9d0f5", onmint = "#000000",
                  tint = "#f4efe4", panel = "#ebe5d6", deep = "#f2b8a0", off = "#d9d3c4", alert = "#e07a7a" }
```

- [ ] **Step 2: Wire PAPER everywhere CYBER is checked.** In `vitreus.luau` make these exact edits:
  - iris.json load, both lines: `or math.floor(pr) == iris_fx.CYBER)` → `or math.floor(pr) == iris_fx.CYBER or math.floor(pr) == iris_fx.PAPER)`, and the same for `lk`.
  - `push_look`: `or iris_cfg.look == iris_fx.CYBER and 3 or 0` → unchanged (Paper sends 0, Glass, to the desktop widgets — out of scope).
  - `show()`: after `fact.cyber_on = …` add `fact.paper_on = iris_cfg.look == iris_fx.PAPER`; in the `hy_theme_changed(…)` call change `or iris_cfg.look == iris_fx.CYBER and "cyber" or "glass"` → `or iris_cfg.look == iris_fx.CYBER and "cyber" or iris_cfg.look == iris_fx.PAPER and "paper" or "glass"`.
  - start-up: after `elseif iris_cfg.preset == iris_fx.CYBER then iris_fx.apply_palette(iris_fx.cyber)` add `elseif iris_cfg.preset == iris_fx.PAPER then iris_fx.apply_palette(iris_fx.paper)`.
  - `theme_pick`: after the CYBER branch add

```lua
        elseif k == iris_fx.PAPER then
            iris_cfg.look, iris_cfg.preset, iris_cfg.enabled = k, k, true
            iris_fx.apply_palette(iris_fx.paper)
```
  - `HY_ROUND_DEFAULT`: add `paper = 22`.

- [ ] **Step 3: Facts in `vitreus.plm`.** After the Cyber block (`follow cy_k = if(cyber_on, 1, 0)`) add:

```
    //  The Paper theme: dreamy e-ink. The plastic body (`pk`) in cream with a black hairline, the liquid left on (round corners, necks, jelly), a pastel
    //  tab on each drawer, still paper grain and a dithered shadow (paper_deco.plm, paper.wgsl). `paper_k` travels between the others and Paper.
    fact paper_on = false
    prop paper_k = 0 ~calm
    follow paper_k = if(paper_on, 1, 0)
```
  Then change `follow obs = if(glass_obs or cas or uwu, 1, 0)` → `follow obs = if(glass_obs or cas or uwu or paper_on, 1, 0)` and `let pk = max(cas_k, uwu_k)` → `let pk = max(max(cas_k, uwu_k), paper_k)`. After `shader matrix = file "matrix.wgsl"` add `shader paper = file "paper.wgsl"                    // the Paper theme's grain and dithered shadow`.

- [ ] **Step 4: Paper body.** In `pages/bar_glass.plm`, directly after the UwU body (the one ending `include "bar_shapes.plm"` / `}` after `show: uwu_k > 0.004`), add:

```
        //  The Paper's cream over it: the palette's own paper colour, no lip, a black hairline at a quarter strength, no shadow (paper_deco.plm dithers one).
        body {
            color: tint
            rim: 0%
            border: 1.2 * u * paper_k, mix(tint, ink, 0.25)
            opacity: paper_k
            show: paper_k > 0.004
            include "bar_shapes.plm"
        }
```
  In `pages/overview.plm`, after its UwU body, add the same body with its own shape:

```
            //  The Paper's cream over it (see bar_glass.plm).
            body {
                color: tint
                rim: 0%
                border: 1.2 * u * paper_k, mix(tint, ink, 0.25)
                opacity: paper_k
                show: paper_k > 0.004
                box { at: ovc.x, ovc.top + 104 * ovu; size: 290 * ovu, 208 * ovu; corner: 18 * ovu * (1 - 0.73 * cy_k) }
            }
```

- [ ] **Step 5: Icon halo off.** `pages/bar_icons.plm:7`: `glow: 2.4 * u, 110%, deep` → `glow: 2.4 * u, 110% * (1 - paper_k), deep`.

- [ ] **Step 6: Stub shader so the check passes.** Create `paper.wgsl` with a transparent stub (replaced in Task 2):

```wgsl
fn shade(s: Shader) -> vec4<f32> {
    return vec4<f32>(0.0, 0.0, 0.0, 0.0);
}
```

- [ ] **Step 7: Static check.** Run `pleamar --check vitreus.plm`. Expected: ends `vitreus.plm: ok`, no new errors.

- [ ] **Step 8: Live check.** `pleamar --say vitreus quit`; wait 4 s; `pleamar --say vitreus "emit theme_pick 11"`; wait 3 s; `pleamar --say vitreus "fact panel controls"`; wait 2 s; `grim` a screenshot and look at it. Expected: cream bar and drawer, black text and icons, lavender switches, rounded corners, thin grey edge, no glow halo. `grep -iE 'error|panic' /tmp/vitreus.log` shows nothing new. Then `fact panel none`.

- [ ] **Step 9: Commit.**

```bash
git add vitreus.luau vitreus.plm pages/bar_glass.plm pages/overview.plm pages/bar_icons.plm paper.wgsl
git commit -m "paper theme: preset 11, cream palette, paper body, no icon halo"
```

---

### Task 2: E-ink texture — `paper.wgsl` and `pages/paper_deco.plm`

**Files:**
- Modify: `paper.wgsl` (replace stub)
- Create: `pages/paper_deco.plm`
- Modify: `pages/bar_glass.plm` (one `include` line before the UwU graphics comment, ~line 383)

**Interfaces:**
- Consumes: `paper_k`, `shader paper`, drawer lets `dk/dc/ds/dl/dm/dz.{ex,ew,ey,eh}`, `do.{ix,iw,ey,eh}`, visibilities `dk0 dc0 ds0 dl0 dm0 dz0 do0`, `vb`, `lf.t`, `u`, palette `ink`.
- Shader values contract: mode in `s.a.y` — 0 grain (`s.a.x` strength, `s.color` ink); 1 dithered shadow (`s.a.x` density, `s.a.z` margin round the drawer, `s.a.w` drawer corner, `s.b.x/s.b.y` offset, `s.b.z` fade distance, `s.b.w` dot opacity); 2 dither fade (top solid → bottom clear, `s.color` pastel).

- [ ] **Step 1: Write the shader.** Replace `paper.wgsl` with:

```wgsl
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
        let d = rrect(s.pos, c + vec2<f32>(s.b.x, s.b.y), h, s.a.w);
        let fall = clamp(1.0 - max(d, 0.0) / max(s.b.z, 1.0), 0.0, 1.0);
        let dens = fall * fall * s.a.x;
        let on = step(bayer4(cell), dens);
        return vec4<f32>(s.color.rgb, on * s.b.w);
    }
    let dens = 1.0 - s.uv.y;
    return vec4<f32>(s.color.rgb, step(bayer4(cell), dens));
}
```

- [ ] **Step 2: Write the decorations part.** Create `pages/paper_deco.plm`:

```
part PaperDeco {
        //  The Paper theme's look on every drawer that is out: a pastel tab across its head (an index card's colour; the edge dithered away),
        //  still paper grain over it, and a dithered e-ink shadow below and to the right in place of a soft one. The seven drawers, in order:
        //  controls, calendar, settings, launcher, player and tray, desk, volume and notifications. Their pastels are named here, once.
        let pp_lav = #d8d0f2
        let pp_peach = #f7d6c6
        let pp_mint = #cde9da
        let pp_sky = #cfe0f3
        let pp_butter = #f4e7b8
        let pp_rose = #f2cfdc
        repeat ppi in 0..7 {
            let ppo = pick(ppi, dk0, dc0, ds0, dl0, dm0, dz0, do0)
            let ppcx = pick(ppi, dk.ex, dc.ex, ds.ex, dl.ex, dm.ex, dz.ex, do.ix)
            let ppw = pick(ppi, dk.ew, dc.ew, ds.ew, dl.ew, dm.ew, dz.ew, do.iw)
            let ppt = pick(ppi, dk.ey - dk.eh / 2, dc.ey - dc.eh / 2, ds.ey - ds.eh / 2, dl.ey - dl.eh / 2, dm.ey - dm.eh / 2, dz.ey - dz.eh / 2, do.ey - do.eh / 2)
            let ppb = min(pick(ppi, dk.ey + dk.eh / 2, dc.ey + dc.eh / 2, ds.ey + ds.eh / 2, dl.ey + dl.eh / 2, dm.ey + dm.eh / 2, dz.ey + dz.eh / 2, do.ey + do.eh / 2), vb - lf.t - 1)
            let ppl = ppcx - ppw / 2
            let pph = ppb - ppt
            let ppcol = pick(ppi, pp_lav, pp_peach, pp_butter, pp_rose, pp_mint, pp_sky, pp_sky)
            let ppm = 18 * u                      // how far the shadow's box reaches past the drawer
            group {
                show: paper_k > 0.01 and ppo > 0.9
                opacity: paper_k * clamp(ppo * 3 - 2, 0, 1)
                shader paper { at: ppl - ppm, ppt - ppm; size: ppw + 2 * ppm, pph + 2 * ppm; values: 0.55, 1, ppm, 24 * u, 5 * u, 7 * u, 10 * u, 0.5; colors: ink, ink }
                group {
                    clip inset 0 box { at: ppcx, ppt + pph / 2; size: ppw, pph; corner: 24 * u }
                    box { at: ppcx, ppt + 7 * u; size: ppw, 14 * u; color: ppcol }
                    shader paper { at: ppl, ppt + 14 * u; size: ppw, 6 * u; values: 0, 2; colors: ppcol, ppcol }
                    shader paper { at: ppl, ppt; size: ppw, pph; values: 0.05, 0; colors: ink, ink }
                }
            }
        }
}
```

- [ ] **Step 3: Include it.** In `pages/bar_glass.plm`, on the line before the comment `//  The UwU theme's graphics, on every drawer that is out` add `        include "paper_deco.plm"`.

- [ ] **Step 4: Static check.** `pleamar --check vitreus.plm` → ends `vitreus.plm: ok`. If `pick` refuses colours or `clip inset` is rejected inside `repeat`, replace the `repeat` with seven written-out groups (one per drawer, the same body with that drawer's names), as Cyber's block does.

- [ ] **Step 5: Live check.** Restart (`pleamar --say vitreus quit`, wait 4 s), with Paper still picked: open `controls`, screenshot; open `settings`, screenshot; then calendar (click the clock, or `pleamar --say vitreus "fact panel calendar"` if that value exists — `grep -n 'fact panel' vitreus.plm` lists them). Expected per drawer: a pastel band across the top with a dotted fading lower edge, faint flecks on the cream, a dotted grey shadow below/right, no smooth shadow. Log clean.

- [ ] **Step 6: Commit.**

```bash
git add paper.wgsl pages/paper_deco.plm pages/bar_glass.plm
git commit -m "paper theme: pastel tabs, paper grain and dithered e-ink shadow on every drawer"
```

---

### Task 3: Fifth card on Settings > Theme

**Files:**
- Modify: `pages/theme.plm` (card region: from the line `//  Glass` through `on press theme_hit.10 { emit theme_pick(10) }`, currently lines 13–120)

**Interfaces:**
- Consumes: `theme_sel` (now 11 for Paper), event `theme_pick`.

- [ ] **Step 1: Re-lay four cards to five, by script.** Run from the repo root:

```bash
python3 - <<'EOF'
p = "pages/theme.plm"
lines = open(p).read().split("\n")
s = next(i for i, l in enumerate(lines) if l.strip() == "//  Glass")
e = next(i for i, l in enumerate(lines) if "on press theme_hit.10" in l)
region = "\n".join(lines[s:e + 1])
R = [("spx + 62 * pu", "spx + 47 * pu"), ("spx + 167 * pu", "spx + 133 * pu"), ("spx + 271 * pu", "spx + 219 * pu"),
     ("spx + 376 * pu", "spx + 305 * pu"), ("96 * pu, 76 * pu", "80 * pu, 76 * pu"), (" - 48 * pu", " - 40 * pu"),
     (" + 48 * pu", " + 40 * pu"), ("width: (80 * pu) / rs", "width: (64 * pu) / rs"),
     ("+ -34 * pu", "+ -28 * pu"), ("+ -17 * pu", "+ -14 * pu"), ("+ 17 * pu", "+ 14 * pu"), ("+ 34 * pu", "+ 28 * pu"),
     ("+ 36 * pu", "+ 28 * pu"), ("radius: 6.4 * pu", "radius: 5.4 * pu")]
# the title / subtitle sit 40 in from the card's left: now 32 (8 from an 80-wide card's edge). Done before the half-width swap.
region = region.replace(" - 40 * pu + 0.5", " - 32 * pu + 0.5")
for a, b in R:
    n = region.count(a)
    assert n > 0, a
    region = region.replace(a, b)
lines[s:e + 1] = region.split("\n")
open(p, "w").write("\n".join(lines))
print("ok")
EOF
```
  Expected: prints `ok`. Then update the page's first comment: `four looks` → `five looks`, and append ` Paper: cream paper with pastel tabs and e-ink grain.` after the Cyber sentence.

- [ ] **Step 2: Add the Paper card.** Copy the Cyber card (from its `//  Cyber` line through `on press theme_hit.10 { emit theme_pick(10) }`) and paste it right after, with these replacements in the copy only:

```bash
python3 - <<'EOF'
p = "pages/theme.plm"
t = open(p).read()
s = t.index("            //  Cyber\n")
e = t.index("on press theme_hit.10 { emit theme_pick(10) }") + len("on press theme_hit.10 { emit theme_pick(10) }")
card = t[s:e]
for a, b in [("//  Cyber", "//  Paper"), ("spx + 305 * pu", "spx + 391 * pu"), ("#05080f", "#f4efe4"), ("#0d2438", "#ebe5d6"),
             ("#ff2bd6", "#f2b8a0"), ("#00e5ff", "#9d8fd6"), ("#ff3b5c", "#cde9da"), ('text "Cyber"', 'text "Paper"'),
             ('text "Neon HUD"', 'text "Dreamy e-ink"'), ("theme_sel == 10", "theme_sel == 11"), ("theme_hit.10", "theme_hit.11"),
             ('label: "Cyber theme"', 'label: "Paper theme"'), ("theme_pick(10)", "theme_pick(11)")]:
    assert a in card, a
    card = card.replace(a, b)
t = t[:e] + "\n" + card + t[e:]
open(p, "w").write(t)
print("ok")
EOF
```

- [ ] **Step 3: Static check.** `pleamar --check vitreus.plm` → ok.

- [ ] **Step 4: Live check.** Open Settings on the Theme page: `pleamar --say vitreus "fact panel settings"`, then set the page fact (`grep -n 'set_pgp' vitreus.plm` shows how the Theme page is chosen; use `--say vitreus "fact <that fact> …"` or click Theme), screenshot. Expected: five cards in one row inside the box, Paper last, with its tick (Paper is the current theme). Then `emit theme_pick 10` and screenshot: Cyber card ticked, Cyber look intact.

- [ ] **Step 5: Commit.**

```bash
git add pages/theme.plm
git commit -m "theme page: five cards, a paper card"
```

---

### Task 4: Literata as Paper's typeface

**Files:**
- Modify: `bin/vitreus-fonts:21-28`
- Modify: `vitreus.luau` (font `DEFAULTS` ~2875, `theme()`/`label()` beside it, `saved.cyber` load ~2962, fonts.json write ~3079)
- Modify: `install.sh` (font URLs ~43–54, the Orbitron install block ~370–380, help text ~22 and ~294)

- [ ] **Step 1: `bin/vitreus-fonts`.** `"cyber" if preset == 10 else "glass"` → `"cyber" if preset == 10 else "paper" if preset == 11 else "glass"`; add `"paper": "Literata"` to the family map; add `"Literata": 1.0` to `SCALE`.

- [ ] **Step 2: `vitreus.luau` font picker.** `DEFAULTS`: add `paper = "Literata"`. `theme()`: `or iris_cfg.look == iris_fx.CYBER and "cyber" or "glass"` → `… and "cyber" or iris_cfg.look == iris_fx.PAPER and "paper" or "glass"`. `label()`: `or theme() == "cyber" and "Cyber" or "Glass"` → `… and "Cyber" or theme() == "paper" and "Paper" or "Glass"`. After the `file.cyber` line add `if type(file.paper) == "string" and file.paper ~= "" then saved.paper = file.paper end`. In the fonts.json write add `paper = saved.paper`.

- [ ] **Step 3: `install.sh`.** Beside the Orbitron URLs add

```sh
# The Paper theme's typeface, Literata (the serif Google made for e-book reading; Google Fonts, OFL).
literata_url="https://github.com/google/fonts/raw/main/ofl/literata/Literata%5Bopsz,wght%5D.ttf"
literata_licence_url="https://github.com/google/fonts/raw/main/ofl/literata/OFL.txt"
```
  and `fonts_literata="$data/fonts/Literata"` beside `fonts_orbitron`. After the Orbitron install block, add a copy of it with `orbitron→literata`, `Orbitron→Literata`, `Cyber→Paper`, file name `Literata[opsz,wght].ttf`. Mention Literata / Paper in the two help-text lines.

- [ ] **Step 4: Install the font here.** `./install.sh --dry-run 2>&1 | grep -i literata` shows the download; then fetch it the same way by hand: `mkdir -p ~/.local/share/fonts/Literata && curl -fsSL -o ~/.local/share/fonts/Literata/'Literata[opsz,wght].ttf' 'https://github.com/google/fonts/raw/main/ofl/literata/Literata%5Bopsz,wght%5D.ttf' && fc-cache -f ~/.local/share/fonts/Literata && fc-list | grep -ci literata` → non-zero. (Do NOT run the real `install.sh`: it adds autostart lines this setup does not use.)

- [ ] **Step 5: Static + live check.** `pleamar --check vitreus.plm` ok; `bash -n install.sh` ok; `python3 bin/vitreus-fonts --help 2>&1 | head -2` runs. Restart via the keeper: `pleamar --say vitreus quit`; wait 5 s; theme stays Paper; open Settings > Theme: the font row says Literata is Paper's font and offers Apply. Apply restarts the shell; screenshot shows serif text.

- [ ] **Step 6: Commit.**

```bash
git add bin/vitreus-fonts vitreus.luau install.sh
git commit -m "paper theme: literata as its typeface"
```

---

### Task 5: Regression pass

- [ ] **Step 1:** `emit theme_pick 0` (Glass), open controls, screenshot: glass as before, no pastel tab, no dots. Same for `10` (Cyber) and `9` (UwU, briefly). Log clean.
- [ ] **Step 2:** `emit theme_pick 11` to leave the user on Paper; close panels (`fact panel none`).
- [ ] **Step 3:** Update the memory file `vitreus_pleamar_shell_cyber_theme.md`: Paper = preset 11, local-only on `fx` (theme.plm card row is a rebase-conflict hotspot), files added.
