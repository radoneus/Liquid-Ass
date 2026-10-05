import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root
    property string mode: "closed"
    property string targetScreenName: ""
    property bool migrating: false
    readonly property var targetScreen: Quickshell.screens.find(s => s.name === targetScreenName) ?? null
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    property string pendingSettingsSection: ""
    function openPluginSettings(section) {
        closeOverlay();
        pendingSettingsSection = section;
        pluginService.setGlobalVar("glassShell", "settingsSection", section);
        PopoutService.openSettingsWithTab("plugins");
        Qt.callLater(finishSettingsLink);
    }
    function finishSettingsLink() {
        if (!pendingSettingsSection || !PopoutService.settingsModal?.visible) return;
        const modal = PopoutService.settingsModal;
        if (typeof modal.openPluginSettings === "function") {
            modal.openPluginSettings("glassShell");
        } else {
            console.warn("glassShell: Відкрийте DMS Glass у списку плагінів");
        }
        pendingSettingsSection = "";
    }
    Connections {
        target: PopoutService
        function onSettingsModalChanged() { Qt.callLater(root.finishSettingsLink); }
    }
    Connections {
        target: PopoutService.settingsModal
        ignoreUnknownSignals: true
        function onVisibleChanged() { Qt.callLater(root.finishSettingsLink); }
    }
    FileView {
        id: skwdConfig
        path: (Quickshell.env("HOME") || "") + "/.config/skwd/data/config.json"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: skwdApps
        path: (Quickshell.env("HOME") || "") + "/.config/skwd/data/apps.json"
        blockLoading: true
        printErrors: false
    }

    function migrate() {
        if (!pluginService || !pluginId || migrating) return;
        const version = pluginService.loadPluginData(pluginId, "migrationVersion", 0);
        if (version >= 13) return;
        migrating = true;
        try {
            if (version === 0) {
                const source = JSON.parse(skwdConfig.text());
                const apps = JSON.parse(skwdApps.text());
                if (!source.components?.appLauncher || !source.switcher || !apps)
                    throw new Error("Неповний конфіг Skwd");
                const entries = {
                    launcher: source.components.appLauncher,
                    switcher: source.switcher,
                    appOverrides: apps,
                    uiScale: source.uiScale,
                    terminal: source.terminal,
                    paths: source.paths
                };
                for (const key in entries) {
                    if (pluginService.loadPluginData(pluginId, key, null) === null && !pluginService.savePluginData(pluginId, key, entries[key]))
                        throw new Error("Не вдалося зберегти " + key);
                }
                if (pluginService.loadPluginData(pluginId, "wallpaperSelector", null) === null) {
                    const directory = pluginService.loadPluginData("wallpaperCarousel", "wallpaperDirectory", "") || "";
                    const launcher = source.components.appLauncher;
                    const switcher = source.switcher;
                    if (!pluginService.savePluginData(pluginId, "wallpaperSelector", {
                        displayMode: "slice", directory,
                        sliceWidth: launcher.sliceWidth, expandedWidth: launcher.expandedWidth,
                        sliceHeight: launcher.sliceHeight, expandedHeight: launcher.sliceHeight, skewOffset: launcher.skewOffset,
                        sliceSpacing: launcher.sliceSpacing, cornerRadius: launcher.cornerRadius,
                        wheelOuterRadius: switcher.wheelOuterRadius, wheelGap: switcher.wheelGap,
                        wheelStartAngle: switcher.wheelStartAngle, dimOpacity: switcher.dimOpacity
                    }))
                        throw new Error("Не вдалося зберегти налаштування шпалер");
                }
            } else if (version === 1) {
                // Repair the first-run copy only if it still has the exact old
                // switcher-derived slice values; never replace later GUI edits.
                const old = pluginService.loadPluginData(pluginId, "wallpaperSelector", {});
                if (old.sliceWidth === 135 && old.sliceHeight === 520 && old.sliceSpacing === -22)
                    pluginService.savePluginData(pluginId, "wallpaperSelector", Object.assign({}, old, {
                        sliceWidth: 180, expandedWidth: 468, sliceHeight: 332,
                        skewAngle: 0, sliceSpacing: 15, cornerRadius: 20
                    }));
            }
            function convert(section, heightFallback, angleKey, oldKey, heightKey, expandedKey) {
                const value = Object.assign({}, section || {});
                const height = Number(value[heightKey]) > 0 ? Number(value[heightKey]) : heightFallback;
                if (value[expandedKey] === undefined) value[expandedKey] = height;
                if (value[angleKey] === undefined) value[angleKey] = Math.atan(Number(value[oldKey] || 0) / height) * 180 / Math.PI;
                delete value[oldKey];
                if (value.customPresets) {
                    const presets = {};
                    for (const name in value.customPresets)
                        presets[name] = convert(value.customPresets[name], heightFallback, angleKey, oldKey, heightKey, expandedKey);
                    value.customPresets = presets;
                }
                return value;
            }
            if (version < 3) {
                for (const [key, height, angle, old, heightKey, expanded] of [
                    ["launcher", 332, "skewAngle", "skewOffset", "sliceHeight", "expandedHeight"],
                    ["wallpaperSelector", 332, "skewAngle", "skewOffset", "sliceHeight", "expandedHeight"],
                    ["switcher", 520, "sliceSkewAngle", "sliceSkewOffset", "sliceHeight", "sliceExpandedHeight"]
                ]) {
                    const section = pluginService.loadPluginData(pluginId, key, {});
                    pluginService.savePluginData(pluginId, key, convert(section, height, angle, old, heightKey, expanded));
                }
            }
            if (version < 4) {
                const wallpaper = Object.assign({}, pluginService.loadPluginData(pluginId, "wallpaperSelector", {}));
                if ("sliceSkewOffset" in wallpaper) {
                    delete wallpaper.sliceSkewOffset;
                    pluginService.savePluginData(pluginId, "wallpaperSelector", wallpaper);
                }
            }
            if (version < 5) {
                const shared = pluginService.loadPluginData(pluginId, "appearance", {}) || {};
                const oldScale = pluginService.loadPluginData(pluginId, "uiScale", 1);
                for (const key of ["launcher", "wallpaperSelector", "switcher"]) {
                    const section = Object.assign({}, pluginService.loadPluginData(pluginId, key, {}));
                    section.uiScale = section.uiScale ?? oldScale;
                    section.cornerRadius = section.cornerRadius ?? shared.cornerRadius ?? 20;
                    section.dimOpacity = section.dimOpacity ?? shared.dimOpacity ?? .3;
                    section.inactiveDimOpacity = section.inactiveDimOpacity ?? .3;
                    delete section.surfaceOpacity;
                    if (key !== "switcher") {
                        delete section.displayMode;
                        for (const obsolete of Object.keys(section).filter(k => /^(hex|grid|wheel|compact)/.test(k)))
                            delete section[obsolete];
                        delete section.roundCorners;
                    }
                    pluginService.savePluginData(pluginId, key, section);
                }
                const panel = Object.assign({}, pluginService.loadPluginData(pluginId, "topPanel", {}), {
                    height: 23, itemGap: 2, uiScale: 1,
                    left: ["runningApps"],
                    centerBeforeClock: ["workspaces", "language", "clipboard"],
                    centerAfterClock: ["controlCenter", "notifications", "audio", "bluetooth", "launcher", "wallpapers", "settings"],
                    right: ["tray", "cpu", "ram", "gpu", "network"]
                });
                for (const key of ["topInset", "blockGap", "surfaceOpacity", "cornerRadius"]) delete panel[key];
                pluginService.savePluginData(pluginId, "topPanel", panel);
                pluginService.savePluginData(pluginId, "appearance", undefined);
                pluginService.savePluginData(pluginId, "uiScale", undefined);
            }
            if (version < 6) {
                const panel = Object.assign({}, pluginService.loadPluginData(pluginId, "topPanel", {}));
                const defaults = {
                    left:["runningApps"], centerBeforeClock:["workspaces","language","clipboard"],
                    centerAfterClock:["controlCenter","wallpapers"], right:["tray","cpu","gpu","network"]
                };
                const removed = ["audio","bluetooth","launcher","settings","shellActions","notifications","ram"];
                for (const lane of Object.keys(defaults))
                    panel[lane] = (panel[lane] || defaults[lane]).filter(widget => !removed.includes(widget));
                const cpuLane = Object.keys(defaults).find(lane => panel[lane].includes("cpu")) || "right";
                if (!panel[cpuLane].includes("cpu")) panel[cpuLane].push("cpu");
                panel[cpuLane].splice(panel[cpuLane].indexOf("cpu") + 1, 0, "ram");
                panel.centerAfterClock.push("notifications");
                Object.assign(panel, {height:28,itemGap:1,uiScale:1,cornerRadius:5});
                panel.autoHideScreens = panel.autoHideScreens || {};
                pluginService.savePluginData(pluginId, "topPanel", panel);
            }
            if (version < 7) {
                const panel = Object.assign({}, pluginService.loadPluginData(pluginId, "topPanel", {}));
                for (const lane of ["left", "centerBeforeClock", "centerAfterClock", "right"]) {
                    if (Array.isArray(panel[lane]))
                        panel[lane] = panel[lane].filter(widget => widget !== "ram");
                }
                delete panel.cornerRadius;
                delete panel.surfaceOpacity;
                pluginService.savePluginData(pluginId, "topPanel", panel);
            }
            if (version < 9) {
                const wallpaper = Object.assign({}, pluginService.loadPluginData(pluginId, "wallpaperSelector", {}));
                delete wallpaper.wallpaperBlurPercent;
                delete wallpaper.wallpaperBlur;
                pluginService.savePluginData(pluginId, "wallpaperSelector", wallpaper);
            }
            if (version < 10) {
                const panel = Object.assign({}, pluginService.loadPluginData(pluginId, "topPanel", {}));
                const actions = ["notifications", "wallpapers", "controlCenter", "clipboard", "language"];
                for (const lane of ["left", "centerBeforeClock", "centerAfterClock", "right"])
                    panel[lane] = (panel[lane] || []).filter(widget => !actions.includes(widget));
                panel.centerBeforeClock = panel.centerBeforeClock.concat(actions);
                pluginService.savePluginData(pluginId, "topPanel", panel);
            }
            if (version < 11) {
                const panel = Object.assign({}, pluginService.loadPluginData(pluginId, "topPanel", {}));
                panel.itemGap = 6;
                delete panel.blockGap;
                pluginService.savePluginData(pluginId, "topPanel", panel);
            }
            if (version < 12) {
                const panel = Object.assign({}, pluginService.loadPluginData(pluginId, "topPanel", {}));
                panel.itemGap = 3;
                pluginService.savePluginData(pluginId, "topPanel", panel);
            }
            if (version < 13) {
                const panel = Object.assign({}, pluginService.loadPluginData(pluginId, "topPanel", {}));
                for (const lane of ["left", "centerBeforeClock", "centerAfterClock", "right"])
                    panel[lane] = (panel[lane] || []).filter(widget => widget !== "codex");
                const right = panel.right || [];
                const tray = right.indexOf("tray");
                right.splice(tray < 0 ? 0 : tray + 1, 0, "codex");
                panel.right = right;
                pluginService.savePluginData(pluginId, "topPanel", panel);
            }
            pluginService.savePluginData(pluginId, "migrationVersion", 13);
        } catch (error) {
            console.warn("glassShell: міграцію не завершено:", error);
        } finally {
            migrating = false;
        }
    }

    Component.onCompleted: {
        Qt.callLater(migrate);
        Qt.callLater(cutoverBars);
    }
    onPluginServiceChanged: Qt.callLater(migrate)

    function cutoverBars() {
        if (!pluginService || pluginService.loadPluginData(pluginId, "layoutVersion", 0) >= 3) return;
        for (const bar of SettingsData.barConfigs) {
            if ((bar.id === "default" && bar.name === "DMS Glass · DP-1")
                    || (bar.id === "glass-hdmi" && bar.name === "DMS Glass · HDMI-A-1"))
                SettingsData.updateBarConfig(bar.id, Object.assign({}, bar, {enabled: false}));
        }
        pluginService.savePluginData(pluginId, "layoutVersion", 3);
    }

    function openOverlay(nextMode, requestedScreenName) {
        const chooseFolder = nextMode === "wallpaperFolder";
        if (chooseFolder) nextMode = "wallpapers";
        const screen = (requestedScreenName ? Quickshell.screens.find(s => s.name === requestedScreenName) : focusedScreen) ?? null;
        if (!screen) return;
        if (!chooseFolder && mode === nextMode && targetScreenName === screen.name) {
            mode = "closed";
            return;
        }
        mode = "closed";
        targetScreenName = screen.name;
        mode = nextMode;
        if (nextMode === "launcher") Qt.callLater(() => launcher.focusSearch());
        if (chooseFolder) Qt.callLater(() => wallpapers.openDirectoryChooser());
    }

    function closeOverlay() { mode = "closed"; }
    function workspaceStep(direction) {
        if (mode !== "workspaces") openOverlay("workspaces", "");
        if (mode === "workspaces") {
            if (direction > 0) workspaces.next(); else workspaces.prev();
        }
    }

    Connections {
        target: root.pluginService
        function onGlobalVarChanged(id, key) {
            if (id !== "glassShell" || key !== "request") return;
            const request = root.pluginService.getGlobalVar(id, key, {});
            root.openOverlay(request.kind, request.screen || "");
        }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.mode !== "closed" && !root.targetScreen) root.closeOverlay();
        }
    }

    IpcHandler {
        target: "glassShell"
        function launcherToggle(): void { root.openOverlay("launcher", ""); }
        function settings(section: string): void { root.openPluginSettings(section); }
        function wallpaperToggle(): void { root.openOverlay("wallpapers", ""); }
        function workspaceNext(): void { root.workspaceStep(1); }
        function workspacePrev(): void { root.workspaceStep(-1); }
        function workspaceConfirm(): void { if (root.mode === "workspaces") workspaces.confirm(); }
        function workspaceCancel(): void { if (root.mode === "workspaces") workspaces.cancel(); }
    }

    GlassWallpaperParallax {}

    GlassTopPanel {
        pluginService: root.pluginService
        settings: root.pluginData
        onRequest: (kind, screenName) => root.openOverlay(kind, screenName)
        onSettingsRequested: section => root.openPluginSettings(section)
    }

    PanelWindow {
        id: overlay
        screen: root.targetScreen
        visible: root.mode !== "closed" && root.targetScreen !== null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.layer: wallpapers.nativeDialogOpen ? WlrLayer.Bottom : WlrLayer.Overlay
        WlrLayershell.namespace: "dms-glass-shell"
        WlrLayershell.keyboardFocus: visible && !wallpapers.nativeDialogOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        LauncherSelector {
            id: launcher
            anchors.fill: parent
            visible: root.mode === "launcher"
            open: visible
            settings: ({appLauncher: root.pluginData.launcher || {}, appOverrides: root.pluginData.appOverrides || {}, terminal: root.pluginData.terminal || "kitty", paths: root.pluginData.paths || {}})
            targetScreen: root.targetScreen
            onCloseRequested: root.closeOverlay()
            onSettingsRequested: root.openPluginSettings("launcher")
        }
        WorkspaceSelector {
            id: workspaces
            anchors.fill: parent
            visible: root.mode === "workspaces"
            open: visible
            settings: root.pluginData.switcher || ({})
            targetScreen: root.targetScreen
            onCloseRequested: root.closeOverlay()
            onSettingsRequested: root.openPluginSettings("switcher")
        }
        WallpaperSelector {
            id: wallpapers
            anchors.fill: parent
            visible: root.mode === "wallpapers"
            open: visible
            settings: root.pluginData.wallpaperSelector || ({})
            targetScreen: root.targetScreen
            onCloseRequested: root.closeOverlay()
            onSettingsRequested: root.openPluginSettings("wallpaperSelector")
            onConfigurationChanged: value => root.pluginService.savePluginData("glassShell", "wallpaperSelector", value)
        }
    }
}
