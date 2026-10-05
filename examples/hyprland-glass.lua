-- Example additions to an existing Hyprland Lua configuration (the `hl` API).
-- Do not replace your complete Hyprland config with this fragment.
-- Launch the session with XDG_CURRENT_DESKTOP=Hyprland:DMS and start DMS.
if os.getenv("XDG_CURRENT_DESKTOP") == "Hyprland:DMS" then
    -- DMS generates this file from the selected wallpaper when dynamic colors are enabled.
    require("dms.colors")
    hl.config({ general = { gaps_in = 4, gaps_out = 5 } })
    hl.curve("glassWorkspaces", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 2.25, bezier = "glassWorkspaces", style = "slide" })
    hl.animation({ leaf = "workspacesIn", enabled = true, speed = 2.25, bezier = "glassWorkspaces", style = "slide" })
    hl.animation({ leaf = "workspacesOut", enabled = true, speed = 2.25, bezier = "glassWorkspaces", style = "slide" })

    -- Configure persistent workspaces for your outputs; otherwise DMS may show
    -- non-clickable padding tiles where no real workspace exists.
    -- hl.workspace_rule({ workspace = "1", monitor = "YOUR_OUTPUT", persistent = true })
    hl.bind("SUPER + R", hl.dsp.exec_cmd("dms ipc call glassShell launcherToggle"))
    hl.bind("ALT + TAB", hl.dsp.exec_cmd("dms ipc call glassShell workspaceNext"))
    hl.bind("ALT + SHIFT + TAB", hl.dsp.exec_cmd("dms ipc call glassShell workspacePrev"))
    hl.bind("ALT + ALT_L", hl.dsp.exec_cmd("dms ipc call glassShell workspaceConfirm"), { release = true })
    hl.bind("ALT + ALT_R", hl.dsp.exec_cmd("dms ipc call glassShell workspaceConfirm"), { release = true })
end
