# Paper theme — design

A fifth look for Settings > Theme: dreamy pastels on cream paper, read like an e-ink page.
Local to the `fx` branch (not upstream). Modelled on upstream's Cyber theme (8f2f42c).

## Look

- **Name / card:** "Paper", subtitle "dreamy e-ink". Theme number 11 (`iris_fx.PAPER`).
- **Material:** the opaque body Retro/UwU use (joins `pk`), with UwU's liquid kept on (round corners,
  necks, jelly). Paper does NOT join `sq` (no squared corners). No glow, no hard shadow. Hairline
  outline in ink at ~25 %.
- **Palette** (fixed; the Iris wallpaper colours are ignored while Paper is on):

  | token  | value     | role                                   |
  |--------|-----------|----------------------------------------|
  | tint   | `#f4efe4` | paper: bar and drawer bodies           |
  | panel  | `#ebe5d6` | rows / plates inside drawers           |
  | ink    | `#000000` | text and icons (pure black)            |
  | faint  | `#8a857a` | secondary text                         |
  | off    | `#d9d3c4` | off tracks, dividers                   |
  | mint   | `#9d8fd6` | accent (lavender)                      |
  | mintlo | `#8a7cc6` | accent, darker                         |
  | minthi | `#d9d0f5` | accent, lighter                        |
  | onmint | `#000000` | marks drawn on the accent              |
  | deep   | `#f2b8a0` | second colour (peach)                  |
  | alert  | `#e07a7a` | warnings                               |

- **Pastel per drawer:** a pastel band across each drawer's head (where Retro draws its stripe),
  like an index-card tab. Defined once as named lets, never inline hex:
  controls `pp_lav #d8d0f2` · calendar `pp_peach #f7d6c6` · player/tray `pp_mint #cde9da` ·
  notifications/volume `pp_sky #cfe0f3` · settings `pp_butter #f4e7b8` · launcher `pp_rose #f2cfdc`.
- **Font:** Literata is the theme's default face (applied through the font picker's Apply, like
  Orbitron for Cyber). Added to `bin/vitreus-fonts` and `install.sh`'s font list.
- **Bar:** same paper, black icons; the dark halo behind the bar's icons is off for Paper.

## E-ink effects — `paper.wgsl`

One new shader, drawn per open drawer the way Cyber draws `matrix.wgsl` in `pages/bar_glass.plm`.

- **Grain:** static fibre noise, ~3–4 % strength, no `s.time` (repaints only on damage).
- **Dithered shading:** Paper drops the drawers' smooth shadow; a shader rect offset down-right of
  each drawer draws a 4×4 Bayer-dither band of ink dots that thins with distance. The same dither
  softens the edge of the pastel tab.
- Both scale with `paper_k`. If the shader fails, the drawers stay plain cream with the hairline.

## Wiring

- `vitreus.luau`: `iris_fx.PAPER = 11`, `iris_fx.paper` palette, and PAPER added everywhere
  CYBER is checked (iris.json load, `show()`, start-up palette, `theme_pick`). `push_look` sends
  look 0 (Glass) to the desktop widgets for now; `hy_theme_changed` gets "glass" (keeps Glass's
  window corners).
- `vitreus.plm`: `fact paper_on`, `prop paper_k ~calm`, `follow paper_k`; `pk` includes `paper_k`;
  the bar-icon halo and the drawer shadow are scaled by `(1 - paper_k)`.
- `pages/paper_deco.plm` (new part): pastel tabs, hairline, the `paper` shader rects. Included
  from `pages/bar_glass.plm` next to the Cyber decorations.
- `pages/theme.plm`: the card row re-laid from four cards to five (expect rebase conflicts here
  when upstream touches this geometry).

## Out of scope

Desktop clock / system monitor / notes / cava (stay Glass for now), lock screen (hyprlock is live),
an Iris-driven pastel variant.

## Testing

No automated tests in this repo. Verify live: `pleamar --say vitreus "emit theme_pick 11"`, grim
screenshots of the bar and of controls / calendar / settings drawers opened via `--say`, check the
log for errors, then switch back to Cyber (10) and Glass (0) to confirm they're unchanged.
