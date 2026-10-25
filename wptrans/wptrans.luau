-- The wallpaper transition's logic. It is told what was picked (`text target`, and `ox`, `oy` for where it starts, -1 for the middle) and
-- then `go`: it makes the new picture at the screen's size (and, for skwd's, the one awww shows now), chooses a transition, shows it, has
-- awww switch to the new picture at once when it covers the screen, and takes the overlay away. While one is on, another `go` is ignored.

-- skwd-wall's (skwd.wgsl), by `kind`; 0 is the hexagon dissolve. Each `go` takes one at random, never the same one twice running.
local KINDS = {
    "crosswarp", "circle-crop", "directional", "directional-scaled", "polka-dots-curtain", "puzzle-right", "crosshatch",
    "directional-wipe", "fadecolor", "parametric-glitch", "perlin", "randomsquares", "crossfade", "pixelate", "iris", "glitch",
    "voronoi-shatter", "plasma-flow", "ink-splash", "smoke", "chromatic-bloom", "inkwell-drop", "pixelfade-wave", "soft-warp-fade",
    "zoom-blur-pull", "mosaic-tumble",
}

local busy = false
local home = ""
local counter = 0
local last_kind = -1
math.randomseed(os.time())
run("printenv", { "HYPRLAND_INSTANCE_SIGNATURE" }, function(out, code) fact.wp_dec = (code == 0 and (out or "") ~= "") and 1 or 0 end)
run("printenv", { "HOME" }, function(out) home = (out or ""):gsub("%s+$", "") end)

local function finish()
    run("awww", { "img", text.target, "--transition-type", "none" }, function()
        -- awww has to have drawn it before the overlay goes, or the old wallpaper shows for a frame
        after(350, function()
            fact.active = false
            fact.ox, fact.oy = -1, -1
            busy = false
        end)
    end)
end

local function pick_kind()
    local k
    repeat k = math.random(0, #KINDS) until k ~= last_kind
    last_kind = k
    return k
end

-- what awww would show: the picture cropped to fill the screen, at the screen's size
local function make(src, geo, file, fn)
    run("magick", { src .. "[0]", "-resize", geo .. "^", "-gravity", "center", "-extent", geo, "-quality", "92", file },
        function(_, code) fn(code == 0) end)
end

on("go", function()
    local path = text.target
    if busy or path == "" or home == "" then return end
    busy = true
    local dir = home .. "/.cache/pleamar/wptrans"
    run("awww", { "query" }, function(out)
        out = out or ""
        local geo = out:match("%d+x%d+") or "1920x1080"
        local now = out:match("currently displaying: image: ([^\n]+)")
        run("mkdir", { "-p", dir }, function()
            counter = counter + 1
            local kind = pick_kind()
            local nfile, ofile = dir .. "/new.jpg", dir .. "/old.jpg"
            local waiting, ok_new, ok_old = 2, false, false
            local function ready()
                waiting = waiting - 1
                if waiting > 0 then return end
                if not ok_new then busy = false return end
                if kind > 0 and not ok_old then kind = 0 end          -- no old picture to bend: the dissolve, which only needs the new one
                fact.kind = kind
                text.src = nfile .. "?" .. counter
                if kind > 0 then text.osrc = ofile .. "?" .. counter end
                after(150, function()           -- a moment for the pictures to be read in
                    fact.active = true
                    after(math.floor(fact.dur * 1000) + 80, finish)
                end)
            end
            make(path, geo, nfile, function(ok) ok_new = ok; ready() end)
            if kind > 0 and now then
                make(now, geo, ofile, function(ok) ok_old = ok; ready() end)
            else
                ready()
            end
        end)
    end)
end)
