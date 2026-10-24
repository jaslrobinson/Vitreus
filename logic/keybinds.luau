-- Settings > Keybinds: the shell's keybinds as the window manager has them, read from its own file and rewritten there when one is changed.
--   Hyprland: hypr_vitreus.lua  (`hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("... pleamar --say vitreus \"emit dash_toggle\""))`)
--   pleamar-wm: keys.conf       (`bind Super+d launch pleamar --say vitreus "emit desk_toggle"`)
-- Only the binds that talk to the shell (`pleamar --say ...`) are listed, and the one that opens Files (`vitreus-files`). A bind is changed in place (its `unbind` line too), and Hyprland is
-- reloaded; pleamar-wm reads its keys when it starts. The scene shows the rows (`kb_rows`), the chips for the modifiers and a box that
-- records the next key (`kb_press`, the codes of pages/keybinds_keys.plm: modifiers * 100 + the key's place in KEYS).
return function()
    local KEYS = {}
    for k in ("a b c d e f g h i j k l m n o p q r s t u v w x y z F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 space Return Tab Print BackSpace Delete Insert Home End Prior Next Left Right Up Down comma period slash semicolon apostrophe bracketleft bracketright backslash minus equal grave"):gmatch("%S+") do
        KEYS[#KEYS + 1] = k
    end
    local KEYIDX = {}
    for i, k in ipairs(KEYS) do KEYIDX[k:lower()] = i end
    local DISP = { space = "Space", Return = "Enter", Tab = "Tab", Print = "Print", BackSpace = "Backspace", Delete = "Delete", Insert = "Insert",
        Home = "Home", End = "End", Prior = "PgUp", Next = "PgDn", Left = "←", Right = "→", Up = "↑", Down = "↓", comma = ",", period = ".",
        slash = "/", semicolon = ";", apostrophe = "'", bracketleft = "[", bracketright = "]", backslash = "\\", minus = "-", equal = "=", grave = "`" }
    local RAWDISP = { ["mouse:272"] = "Mouse L", ["mouse:273"] = "Mouse R", ["mouse:274"] = "Mouse M", Caps_Lock = "Caps",
        XF86AudioRaiseVolume = "Vol +", XF86AudioLowerVolume = "Vol −", XF86AudioMute = "Mute", XF86AudioMicMute = "Mic mute",
        XF86AudioPlay = "Play", XF86AudioPause = "Pause", XF86AudioNext = "Next", XF86AudioPrev = "Prev",
        XF86MonBrightnessUp = "Bright +", XF86MonBrightnessDown = "Bright −", XF86PowerOff = "Power" }
    local function disp_key(k)
        if #k == 1 then return k:upper() end
        return DISP[k] or RAWDISP[k] or (k:gsub("^XF86", ""))
    end
    local MODS = { { 1, "Super" }, { 4, "Ctrl" }, { 8, "Alt" }, { 2, "Shift" } }   -- the order a combo is written in
    local MODBIT = { super = 1, mod = 1, mod4 = 1, win = 1, shift = 2, ctrl = 4, control = 4, alt = 8, mod1 = 8 }

    -- What each bind does, by what it says to the shell. Binds that are not here are left out.
    local ACTS = {
        ["vitreus emit launch_toggle"] = "Launcher",
        ["vitreus emit settings_toggle"] = "Settings",
        ["lockscreen fact locked true"] = "Lock screen",
        ["vitreus emit wp_picker_toggle"] = "Wallpaper picker",
        ["vitreus emit desk_toggle"] = "Desk",
        ["vitreus emit dash_toggle"] = "Dashboard",
        ["vitreus emit ov_toggle"] = "Workspace overview",
        ["vitreus emit shot 0"] = "Screenshot: region",
        ["vitreus emit shot 1"] = "Screenshot: whole screen",
        ["vitreus emit rec_toggle"] = "Record the screen",
        ["launch vitreus-files"] = "Files",
        ["vitreus-files"] = "Files",
    }
    -- The combos this shell ships with, per window manager, as (modifier bits, key); a second one is for an action that has two.
    local DEFAULTS = {
        hypr = {
            ["vitreus-files"] = { { 1, "e" } },
            ["vitreus emit launch_toggle"] = { { 1, "space" } }, ["vitreus emit settings_toggle"] = { { 3, "space" } },
            ["lockscreen fact locked true"] = { { 1, "l" } }, ["vitreus emit wp_picker_toggle"] = { { 1, "b" } },
            ["vitreus emit desk_toggle"] = { { 1, "d" } }, ["vitreus emit dash_toggle"] = { { 3, "d" } }, ["vitreus emit ov_toggle"] = { { 1, "Tab" } },
            ["vitreus emit shot 0"] = { { 0, "Print" }, { 1, "c" } }, ["vitreus emit shot 1"] = { { 2, "Print" } }, ["vitreus emit rec_toggle"] = { { 3, "c" } },
        },
        niri = {
            ["vitreus-files"] = { { 1, "e" } },
            ["vitreus emit launch_toggle"] = { { 1, "space" } }, ["vitreus emit settings_toggle"] = { { 3, "space" } },
            ["lockscreen fact locked true"] = { { 1, "l" } }, ["vitreus emit wp_picker_toggle"] = { { 1, "b" } },
            ["vitreus emit desk_toggle"] = { { 1, "d" } }, ["vitreus emit dash_toggle"] = { { 3, "d" } }, ["vitreus emit ov_toggle"] = { { 1, "Tab" } },
            ["vitreus emit shot 0"] = { { 0, "Print" }, { 1, "c" } }, ["vitreus emit shot 1"] = { { 2, "Print" } }, ["vitreus emit rec_toggle"] = { { 3, "c" } },
        },
        pwm = {
            ["vitreus emit launch_toggle"] = { { 1, "space" } }, ["vitreus emit settings_toggle"] = { { 3, "space" } },
            ["lockscreen fact locked true"] = { { 1, "l" } }, ["vitreus emit wp_picker_toggle"] = { { 1, "b" } },
            ["vitreus emit desk_toggle"] = { { 1, "d" } }, ["vitreus emit dash_toggle"] = { { 3, "d" } }, ["vitreus emit shot 0"] = { { 0, "Print" }, { 1, "c" } },
            ["vitreus emit shot 1"] = { { 2, "Print" } }, ["vitreus emit rec_toggle"] = { { 3, "c" } },
            ["launch vitreus-files"] = { { 1, "e" } },
        },
    }

    -- What a bind taken out here starts with: the line stays in the file, commented, so it can be put back.
    local REMOVED = { hypr = "-- removed in Settings: ", pwm = "#removed# ", niri = "// removed in Settings: " }

    local K = { rows = {}, sel = 0, mask = 0, key = "" }     -- sel: 1-based, 0 = none

    local function wm() return fact.wm_niri == true and "niri" or (fact.wm_hypr == true and "hypr" or "pwm") end
    local function home() return K.home or "" end
    local function path()
        if wm() == "hypr" then return home() .. "/.config/hypr/hypr_vitreus.lua" end
        if wm() == "niri" then return home() .. "/.config/niri/niri_vitreus.kdl" end
        return home() .. "/.config/pleamar/keys.conf"
    end

    -- A combo as the file writes it, to (modifier bits, key); nil when it does not make sense.
    local function parse_combo(s, loose)
        local parts = {}
        for p in (s or ""):gmatch("[^%+%s]+") do parts[#parts + 1] = p end
        if #parts == 0 then return nil end
        local mask = 0
        for i = 1, #parts - 1 do
            local b = MODBIT[parts[i]:lower()]
            if not b then return nil end
            mask = bit32.bor(mask, b)
        end
        local key = parts[#parts]
        local idx = KEYIDX[key:lower()]
        if not idx then
            if loose then return mask, key end
            return nil
        end
        return mask, KEYS[idx]
    end
    -- And back: Hyprland writes `SUPER + SHIFT + D`, pleamar-wm `Super+Shift+d`.
    local function write_combo(mask, key)
        local names = {}
        for _, m in ipairs(MODS) do
            if bit32.band(mask, m[1]) ~= 0 then names[#names + 1] = wm() == "hypr" and m[2]:upper() or (wm() == "niri" and m[2] == "Super" and "Mod" or m[2]) end
        end
        local k = key
        if wm() == "hypr" or wm() == "niri" then
            if #key == 1 then k = key:upper() elseif key == "space" then k = "Space" end    -- as the file has always written them
        end
        names[#names + 1] = k
        return table.concat(names, wm() == "hypr" and " + " or "+")
    end

    -- The words on the key caps: modifiers, then the key; each with its width (in the page's own units, which are 1.69 times the text's pixels: a
    -- cap is 11 of padding and about 4.4 per letter) and how far its middle is from the right end of the row.
    local function caps(mask, key)
        local parts = {}
        for _, m in ipairs(MODS) do if bit32.band(mask, m[1]) ~= 0 then parts[#parts + 1] = m[2] end end
        parts[#parts + 1] = disp_key(key)
        local w = {}
        for i, p in ipairs(parts) do w[i] = math.max(15, 11 + #p * 4.4) end
        local right, off = 0, {}
        for i = #parts, 1, -1 do
            off[i] = right + w[i] / 2
            right = right + w[i] + 5
        end
        return parts, w, off
    end

    local WIN = 12                    -- rows the page has (pages/keybinds.plm `repeat i in 0..12`); the wheel moves the window (`kb_scroll`)
    K.off = 0
    local function show()
        local model_rows = {}
        K.off = math.max(0, math.min(K.off, #K.rows - WIN))
        if wm() == "hypr" then
            local n = #K.rows
            text.kb_where = n > WIN and string.format("%d–%d of %d%s", K.off + 1, math.min(K.off + WIN, n), n, K.off + WIN < n and "  ·  scroll for more" or "")
                or string.format("%d binds  ·  hyprland.lua, hypr_vitreus.lua", n)
        end
        for i = 1, math.min(WIN, #K.rows - K.off) do
            local r = K.rows[K.off + i]
            local parts, w, off = caps(r.mask, r.key)
            local row = { name = r.name, chg = r.changed }
            local names = { "a", "b", "c", "d" }
            for j = 1, 4 do
                row[names[j]] = parts[j] or ""
                row["w" .. names[j]] = parts[j] and w[j] or 0
                row["r" .. names[j]] = parts[j] and off[j] or 0
            end
            model_rows[i] = row
        end
        model.kb_rows = model_rows
        fact.kb_ok = #K.rows > 0
    end

    local function dirty()
        local r = K.rows[K.sel]
        fact.kb_dirty = r ~= nil and K.key ~= "" and (K.mask ~= r.mask or K.key ~= r.key)
    end
    local function pick_text()
        text.kb_key = K.key ~= "" and disp_key(K.key) or ""
        fact.kb_has = K.key ~= ""
    end

    -- ── Hyprland: every bind, from both files ─────────────────────────────────────────────────────────────────────────
    -- hyprland.lua is read first, hypr_vitreus.lua (loaded after it, and unbinding first) second: a combo in both is live from the
    -- second, so the first one's row is dropped. Each row keeps its file, its line and the first argument as written, so a change
    -- rewrites only that, on that line. A row is named by the comment at the end of its line, else by what it runs.
    local HFILES = { "hyprland.lua", "hypr_vitreus.lua" }
    local function hfile(f) return home() .. "/.config/hypr/" .. f end
    local DIRW = { l = "left", r = "right", u = "up", d = "down" }
    local CMDNAMES = {
        { "rofi_show%.sh drun", "App launcher (rofi)" }, { "rofi_show%.sh window", "Window switcher (rofi)" }, { "rofi_clipboard", "Clipboard (rofi)" },
        { "swaync%-client %-t", "Notifications" }, { "playerctl play%-pause", "Play / pause" },
        { "output%-volume raise", "Volume up" }, { "output%-volume lower", "Volume down" }, { "output%-volume mute", "Mute" },
        { "input%-volume mute", "Mic mute" }, { "brightness raise", "Brightness up" }, { "brightness lower", "Brightness down" },
        { "%-%-caps%-lock", "Caps Lock indicator" }, { "screenshot%.sh %-%-full %-%-edit", "Screenshot: screen, then edit" },
        { "screenshot%.sh %-%-full", "Screenshot: screen" }, { "screenshot%.sh %-%-edit", "Screenshot: region, then edit" },
        { "screenshot%.sh", "Screenshot: region" }, { "smart_lock%.sh", "Lock screen" }, { "captive%-portal", "Wi-Fi login page" },
        { "exec_cmd%(terminal%)", "Terminal" }, { "firefox", "Firefox" },
    }
    local function title(w) return (w:gsub("^%l", string.upper)) end
    local function hname(rest)
        local c = rest:match("%)%s*%-%-%s*(.-)%s*$")
        if c and c ~= "" then return title(c) end
        local scene, cmd = rest:match('pleamar %-%-say (%S+) \\"(.-)\\"')
        if scene and ACTS[scene .. " " .. cmd] then return ACTS[scene .. " " .. cmd] end
        if rest:match("vitreus%-files") then return "Files" end
        local v = rest:match("vitreus_open%.sh panel (%w+)")
        if v then return "Vitreus: " .. title(v) end
        v = rest:match("vitreus_open%.sh settings pg_(%w+)")
        if v then return "Settings: " .. (({ keys = "Keybinds", disp = "Display", theme = "Theme" })[v] or v) end
        v = rest:match('vitreus_open%.sh addon \\"(.-)\\"')
        if v then return v end
        v = rest:match("dsp%.focus%(%{%s*workspace%s*=%s*(%d+)")
        if v then return "Go to workspace " .. v end
        v = rest:match("window%.move%(%{%s*workspace%s*=%s*(%d+)")
        if v then return "Move window to workspace " .. v end
        v = rest:match('dsp%.focus%(%{%s*direction%s*=%s*"(%a+)"')
        if v then return "Focus " .. (DIRW[v] or v) end
        v = rest:match('window%.move%(%{%s*direction%s*=%s*"(%a+)"')
        if v then return "Move window " .. (DIRW[v] or v) end
        local x, y = rest:match("window%.resize%(%{%s*x%s*=%s*(%-?%d+),%s*y%s*=%s*(%-?%d+)")
        if x then
            x, y = tonumber(x), tonumber(y)
            return "Resize window: " .. (x < 0 and "narrower" or x > 0 and "wider" or y < 0 and "shorter" or "taller")
        end
        if rest:match("window%.resize%(%)") then return "Resize window (drag)" end
        if rest:match("window%.drag%(%)") then return "Move window (drag)" end
        if rest:match("window%.close%(") then return "Close window" end
        if rest:match("window%.float%(") then return "Float / tile window" end
        for _, m in ipairs(CMDNAMES) do if rest:match(m[1]) then return m[2] end end
        local ex = rest:match('exec_cmd%("(.-)"%)')
        if ex then
            ex = ex:gsub('PATH=\\"[^"]-\\"%s*', ""):gsub("^bash%s+", ""):gsub("%S*/", "")
            return ex
        end
        if rest:match("function%(") then return "Lua action" end
        return "Bind"
    end
    local function hbalanced(line)
        local _, o = line:gsub("%(", "")
        local _, c = line:gsub("%)", "")
        return o == c
    end
    local function read_hypr(fn)
        local rows, at = {}, {}
        local function parse(fi, out)
            local n = 0
            for line in ((out or "") .. "\n"):gmatch("([^\n]*)\n") do
                n = n + 1
                local src, rest = line:match("^%s*hl%.bind%(([^,]-),(.*)$")
                if src then
                    local combo
                    local inner = src:match('^%s*mainMod%s*%.%.%s*"(.*)"%s*$')
                    if inner then combo = "SUPER" .. inner else combo = src:match('^%s*"(.*)"%s*$') end
                    local mask, key = parse_combo(combo, true)
                    if mask then
                        local id = mask .. " " .. key:lower()
                        if at[id] then rows[at[id]] = false end           -- the later file wins
                        local act
                        local scene, cmd = rest:match('pleamar %-%-say (%S+) \\"(.-)\\"')
                        if scene then act = scene .. " " .. cmd elseif rest:match("vitreus%-files") then act = "vitreus-files" end
                        local d = (fi == 2 and act and DEFAULTS.hypr[act]) and DEFAULTS.hypr[act][1] or nil
                        rows[#rows + 1] = { order = #rows + 1, act = act, name = hname(rest), mask = mask, key = KEYIDX[key:lower()] and KEYS[KEYIDX[key:lower()]] or key,
                            raw = key, src = src, combo = combo, file = HFILES[fi], line = n, one = hbalanced(line), def = d,
                            changed = d ~= nil and (d[1] ~= mask or d[2] ~= (KEYIDX[key:lower()] and KEYS[KEYIDX[key:lower()]] or key)) }
                        at[id] = #rows
                    end
                end
            end
        end
        -- one after the other: two reads at once could come back in either order
        run("cat", { hfile(HFILES[1]) }, function(out1)
            parse(1, out1)
            run("cat", { hfile(HFILES[2]) }, function(out2)
                parse(2, out2)
                local live = {}
                for _, r in ipairs(rows) do if r then live[#live + 1] = r end end
                K.rows = live
                show()
                if fn then fn() end
            end)
        end)
    end

    local function read(fn)
        if wm() == "hypr" then read_hypr(fn) return end
        run("cat", { path() }, function(out, code)
            local rows = {}
            local seen = {}
            if code == 0 then
                for line in (out or ""):gmatch("[^\n]+") do
                    local combo, scene, cmd
                    if wm() == "niri" then
                        combo, scene, cmd = line:match("^%s*(%S+)%s*{%s*spawn%-sh%s+\"pleamar %-%-say (%S+) '(.-)'\"")
                        if not combo then combo, scene = line:match('^%s*(%S+)%s*{%s*spawn%s+"(vitreus%-files)"') end
                    elseif wm() == "hypr" then
                        combo, scene, cmd = line:match('^hl%.bind%("([^"]+)",.-pleamar %-%-say (%S+) \\"(.-)\\"')
                        if not combo then combo, scene, cmd = line:match('^hl%.bind%("([^"]+)", hl%.dsp%.exec_cmd%(".-(vitreus%-files)"%)') end
                    else
                        combo, scene, cmd = line:match('^bind%s+(%S+)%s+.-pleamar %-%-say (%S+) "(.-)"')
                        if not combo then combo, scene, cmd = line:match('^bind%s+(%S+)%s+(launch)%s+(vitreus%-files)%s*$') end
                    end
                    if combo then
                        local act = cmd and (scene .. " " .. cmd) or scene     -- Hyprland's Files bind has no scene
                        local name = ACTS[act]
                        local mask, key = parse_combo(combo)
                        if name and mask then
                            seen[act] = (seen[act] or 0) + 1
                            local d = (DEFAULTS[wm()][act] or {})[seen[act]]
                            rows[#rows + 1] = { order = #rows + 1, act = act, name = name, mask = mask, key = key, text = combo, def = d,
                                changed = d ~= nil and (d[1] ~= mask or d[2] ~= key) }
                        end
                    end
                end
            end
            table.sort(rows, function(a, b)          -- alphabetical; two binds of one action keep the order they have in the file
                if a.name ~= b.name then return a.name:lower() < b.name:lower() end
                return a.order < b.order
            end)
            K.rows = rows
            show()
            if fn then fn() end
        end)
    end

    local function refresh()
        if K.home then read() return end
        run("printenv", { "HOME" }, function(out)
            K.home = (out or ""):gsub("%s+$", "")
            read()
        end)
    end

    on("kb_refresh", function()
        K.sel = 0
        fact.kb_sel = -1
        fact.kb_cap = false
        fact.kb_dirty = false
        text.kb_msg = ""
        text.kb_where = wm() == "hypr" and "Hyprland" or (wm() == "niri" and "niri  ·  niri_vitreus.kdl" or "Pleamar-WM  ·  keys.conf")
        K.off = 0
        refresh()
    end)

    on("kb_select", function(i)
        local w = (tonumber(i) or 0)
        i = w + 1 + K.off
        local r = K.rows[i]
        if not r then return end
        K.sel, K.mask, K.key = i, r.mask, r.key
        fact.kb_sel = w
        fact.kb_cap = false
        fact.kb_mod = r.mask
        text.kb_name = r.name
        text.kb_msg = ""
        pick_text()
        dirty()
    end)

    on("kb_mod_toggle", function(bit)
        bit = tonumber(bit) or 0
        if K.sel == 0 or bit == 0 then return end
        K.mask = bit32.bxor(K.mask, bit)
        fact.kb_mod = K.mask
        text.kb_msg = ""
        dirty()
    end)

    -- A key was pressed while recording: its place in KEYS and the modifiers that were down with it.
    on("kb_press", function(code)
        code = tonumber(code) or 0
        local key = KEYS[code % 100 + 1]
        if not key or K.sel == 0 then return end
        K.mask, K.key = math.floor(code / 100), key
        fact.kb_mod = K.mask
        fact.kb_cap = false
        text.kb_msg = ""
        pick_text()
        dirty()
    end)

    on("kb_cancel", function()
        K.sel = 0
        fact.kb_sel = -1
        fact.kb_cap = false
        fact.kb_dirty = false
        text.kb_msg = ""
    end)

    -- Writes combo `mask`, `key` in place of what row `r` has, in the file; then reloads the window manager and reads the file again.
    -- Hyprland: a change to one line of hyprland.lua or hypr_vitreus.lua. The file is copied first; after the reload, if Hyprland
    -- reports a config error, the copy is put back and Hyprland reloaded again, so a bad write never leaves the desktop without its keys.
    -- The line is read again before it is written: if it no longer holds what was listed, the list is read again instead.
    local function hypr_write(r, script, msg_ok)
        local f = hfile(r.file)
        local bak = f .. ".vitreus-kb.bak"
        local function finish(msg)
            read(function()
                K.sel = 0
                fact.kb_sel = -1
                fact.kb_dirty = false
                text.kb_msg = msg
            end)
        end
        run("sed", { "-n", r.line .. "p", f }, function(cur)
            local src = (cur or ""):match("^%s*hl%.bind%(([^,]-),")
            if src ~= r.src then finish("The file changed: the list is read again") return end
            run("cp", { "-f", f, bak }, function(_, c0)
                if c0 ~= 0 then text.kb_msg = "Could not back up " .. r.file return end
                run("sed", { "-i", "--follow-symlinks", "-e", script, f }, function(_, c1)
                    if c1 ~= 0 then text.kb_msg = "Could not write " .. r.file return end
                    run("hyprctl", { "reload" }, function()
                        run("hyprctl", { "configerrors" }, function(errs)
                            if (errs or ""):match("%S") then
                                run("cp", { "-f", bak, f }, function()
                                    run("hyprctl", { "reload" }, function() finish("Hyprland did not take it: the file is as it was") end)
                                end)
                            else
                                finish(msg_ok)
                            end
                        end)
                    end)
                end)
            end)
        end)
    end

    local function apply_hypr(r, mask, key)
        if key == r.key then key = r.raw end                  -- the key as the file spells it (`left`, `Print`, `1`)
        local combo = write_combo(mask, key)
        if not combo:match("^[%w_ %+:]+$") then text.kb_msg = "That key cannot be written to the file" return end
        for _, o in ipairs(K.rows) do
            if o ~= r and o.mask == mask and o.key:lower() == tostring(key):lower() then text.kb_msg = "Already used by " .. o.name return end
        end
        -- as it was written: `mainMod .. " + …"` stays that way while Super is in it
        local new
        if r.src:match("^%s*mainMod") and bit32.band(mask, 1) ~= 0 then
            new = 'mainMod .. "' .. combo:gsub("^SUPER", "") .. '"'
        else
            new = '"' .. combo .. '"'
        end
        local script = r.line .. 's|^\\([[:space:]]*hl\\.bind(\\)[^,]*,|\\1' .. new .. ',|'
        if r.file == "hypr_vitreus.lua" then           -- its `hl.unbind` of the old combo goes with it
            script = script .. '\n' .. 's|^hl\\.unbind("' .. r.combo .. '")$|hl.unbind("' .. combo .. '")|'
        end
        hypr_write(r, script, "Saved. Hyprland has the new key.")
    end

    local function apply(r, mask, key)
        if wm() == "hypr" then apply_hypr(r, mask, key) return end
        local old, new = r.text, write_combo(mask, key)
        if not new:match("^[%w_ %+]+$") or not old:match("^[%w_ %+]+$") then text.kb_msg = "That key cannot be written to the file" return end
        for i, o in ipairs(K.rows) do
            if o ~= r and o.mask == mask and o.key == key then text.kb_msg = "Already used by " .. o.name return end
        end
        local script
        if wm() == "hypr" then
            script = 's|"' .. old .. '"|"' .. new .. '"|g'
        elseif wm() == "niri" then
            script = 's|^\\([[:space:]]*\\)' .. old .. '\\([[:space:]]*{\\)|\\1' .. new .. '\\2|'
        else
            script = 's|^\\(unbind[[:space:]]\\{1,\\}\\)' .. old .. '[[:space:]]*$|\\1' .. new .. '|; ' ..
                     's|^\\(bind[[:space:]]\\{1,\\}\\)' .. old .. '\\([[:space:]]\\)|\\1' .. new .. '\\2|'
        end
        run("sed", { "-i", "--follow-symlinks", script, path() }, function(_, code)
            if code ~= 0 then text.kb_msg = "Could not write " .. path() return end
            local function done()
                read(function()
                    K.sel = 0
                    fact.kb_sel = -1
                    fact.kb_dirty = false
                    text.kb_msg = wm() == "hypr" and "Saved. Hyprland has the new key." or (wm() == "niri" and "Saved. niri has the new key." or "Saved. Pleamar-WM uses it from its next start.")
                end)
            end
            if wm() == "hypr" then run("hyprctl", { "reload" }, function() done() end) else done() end     -- (niri reloads a file it includes by itself)
        end)
    end

    on("kb_save", function()
        local r = K.rows[K.sel]
        if not r or K.key == "" then return end
        apply(r, K.mask, K.key)
    end)

    -- Takes the selected bind out of the file: its line is kept as a comment (Reset to defaults puts it back). Under pleamar-wm an `unbind` follows,
    -- so the key does nothing at all and not what `defaults` gives it.
    on("kb_delete", function()
        local r = K.rows[K.sel]
        if not r then return end
        if wm() == "hypr" then
            if not r.one then text.kb_msg = "This bind runs over several lines: take it out in " .. r.file return end
            hypr_write(r, r.line .. "s|^|" .. REMOVED.hypr .. "|", "Removed “" .. r.name .. "”: its line is kept, commented, in " .. r.file)
            return
        end
        local old = r.text
        if not old:match("^[%w_ %+]+$") then text.kb_msg = "That key cannot be written to the file" return end
        local script
        if wm() == "hypr" then
            script = 's|^\\(hl\\.bind("' .. old .. '",\\)|' .. REMOVED.hypr .. '\\1|'
        elseif wm() == "niri" then
            script = 's|^\\([[:space:]]*' .. old .. '[[:space:]]*{.*\\)$|' .. REMOVED.niri .. '\\1|'
        else
            script = 's|^\\(bind[[:space:]]\\{1,\\}' .. old .. '[[:space:]].*\\)$|' .. REMOVED.pwm .. '\\1\\nunbind ' .. old .. '|'
        end
        run("sed", { "-i", "--follow-symlinks", script, path() }, function(_, code)
            if code ~= 0 then text.kb_msg = "Could not write " .. path() return end
            local function done()
                read(function()
                    K.sel = 0
                    fact.kb_sel = -1
                    fact.kb_dirty = false
                    text.kb_msg = "Removed “" .. r.name .. "”. Reset to defaults puts it back."
                end)
            end
            if wm() == "hypr" then run("hyprctl", { "reload" }, function() done() end) else done() end
        end)
    end)

    -- Reset to defaults: every bind of this shell's goes back to the key it ships with, whether it was changed, taken out here or edited by hand.
    -- Its lines are dropped (and the ones Delete left as comments) and one block of the stock ones is written at the end of the file. Pressed
    -- twice (the first press only arms it): it overwrites the keys that were changed.
    local BLOCK = { hypr = { "-- >>> vitreus defaults (Settings > Keybinds)", "-- <<< vitreus defaults" },
                    pwm = { "# >>> vitreus defaults (Settings > Keybinds)", "# <<< vitreus defaults" },
                    niri = { "// >>> vitreus defaults (Settings > Keybinds)", "// <<< vitreus defaults" } }
    local function default_lines(w)
        local out = { BLOCK[w][1] }
        local acts = {}
        for act in pairs(DEFAULTS[w]) do acts[#acts + 1] = act end
        table.sort(acts)
        for _, act in ipairs(acts) do
            local scene, cmd = act:match("^(%S+) (.+)$")
            for _, d in ipairs(DEFAULTS[w][act]) do
                local combo = write_combo(d[1], d[2])
                if w == "niri" then
                    out[#out + 1] = (act == "vitreus-files") and ("    " .. combo .. ' { spawn "vitreus-files"; }')
                        or ("    " .. combo .. " { spawn-sh \"pleamar --say " .. scene .. " '" .. cmd .. "'\"; }")
                elseif w == "hypr" then
                    local run_it = (act == "vitreus-files") and 'PATH=\\"$HOME/.local/bin:$PATH\\" vitreus-files'
                        or ('PATH=\\"$HOME/.local/bin:$PATH\\" pleamar --say ' .. scene .. ' \\"' .. cmd .. '\\"')
                    out[#out + 1] = 'hl.unbind("' .. combo .. '")'
                    out[#out + 1] = 'hl.bind("' .. combo .. '", hl.dsp.exec_cmd("' .. run_it .. '"))'
                else
                    local run_it = (act == "launch vitreus-files") and "launch vitreus-files"
                        or ('launch pleamar --say ' .. scene .. ' "' .. cmd .. '"')
                    out[#out + 1] = "unbind " .. combo
                    out[#out + 1] = "bind " .. combo .. " " .. run_it
                end
            end
        end
        out[#out + 1] = BLOCK[w][2]
        if w == "niri" then out[#out + 1] = "}" end          -- (niri has one `binds` per file: the block goes inside it, before its closing brace)
        return out
    end
    on("kb_defaults", function()
        if wm() == "hypr" then text.kb_msg = "Every bind is listed here: change them one by one" return end
        if not fact.kb_arm then
            fact.kb_arm = true
            after(4000, function() fact.kb_arm = false end)
            return
        end
        fact.kb_arm = false
        local w = wm()
        local cmds = {}
        for act in pairs(ACTS) do
            local cmd = act:match("^%S+ (emit .+)$") or act:match("^%S+ (fact .+)$")
            if cmd then cmds[#cmds + 1] = cmd end
        end
        table.sort(cmds)
        local alt = table.concat(cmds, "|")
        local drop, script2 = {}, {}
        if w == "niri" then
            drop = { "-e", "/^[[:space:]]*[^[:space:]]+[[:space:]]*\\{[[:space:]]*(spawn-sh[[:space:]]+\"pleamar --say (vitreus|lockscreen) '(" .. alt .. ")'\"|spawn[[:space:]]+\"vitreus-files\")/d",
                     "-e", "/^\\/\\/ removed in Settings: /d",
                     "-e", "/^\\/\\/ >>> vitreus defaults/,/^\\/\\/ <<< vitreus defaults/d",
                     "-e", "${/^}[[:space:]]*$/d}" }
        elseif w == "hypr" then
            drop = { "-e", '/^hl\\.bind\\(.*(--say (vitreus|lockscreen) \\\\"(' .. alt .. ')\\\\"|vitreus-files)/d',
                     "-e", "/^-- removed in Settings: /d",
                     "-e", "/^-- >>> vitreus defaults/,/^-- <<< vitreus defaults/d" }
        else
            drop = { "-e", '/^bind[[:space:]].*(pleamar --say (vitreus|lockscreen) "(' .. alt .. ')"|launch vitreus-files)[[:space:]]*$/d',
                     "-e", "/^#removed# /{N;d}",
                     "-e", "/^# >>> vitreus defaults/,/^# <<< vitreus defaults/d" }
        end
        local args = { "-i", "-E", "--follow-symlinks" }
        for _, a in ipairs(drop) do args[#args + 1] = a end
        args[#args + 1] = path()
        run("sed", args, function(_, code)
            if code ~= 0 then text.kb_msg = "Could not write " .. path() return end
            -- (a second pass: `$a` never fires when the last line is one of those just deleted)
            local add = { "-i", "--follow-symlinks" }
            for _, line in ipairs(default_lines(w)) do
                add[#add + 1] = "-e"
                add[#add + 1] = "$a\\" .. line:gsub("\\", "\\\\")
            end
            add[#add + 1] = path()
            run("sed", add, function(_, code2)
                if code2 ~= 0 then text.kb_msg = "Could not write " .. path() return end
                local function done()
                    read(function()
                        K.sel = 0
                        fact.kb_sel = -1
                        fact.kb_dirty = false
                        text.kb_msg = (w == "hypr" or w == "niri") and "Back to the default keys." or "Back to the default keys. Pleamar-WM uses them from its next start."
                    end)
                end
                if w == "hypr" then run("hyprctl", { "reload" }, function() done() end) else done() end
            end)
        end)
    end)

    on("kb_scroll", function(n)
        if K.sel ~= 0 then return end                         -- not while a row is being changed: its editor is open below
        local before = K.off
        K.off = K.off + math.floor((tonumber(n) or 0) * 3 + 0.5)
        show()
        if K.off ~= before then text.kb_msg = "" end
    end)

    on("kb_reset", function()
        local r = K.rows[K.sel]
        if not r or not r.def then text.kb_msg = "No stock key for this one" return end
        apply(r, r.def[1], r.def[2])
    end)
end
