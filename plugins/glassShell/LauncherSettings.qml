// Settings UI adapted from liixini/skwd skwd-settings/qml/sections/LaunchSettings.qml.
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
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Qt.labs.folderlistmodel
import Quickshell
import qs.Common
import qs.Widgets

ColumnLayout {
    id: root
    property var settings: ({})
    property var applications: []
    signal configurationChanged(var patch)
    readonly property var launcher: settings.launcher || ({})
    property string category: "Категорії"
    property string appQuery: ""
    property string selectedApp: ""
    property bool pickerOpen: false
    property string pickerDir: ""
    onVisibleChanged: if (!visible) pickerOpen = false
    readonly property var categories: ["Категорії", "Шляхи", "Картки програм"]
    readonly property var defaultFilters: [
        {key:"all",icon:"◈",label:"Усі",type:"all",value:""},
        {key:"desktop",icon:"▦",label:"Програми",type:"source",value:"desktop"},
        {key:"game",icon:"◆",label:"Ігри",type:"category",value:"Game"},
        {key:"steam",icon:"◉",label:"Steam",type:"source",value:"steam"}
    ]
    readonly property var matchingApps: applications.filter(app => (app.name || "").toLocaleLowerCase().includes(appQuery)).slice(0, 100)
    readonly property var selectedOverride: appOverride(selectedApp)
    spacing: 10
    Shortcut { sequence: "Escape"; enabled: root.visible && root.pickerOpen; onActivated: root.pickerOpen = false }
    function fileUrl(path) { return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : ""; }
    function resolvePath(path) {
        const home = Quickshell.env("HOME") || "";
        return path === "~" ? home : path.startsWith("~/") ? home + path.slice(1) : path;
    }
    function change(patch) { configurationChanged({launcher: Object.assign({}, launcher, patch)}); }
    function changeRoot(patch) { configurationChanged(patch); }
    function changeFilter(index, field, value) {
        const filters = JSON.parse(JSON.stringify(launcher.filters || defaultFilters));
        if (index < 0 || index >= filters.length) return;
        filters[index][field] = value;
        change({filters});
    }
    function appOverride(name) {
        const items = settings.appOverrides || {};
        const lower = name.toLowerCase();
        if (items[lower]) return items[lower];
        for (const key in items) if (!key.startsWith("_") && lower.includes(key.toLowerCase())) return items[key];
        return {};
    }
    function setApp(name, field, value) {
        if (!name) return;
        const key = name.toLowerCase();
        const apps = Object.assign({}, settings.appOverrides || {});
        apps[key] = Object.assign({}, apps[key] || appOverride(name), {[field]: value});
        changeRoot({appOverrides: apps});
    }
    function setPath(key, value) { changeRoot({paths: Object.assign({}, settings.paths || {}, {[key]: value})}); }

    DankDropdown {
        Layout.fillWidth: true; text: "Додатково для програм"; options: root.categories
        currentValue: root.category
        onValueChanged: value => root.category = value
    }
    Text { visible: root.category === "Категорії"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Категорії — кнопки над каруселлю. Виберіть джерело програм, категорію .desktop або власний тег."; color: Theme.surfaceTextSecondary }
    Repeater {
        model: root.category === "Категорії" ? root.launcher.filters || root.defaultFilters : []
        delegate: ColumnLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                DankTextField { Layout.fillWidth: true; text: modelData.label || ""; placeholderText: "Назва категорії"; Accessible.name: "Назва категорії"; onEditingFinished: root.changeFilter(index, "label", text) }
                DankButton {
                    text: "×"; Accessible.name: "Видалити категорію " + modelData.label
                    onClicked: { const f = JSON.parse(JSON.stringify(root.launcher.filters || root.defaultFilters)); f.splice(index,1); root.change({filters:f}); }
                }
            }
            DankDropdown {
                Layout.fillWidth: true; text: "Показувати"; options: ["Усі програми","За джерелом","За категорією .desktop","За власним тегом"]
                currentValue: ({"all":"Усі програми","source":"За джерелом","category":"За категорією .desktop","tag":"За власним тегом"})[modelData.type] || "Усі програми"
                onValueChanged: value => root.changeFilter(index, "type", ({"Усі програми":"all","За джерелом":"source","За категорією .desktop":"category","За власним тегом":"tag"})[value])
            }
            RowLayout {
                Layout.fillWidth: true
                DankTextField { Layout.preferredWidth: 85; text: modelData.icon || ""; placeholderText: "Символ"; Accessible.name: "Символ фільтра"; onEditingFinished: root.changeFilter(index, "icon", text) }
                DankTextField { Layout.fillWidth: true; text: modelData.value || ""; placeholderText: modelData.type === "source" ? "desktop або steam" : modelData.type === "category" ? "Наприклад Game або Development" : "Власний тег"; Accessible.name: "Умова категорії"; enabled: modelData.type !== "all"; onEditingFinished: root.changeFilter(index, "value", text) }
            }
        }
    }
    ColumnLayout {
        visible: root.category === "Категорії"; Layout.fillWidth: true
        DankButton { Layout.fillWidth: true; text: "Додати категорію"; onClicked: { const f = JSON.parse(JSON.stringify(root.launcher.filters || root.defaultFilters)); f.push({key:"filter" + Date.now(),icon:"",label:"Нова категорія",type:"all",value:""}); root.change({filters:f}); } }
        DankButton { Layout.fillWidth: true; text: "Відновити початкові категорії"; onClicked: root.change({filters:root.defaultFilters}) }
    }
    ColumnLayout {
        visible: root.category === "Шляхи"; Layout.fillWidth: true
        Text { text: "Термінал"; color: Theme.surfaceText }
        DankTextField { Layout.fillWidth: true; text: root.settings.terminal || "kitty"; Accessible.name: "Термінал"; onEditingFinished: root.changeRoot({terminal:text}) }
        Text { text: "Тека зображень"; color: Theme.surfaceText }
        DankTextField { Layout.fillWidth: true; text: root.settings.paths?.splash || ""; placeholderText: "~/appsplash"; Accessible.name: "Тека зображень"; onEditingFinished: root.setPath("splash",text) }
        Text { text: "Тека Steam"; color: Theme.surfaceText }
        DankTextField { Layout.fillWidth: true; text: root.settings.paths?.steam || ""; placeholderText: "~/.local/share/Steam"; Accessible.name: "Тека Steam"; onEditingFinished: root.setPath("steam",text) }
        Text { text: "Додаткові бібліотеки Steam (шляхи через крапку з комою)"; color: Theme.surfaceText; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        DankTextField {
            Layout.fillWidth: true
            text: (root.settings.paths?.steamLibraries || []).join("; ")
            Accessible.name: "Додаткові бібліотеки Steam через крапку з комою"
            onEditingFinished: root.setPath("steamLibraries",text.split(";").map(p => p.trim()).filter(Boolean))
        }
    }
    ColumnLayout {
        visible: root.category === "Картки програм"; Layout.fillWidth: true
        DankTextField { Layout.fillWidth: true; placeholderText: "Знайти застосунок"; Accessible.name: "Пошук застосунку"; onTextEdited: root.appQuery = text.toLocaleLowerCase() }
        DankDropdown {
            Layout.fillWidth: true; text: "Застосунок"; enableFuzzySearch: true
            options: root.matchingApps.map(a => a.name)
            currentValue: root.selectedApp
            onValueChanged: value => root.selectedApp = value
        }
        Text { Layout.fillWidth: true; visible: root.matchingApps.length === 100; wrapMode: Text.WordWrap; text: "Показано перші 100 збігів; уточніть пошук, щоб знайти решту."; color: Theme.surfaceTextSecondary }
        Repeater {
            model: root.selectedApp ? [
                {key:"displayName",label:"Назва на картці",hint:"Назва"},
                {key:"background",label:"Шлях до картинки",hint:"Файл зображення"},
                {key:"icon",label:"Іконка",hint:"Назва іконки"},
                {key:"tags",label:"Теги для пошуку",hint:"Через кому"}
            ] : []
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Text { text: modelData.label; color: Theme.surfaceText }
                RowLayout {
                    Layout.fillWidth: true
                    DankTextField {
                        Layout.fillWidth: true; text: root.selectedOverride[modelData.key] || ""
                        placeholderText: modelData.hint; Accessible.name: modelData.label + " для " + root.selectedApp
                        onEditingFinished: root.setApp(root.selectedApp,modelData.key,text)
                    }
                    DankButton {
                        visible: modelData.key === "background"; text: "…"; Accessible.name: "Вибрати зображення"
                        onClicked: { root.pickerDir = root.resolvePath(root.settings.paths?.splash || "~/appsplash"); root.pickerOpen = true; }
                    }
                }
            }
        }
        RowLayout {
            visible: !!root.selectedApp; Layout.fillWidth: true
            Text { text: "Іконка .desktop"; color: Theme.surfaceText; Layout.fillWidth: true }
            DankToggle { checked: !!root.selectedOverride.useDesktopIcon; Accessible.name: "Іконка desktop"; onToggled: root.setApp(root.selectedApp,"useDesktopIcon",checked) }
        }
        RowLayout {
            visible: !!root.selectedApp; Layout.fillWidth: true
            Text { text: "Сховати програму"; color: Theme.surfaceText; Layout.fillWidth: true }
            DankToggle { checked: !!root.selectedOverride.hidden; Accessible.name: "Сховати програму"; onToggled: root.setApp(root.selectedApp,"hidden",checked) }
        }
        ColumnLayout {
            visible: root.pickerOpen && !!root.selectedApp; Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                DankTextField { id: folderInput; Layout.fillWidth: true; text: root.pickerDir; Accessible.name: "Тека зображень"; onAccepted: root.pickerDir = root.resolvePath(text) }
                DankButton { text: "Перейти"; onClicked: root.pickerDir = root.resolvePath(folderInput.text) }
                DankButton { text: "Закрити"; onClicked: root.pickerOpen = false }
            }
            GridView {
                Layout.fillWidth: true; Layout.preferredHeight: 230; clip: true
                cellWidth: 110; cellHeight: 110; model: imageFiles
                delegate: Item {
                    required property string filePath
                    required property string fileName
                    required property bool fileIsDir
                    width: 104; height: 104
                    Rectangle {
                        anchors.fill: parent; radius: 8; color: Theme.surfaceContainerHigh; border.color: Theme.outline
                        Image { anchors.fill: parent; anchors.bottomMargin: 22; source: fileIsDir ? "" : root.fileUrl(filePath); fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(104,82) }
                        Text { anchors.bottom: parent.bottom; width: parent.width; text: (fileIsDir ? "📁 " : "") + fileName; color: Theme.surfaceText; elide: Text.ElideMiddle }
                        MouseArea { anchors.fill: parent; onClicked: { if (fileIsDir) root.pickerDir = filePath; else { root.setApp(root.selectedApp,"background",filePath); root.pickerOpen = false; } } }
                    }
                }
            }
        }
    }
    FolderListModel {
        id: imageFiles
        folder: root.pickerOpen ? root.fileUrl(root.pickerDir) : ""
        nameFilters: ["*.png","*.jpg","*.jpeg","*.webp","*.avif"]
        showDirs: true; showDotAndDotDot: true; caseSensitive: false; sortField: FolderListModel.Name
    }
}
