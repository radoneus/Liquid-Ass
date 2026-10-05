// Presentation adapted from liixini/skwd skwd-launch/qml/launcher/AppLauncher.qml.
// MIT License, Copyright (c) 2025-2026 liixini.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root
    property bool open: false
    property var settings: ({})
    property var targetScreen: null
    signal closeRequested()
    signal settingsRequested()
    property point lastHoverPosition: Qt.point(-1, -1)
    readonly property var launcher: settings?.appLauncher || ({})
    readonly property real adaptiveScale: Math.max(.75, Math.min(1.5, Math.min((targetScreen?.width || width) / 1920, (targetScreen?.height || height) / 1080)))
    readonly property real uiScale: Math.max(.5, Math.min(2, Number(launcher.uiScale ?? 1))) * adaptiveScale
    readonly property real smallWidth: Math.max(20, Number(launcher.sliceWidth ?? 180)) * uiScale
    readonly property real bigWidth: Math.max(20, Number(launcher.expandedWidth ?? 468)) * uiScale
    readonly property real smallHeight: Math.max(20, Number(launcher.sliceHeight ?? 332)) * uiScale
    readonly property real bigHeight: Math.max(20, Number(launcher.expandedHeight ?? launcher.sliceHeight ?? 332)) * uiScale
    readonly property real skewAngle: Math.max(-45, Math.min(45, Number(launcher.skewAngle ?? 0)))
    readonly property real cardFit: Math.min(1, Math.max(.01, (gallery.width - 20) / bigWidth), Math.max(.01, (gallery.height - 12) / Math.max(bigHeight, smallHeight)))
    readonly property int visibleCount: Math.max(1, Math.min(25, Math.floor(Number(launcher.visibleCount ?? 9))))
    // Clamp once against the narrowest width/height ratio; all cards keep the same side angle.
    readonly property real effectiveAngle: Math.atan(Math.max(-.4 * Math.min(smallWidth / smallHeight, bigWidth / bigHeight), Math.min(.4 * Math.min(smallWidth / smallHeight, bigWidth / bigHeight), Math.tan(skewAngle * Math.PI / 180)))) * 180 / Math.PI
    function skew(w, h) { return h * Math.tan(effectiveAngle * Math.PI / 180); }
    function leftEdge(w, h, y) {
        const s = skew(w, h);
        return Math.max(0, s) + (Math.max(0, -s) - Math.max(0, s)) * y / h;
    }
    function rightEdge(w, h, y) {
        const s = skew(w, h);
        return w + Math.min(0, s) + (-Math.max(0, s) - Math.min(0, s)) * y / h;
    }
    function cardWidth(index) { return (index === selectedIndex ? bigWidth : smallWidth) * cardFit; }
    function cardHeight(index) { return (index === selectedIndex ? bigHeight : smallHeight) * cardFit; }
    function advance(index) {
        const w = cardWidth(index), h = cardHeight(index), nextW = cardWidth(index + 1), nextH = cardHeight(index + 1);
        const top = Math.max(-h / 2, -nextH / 2), bottom = Math.min(h / 2, nextH / 2);
        function correction(y) { return root.leftEdge(nextW, nextH, y + nextH / 2) - root.rightEdge(w, h, y + h / 2); }
        return Math.max(20, Number(launcher.sliceSpacing ?? 15) * uiScale * cardFit - Math.min(correction(top), correction(bottom)));
    }
    function cardX(index) {
        let x = (gallery.width - cardWidth(selectedIndex)) / 2;
        if (index < selectedIndex) for (let i = selectedIndex - 1; i >= index; --i) x -= advance(i);
        else for (let i = selectedIndex; i < index; ++i) x += advance(i);
        return x;
    }
    readonly property int firstCard: Math.max(0, selectedIndex - Math.floor((visibleCount - 1) / 2))
    readonly property int lastCard: Math.min(results.length, Math.max(visibleCount, selectedIndex + Math.ceil((visibleCount - 1) / 2) + 1))
    // A bounded circular pool retains each visible app's delegate as the window advances.
    // Only the card leaving the window is recycled for the incoming app.
    readonly property int poolSize: Math.min(visibleCount, results.length)
    function pooledIndex(slot) {
        if (!poolSize) return -1;
        return firstCard + ((slot - firstCard % poolSize + poolSize) % poolSize);
    }
    property string selectedId: ""
    property string query: ""
    property string filter: ""
    property int selectedIndex: 0
    property var steamGames: ({})
    property var splashImages: ({})
    property var steamLibraryPaths: []
    readonly property var steamFolders: {
        var first = root.resolvePath(root.settings?.paths?.steam || "~/.local/share/Steam");
        var extra = root.steamLibraryPaths.concat(root.settings?.paths?.steamLibraries || []);
        var all = [first];
        for (var i = 0; i < extra.length; i++) {
            var candidate = root.resolvePath(extra[i]);
            if (candidate && all.indexOf(candidate) === -1) all.push(candidate);
        }
        return all;
    }
    readonly property var defaultFilters: [
        { key: "all", icon: "◈", label: "Усі", type: "all", value: "" },
        { key: "desktop", icon: "▦", label: "Програми", type: "source", value: "desktop" },
        { key: "game", icon: "◆", label: "Ігри", type: "category", value: "Game" },
        { key: "steam", icon: "◉", label: "Steam", type: "source", value: "steam" }
    ]
    readonly property var filters: Array.isArray(launcher.filters) && launcher.filters.length ? launcher.filters : defaultFilters
    readonly property var nativeApplications: DesktopEntries.applications.values
    readonly property var allApplications: {
        var native = root.nativeApplications;
        var steam = root.steamGames;
        var overrides = settings?.appOverrides || settings?.apps || {};
        var apps = [];
        var seen = {};
        for (var i = 0; i < native.length; i++) {
            var entry = native[i];
            if (!entry || !entry.name || !entry.command || entry.noDisplay || entry.hidden) continue;
            var id = entry.id || entry.name;
            if (seen[id]) continue;
            seen[id] = true;
            var categories = entry.categories || "";
            var item = { id: id, name: entry.name, icon: entry.icon || "", categories: Array.isArray(categories) ? categories.join(";") : String(categories), source: "desktop", entry: entry };
            apps.push(root.withOverride(item, overrides));
        }
        for (var key in steam) {
            if (!steam[key] || seen["steam:" + key]) continue;
            var game = steam[key];
            seen["steam:" + key] = true;
            apps.push(root.withOverride({ id: "steam:" + key, steamId: key, name: game.name, icon: "steam", categories: "Game;", source: "steam", background: root.resolvePath(settings?.paths?.steam || "~/.local/share/Steam") + "/appcache/librarycache/" + key + "_library_600x900.jpg" }, overrides));
        }
        apps.sort((a, b) => a.name.localeCompare(b.name));
        return apps;
    }
    function publishApplications() {
        PluginService.setGlobalVar("glassShell", "applications", allApplications.map(a => ({
            id: a.id, name: a.name, displayName: a.displayName, icon: a.icon,
            source: a.source, background: a.background, tags: a.tags, hidden: a.hidden
        })));
    }
    onAllApplicationsChanged: publishApplications()
    readonly property var applications: allApplications.filter(a => !a.hidden)
    function usageCount(app, ranking) {
        const id = String(app.id || "");
        const item = ranking[id] || ranking[id.replace(/\.desktop$/, "")] || ranking[id + ".desktop"];
        return Number(item?.usageCount || 0);
    }
    function matchTier(app, terms) {
        if (!terms.length) return 0;
        const name = String(app.displayName || app.name || "").toLocaleLowerCase();
        const nativeName = String(app.name || "").toLocaleLowerCase();
        const phrase = terms.join(" ");
        if (name === phrase || nativeName === phrase) return 0;
        if (name.startsWith(phrase) || nativeName.startsWith(phrase)) return 1;
        if (name.includes(phrase) || nativeName.includes(phrase)) return 2;
        const metadata = [app.categories, app.tags, app.entry?.comment || ""].join(" ").toLocaleLowerCase();
        let score = 3;
        for (const term of terms) {
            const tier = name.includes(term) || nativeName.includes(term) ? 0 : metadata.includes(term) ? 10 : -1;
            if (tier < 0) return -1;
            score += tier;
        }
        return score;
    }
    readonly property var results: {
        const ranking = AppUsageHistoryData.appUsageRanking || {};
        const tiers = {};
        const terms = root.query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
        const config = root.filters.find(f => f.key === root.filter);
        const list = root.applications.filter(a => {
            if (config && config.type !== "all" && config.value) {
                const value = String(config.value).toLocaleLowerCase();
                if (config.type === "source" && a.source.toLocaleLowerCase() !== value) return false;
                if (config.type === "category" && !a.categories.toLocaleLowerCase().includes(value)) return false;
                if (config.type === "tag" && !a.tags.toLocaleLowerCase().includes(value)) return false;
            }
            const tier = root.matchTier(a, terms);
            if (tier >= 0) tiers[a.id] = tier;
            return tier >= 0;
        });
        list.sort((a, b) => {
            if (terms.length) {
                const diff = tiers[a.id] - tiers[b.id];
                if (diff) return diff;
            }
            return root.usageCount(b, ranking) - root.usageCount(a, ranking)
                || String(a.displayName || a.name).localeCompare(String(b.displayName || b.name))
                || String(a.id).localeCompare(String(b.id));
        });
        return list;
    }
    onResultsChanged: {
        const old = results.findIndex(a => a.id === selectedId);
        selectedIndex = results.length ? (old >= 0 ? old : Math.max(0, Math.min(selectedIndex, results.length - 1))) : -1;
        selectedId = results[selectedIndex]?.id || "";
    }
    onSelectedIndexChanged: selectedId = results[selectedIndex]?.id || ""
    onOpenChanged: {
        if (open) {
            publishApplications();
            selectedId = "";
            query = "";
            filter = "";
            selectedIndex = 0;
            Qt.callLater(focusSearch);
        } else {
            query = "";
        }
    }
    function resolvePath(path) {
        if (!path) return "";
        var home = Quickshell.env("HOME") || "";
        return path === "~" ? home : path.startsWith("~/") ? home + path.slice(1) : path;
    }
    function fileUrl(path) { return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : ""; }
    function withOverride(app, overrides) {
        var match = overrides[app.name.toLocaleLowerCase()];
        if (!match) for (var key in overrides) {
            if (!key.startsWith("_") && app.name.toLocaleLowerCase().includes(key.toLocaleLowerCase())) { match = overrides[key]; break; }
        }
        match = typeof match === "string" ? { background: match } : match || {};
        var result = Object.assign({}, app, {
            background: resolvePath(match.background || app.background || ""),
            displayName: match.displayName || "", customIcon: match.icon || "",
            useDesktopIcon: !!match.useDesktopIcon, tags: match.tags || "", hidden: !!match.hidden
        });
        return result;
    }
    function matchSplash(name) {
        var key = name.toLocaleLowerCase();
        var simple = key.replace(/[^\p{L}\p{N}]/gu, "");
        var splash = splashImages[key] || splashImages[key.replace(/ /g, "_")] || splashImages[key.replace(/ /g, "-")];
        if (!splash && simple.length > 2) for (var stem in splashImages) {
            var comparable = stem.replace(/[^\p{L}\p{N}]/gu, "");
            if (comparable.length > 2 && (comparable.includes(simple) || simple.includes(comparable))) { splash = splashImages[stem]; break; }
        }
        return splash || "";
    }
    function registerManifest(path, content) {
        var id = /"appid"\s+"([0-9]+)"/.exec(content);
        var name = /"name"\s+"([^"]+)"/.exec(content);
        if (!id || !name || /proton|redistribut|steamworks|steam linux runtime|wallpaper engine|steamvr/i.test(name[1])) return;
        var copy = Object.assign({}, steamGames);
        copy[id[1]] = { name: name[1], path: path };
        steamGames = copy;
    }
    function unregisterManifest(path) {
        var copy = Object.assign({}, steamGames);
        for (var id in copy) if (copy[id].path === path) delete copy[id];
        steamGames = copy;
    }
    function parseLibraryFolders(text) {
        var paths = [];
        var pattern = /"path"\s+"((?:\\.|[^"\\])+)"/g;
        var match;
        while ((match = pattern.exec(text)) !== null) paths.push(match[1].replace(/\\\\/g, "\\"));
        steamLibraryPaths = paths;
    }
    function focusSearch() {
        if (!open) return;
        search.forceActiveFocus();
        search.cursorPosition = search.length;
    }
    function activate(index) {
        if (index < 0 || index >= results.length) return;
        const app = results[index];
        if (app.entry && app.entry.runInTerminal) {
            // DesktopEntry.command has expanded Exec field codes; do not pass raw Exec to a shell.
            Quickshell.execDetached({
                command: [root.settings?.terminal || SessionData.resolveTerminal() || "xterm", "-e"].concat(app.entry.command),
                workingDirectory: app.entry.workingDirectory || Quickshell.env("HOME")
            });
        } else if (app.entry) SessionService.launchDesktopEntry(app.entry, false);
        else if (app.steamId) Quickshell.execDetached(["steam", "steam://rungameid/" + app.steamId]);
        else return;
        AppUsageHistoryData.addAppUsage(app.entry || {
            id: app.id, name: app.name, icon: app.icon, exec: "steam steam://rungameid/" + app.steamId
        });
        closeRequested();
    }
    function step(delta) { if (results.length) selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta)); }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            closeRequested(); event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
            step(1); event.accepted = true;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
            step(-1); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate(selectedIndex); event.accepted = true;
        }
    }
    property var libraryIndex: FileView {
        path: root.resolvePath(root.settings?.paths?.steam || "~/.local/share/Steam") + "/steamapps/libraryfolders.vdf"
        preload: true
        watchChanges: true
        onLoaded: root.parseLibraryFolders(text())
        onFileChanged: { reload(); root.parseLibraryFolders(text()); }
    }
    Repeater {
        model: root.steamFolders
        Item {
            required property string modelData
            width: 0; height: 0; visible: false
            FolderListModel {
                id: manifests
                folder: root.fileUrl(modelData + "/steamapps")
                nameFilters: ["appmanifest_*.acf"]
                showDirs: false
                showDotAndDotDot: false
            }
            Repeater {
                model: manifests
                Item {
                    required property string filePath
                    width: 0; height: 0; visible: false
                    property var manifest: FileView {
                        path: filePath
                        preload: true
                        watchChanges: true
                        onLoaded: root.registerManifest(filePath, text())
                        onFileChanged: { reload(); root.registerManifest(filePath, text()); }
                    }
                    Component.onDestruction: root.unregisterManifest(filePath)
                }
            }
        }
    }
    FolderListModel {
        id: splashes
        folder: root.fileUrl(root.resolvePath(root.settings?.paths?.splash || "~/appsplash"))
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.avif"]
        showDirs: false
        showDotAndDotDot: false
        caseSensitive: false
    }
    Repeater {
        model: splashes
        Item {
            required property string filePath
            required property string fileName
            width: 0; height: 0; visible: false
            Component.onCompleted: {
                var images = Object.assign({}, root.splashImages);
                images[fileName.replace(/\.[^.]+$/, "").toLocaleLowerCase()] = filePath;
                root.splashImages = images;
            }
            Component.onDestruction: {
                var images = Object.assign({}, root.splashImages);
                var key = fileName.replace(/\.[^.]+$/, "").toLocaleLowerCase();
                if (images[key] === filePath) delete images[key];
                root.splashImages = images;
            }
        }
    }

    visible: open
    Rectangle { anchors.fill: parent; color: Theme.withAlpha(Theme.surface, Math.max(0, Math.min(1, Number(root.launcher.dimOpacity ?? .58)))) }
    MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
    Item {
        id: panel
        width: Math.min(root.width - 28, 1560 * root.adaptiveScale)
        height: Math.min(root.height - 28, Math.max(root.smallHeight, root.bigHeight) + 170)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        palette.text: Theme.surfaceText
        palette.buttonText: Theme.surfaceText
        palette.base: Theme.surfaceContainer
        palette.button: Theme.surfaceContainerHigh
        palette.highlight: Theme.primary
        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 58
            radius: 14
            color: Theme.withAlpha(Theme.surfaceContainer, .88)
        }
        MouseArea { anchors.fill: parent; onClicked: {} }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10
            RowLayout {
                id: toolbar
                Layout.fillWidth: true
                spacing: 12
                Basic.TextField {
                    id: search
                    Layout.fillWidth: true
                    Layout.minimumWidth: 130
                    Layout.preferredHeight: 40
                    font.pixelSize: 14
                    verticalAlignment: TextInput.AlignVCenter
                    leftPadding: 10
                    rightPadding: 10
                    placeholderText: "Пошук програм…"
                    placeholderTextColor: Theme.surfaceTextMedium
                    color: Theme.surfaceText
                    selectionColor: Theme.primary
                    text: root.query
                    selectByMouse: true
                    background: Rectangle {
                        radius: 10
                        color: Theme.surfaceContainerHigh
                        border.color: search.activeFocus ? Theme.primary : Theme.outline
                        border.width: search.activeFocus ? 2 : 1
                    }
                    onTextEdited: { root.selectedId = ""; root.query = text; root.selectedIndex = 0; }
                    Keys.onPressed: event => root.handleKey(event)
                }
                DankButton {
                    text: "⚙"
                    Accessible.name: "Налаштування"
                    ToolTip.visible: hovered
                    ToolTip.text: Accessible.name
                    onClicked: root.settingsRequested()
                }
                DankButton { text: "✕"; Accessible.name: "Закрити меню"; textColor: Theme.surfaceText; onClicked: root.closeRequested() }
            }
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                contentWidth: filterRow.width
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: filterRow
                    spacing: 6
                    Repeater {
                        model: root.filters
                        DankButton {
                            required property var modelData
                            text: modelData.icon + " " + modelData.label
                            backgroundColor: root.filter === (modelData.type === "all" ? "" : modelData.key) ? Theme.primaryContainer : Theme.surfaceContainerHigh
                            textColor: Theme.surfaceText
                            buttonHeight: 36
                            onClicked: {
                                root.selectedId = "";
                                root.filter = modelData.type === "all" ? "" : (root.filter === modelData.key ? "" : modelData.key);
                                root.selectedIndex = 0;
                                root.focusSearch();
                            }
                        }
                    }
                }
            }
            Item {
                id: gallery
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                Text {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    text: "Нічого не знайдено"
                    color: Theme.surfaceText
                }
                Repeater {
                    model: root.open ? root.poolSize : 0
                    LauncherTile {
                        id: card
                        required property int index
                        readonly property int appIndex: root.pooledIndex(index)
                        readonly property bool cardVisible: appIndex >= root.firstCard && appIndex < root.lastCard && appIndex < root.results.length
                        property bool recycled: false
                        onAppIndexChanged: {
                            recycled = true;
                            recycleTimer.restart();
                        }
                        Timer { id: recycleTimer; interval: 0; onTriggered: card.recycled = false }
                        visible: cardVisible
                        app: root.results[appIndex] || ({})
                        width: root.cardWidth(appIndex)
                        height: root.cardHeight(appIndex)
                        x: root.cardX(appIndex)
                        y: (gallery.height - height) / 2
                        decodeWidth: Math.min(2048, Math.max(root.bigWidth, root.smallWidth))
                        decodeHeight: Math.min(2048, Math.max(root.bigHeight, root.smallHeight))
                        selected: appIndex === root.selectedIndex
                        skewAngle: root.effectiveAngle
                        cornerRadius: Math.max(0, Number(root.launcher.cornerRadius ?? 20)) * root.uiScale * root.cardFit
                        dimOpacity: Math.max(0, Math.min(1, Number(root.launcher.inactiveDimOpacity ?? .3)))
                        splash: root.matchSplash(app.name || "")
                        z: selected ? 10 : 0
                        Behavior on x { enabled: !recycled; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on width { enabled: !recycled; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on height { enabled: !recycled; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        onHighlighted: position => {
                            if (Math.hypot(position.x - root.lastHoverPosition.x, position.y - root.lastHoverPosition.y) < 3) return;
                            root.lastHoverPosition = position;
                            root.selectedIndex = appIndex;
                        }
                        onActivated: root.activate(appIndex)
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    z: 100
                    acceptedButtons: Qt.NoButton
                    onWheel: event => {
                        root.lastHoverPosition = mapToGlobal(event.x, event.y);
                        if (event.angleDelta.y) root.step(event.angleDelta.y > 0 ? -1 : 1);
                        event.accepted = true;
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                color: Theme.surfaceText
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "← → — вибрати · Enter — запустити · Esc — закрити"
                Accessible.name: text
                Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.implicitWidth + 24)
                    height: parent.height + 8
                    radius: 10
                    color: Theme.withAlpha(Theme.surfaceContainer, .88)
                }
            }
        }
    }
    Keys.onPressed: event => root.handleKey(event)
}
