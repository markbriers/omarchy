-- Raspberry Pi defaults.
--
-- The Pi 5's VideoCore VII runs Hyprland through Mesa's V3D driver. It renders
-- a tiling desktop fine, but it shares memory bandwidth with the CPU and has
-- no headroom for the per-frame full-screen passes that animations, blur and
-- shadows cost. Leaving the stock animation set on is the difference between a
-- desktop that feels immediate and one that feels like it is catching up.
--
-- Only settings whose names and types are stable across Hyprland releases are
-- touched here. The exotic render knobs have changed type more than once, and
-- a config error on a machine that is already the slow one is not a trade
-- worth making. misc.vfr was in this file until Hyprland 0.56.1 rejected it as
-- an unknown key on a running session; variable refresh is on by default
-- anyway, so nothing was lost by dropping it.
--
-- Everything here is a default, not a lock: ~/.config/hypr/looknfeel.lua loads
-- after this file and wins, so `hl.config({ animations = { enabled = true } })`
-- there turns the animations back on.

hl.config({
  animations = {
    enabled = false,
  },

  decoration = {
    -- Blur and shadows are already off in Omarchy's defaults. They are set
    -- again here because a theme is free to turn them on, and on this GPU they
    -- are the two settings that cost the most.
    rounding = 0,

    blur = {
      enabled = false,
    },

    shadow = {
      enabled = false,
    },
  },
})
