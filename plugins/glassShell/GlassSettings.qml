import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "glassShell"
    property string category: ""
    property var data: ({})
    property var applications: []
    readonly property var options: data[category] || ({})
    readonly property bool carousel: category === "launcher" || category === "wallpaperSelector"
    readonly property string mode: options.displayMode || "wheel"
    readonly property var sections: [
        {key:"topPanel", name:"Моноброва", hint:"Розмір, щільність і порядок елементів"},
        {key:"launcher", name:"Програми", hint:"Картки, категорії та запуск програм"},
        {key:"switcher", name:"Робочі столи", hint:"Alt+Tab: вигляд, підписи та розмиття"},
        {key:"wallpaperSelector", name:"Шпалери", hint:"Картки, каталог і вибір зображення"}
    ]
    readonly property var lanes: [
        {key:"left",name:"Ліве крило"}, {key:"centerBeforeClock",name:"Ліворуч від часу"},
        {key:"centerAfterClock",name:"Праворуч від часу"}, {key:"right",name:"Праве крило"}
    ]
    readonly property var widgetNames: ({runningApps:"Запущені програми",workspaces:"Кнопки столів",language:"Мова",clipboard:"Буфер обміну",controlCenter:"Керування",notifications:"Сповіщення",wallpapers:"Шпалери",tray:"Трей",codex:"Codex",cpu:"Процесор і RAM",gpu:"Відеокарта",network:"Мережа"})
    readonly property var defaultPanel: ({height:28,itemGap:3,uiScale:1,autoHideScreens:{},left:["runningApps"],centerBeforeClock:["workspaces","notifications","wallpapers","controlCenter","clipboard","language"],centerAfterClock:[],right:["tray","codex","cpu","gpu","network"]})
    readonly property var cardFields: [
        {key:"sliceWidth",label:"Звичайна картка: ширина",value:180,min:30,max:1600},
        {key:"sliceHeight",label:"Звичайна картка: висота",value:332,min:60,max:1400},
        {key:"expandedWidth",label:"Вибрана картка: ширина",value:468,min:60,max:2400},
        {key:"expandedHeight",label:"Вибрана картка: висота",value:332,min:60,max:1400},
        {key:"skewAngle",label:"Нахил бічних сторін",description:"0° — прямокутник. Від’ємне значення змінює напрямок нахилу.",value:0,min:-45,max:45,unit:"°"},
        {key:"sliceSpacing",label:"Відстань між видимими краями",description:"Від’ємне значення накладає сусідні картки одну на одну.",value:15,min:-300,max:300},
        {key:"visibleCount",label:"Кількість видимих карток",value:9,min:1,max:25,unit:""},
        {key:"cornerRadius",label:"Заокруглення карток",value:20,min:0,max:100}
    ]
    readonly property var fields: {
        if (carousel) return cardFields;
        if (category === "topPanel") return [
            {key:"height",label:"Базова висота блоків",description:"Висота для фізичної діагоналі 24″. На інших моніторах масштабується за їхньою діагоналлю; блок часу в 1,5 раза вищий.",value:28,min:24,max:48},
            {key:"itemGap",label:"Проміжок між блоками",description:"Однакова відстань між усіма блоками, зокрема годинником. Усередині застосунків і керування відступи відповідають трею.",value:3,min:0,max:12}
        ];
        if (category !== "switcher") return [];
        if (mode === "wheel") return [
            {key:"wheelOuterRadius",label:"Зовнішній радіус колеса",value:520,min:100,max:1000},
            {key:"wheelInnerRadius",label:"Радіус центрального кола",value:135,min:80,max:500},
            {key:"wheelGap",label:"Проміжок між секторами",value:0,min:0,max:30,unit:"°"},
            {key:"wheelStartAngle",label:"Поворот колеса",value:90,min:-360,max:360,unit:"°"}
        ];
        if (mode === "slice") return cardFields.map(f => Object.assign({},f,{key:({expandedWidth:"sliceExpandedWidth",expandedHeight:"sliceExpandedHeight",skewAngle:"sliceSkewAngle",visibleCount:"sliceVisibleCount"})[f.key] || f.key})).concat([{key:"cardWidth",label:"Ширина ряду",value:1600,min:300,max:4000}]);
        if (mode === "grid") return [
            {key:"gridCellWidth",label:"Ширина картки",value:240,min:100,max:1400},
            {key:"gridCellHeight",label:"Висота картки",value:170,min:100,max:1000},
            {key:"gridSpacing",label:"Проміжок",value:14,min:0,max:100},
            {key:"gridColumns",label:"Стовпців",value:5,min:1,max:12,unit:""},
            {key:"gridRows",label:"Видимих рядків",value:4,min:1,max:10,unit:""}
        ];
        return [{key:"compactCellWidth",label:"Ширина картки",value:160,min:100,max:1000},{key:"compactCellHeight",label:"Висота картки",value:120,min:100,max:800},{key:"compactSpacing",label:"Проміжок",value:8,min:0,max:100}];
    }
    function reload() {
        if (!pluginService) return;
        const next = {};
        for (const key of ["topPanel","launcher","switcher","wallpaperSelector","appOverrides","paths"]) next[key] = loadValue(key, {}) || {};
        next.terminal = loadValue("terminal", "kitty");
        data = next;
        applications = pluginService.getGlobalVar(pluginId,"applications",[]) || [];
    }
    function patch(section, values) {
        if (!pluginService) return;
        saveValue(section,Object.assign({},loadValue(section,{}) || {},values));
        reload();
    }
    function setField(key,value) { patch(category,{[key]:value}); }
    function setAutoHide(screenName, enabled) {
        const panel = loadValue("topPanel", {}) || {};
        patch("topPanel", {autoHideScreens:Object.assign({}, panel.autoHideScreens || {}, {[screenName]:enabled})});
    }
    function launcherPatch(values) {
        for (const key of Object.keys(values)) {
            if (["launcher","appOverrides","paths"].includes(key)) patch(key,values[key]);
            else saveValue(key,values[key]);
        }
        reload();
    }
    function deepLink() {
        if (!pluginService) return;
        const requested = pluginService.getGlobalVar(pluginId,"settingsSection","");
        if (!requested) return;
        category = sections.some(s => s.key === requested) ? requested : "topPanel";
        pluginService.setGlobalVar(pluginId,"settingsSection","");
    }
    function preview() {
        pluginService?.setGlobalVar(pluginId,"request",{kind:category === "launcher" ? "launcher" : category === "switcher" ? "workspaces" : "wallpapers",screen:""});
    }
    function moveWidget(widget,target,offset) {
        const panel = Object.assign({},defaultPanel,data.topPanel || {});
        const next = {};
        for (const lane of lanes) next[lane.key] = (panel[lane.key] || []).slice();
        const origin = lanes.find(l => next[l.key].includes(widget));
        if (!origin) return;
        const index = next[origin.key].indexOf(widget);
        next[origin.key].splice(index,1);
        const insert = origin.key === target ? Math.max(0,Math.min(next[target].length,index+offset)) : next[target].length;
        next[target].splice(insert,0,widget);
        patch("topPanel",next);
    }
    function preset(slot,save) {
        const presets = Object.assign({},options.customPresets || {});
        const key = slot + "_slice";
        if (save) {
            const values = {};
            for (const f of cardFields) values[f.key] = options[f.key] ?? f.value;
            for (const field of ["uiScale","dimOpacity","inactiveDimOpacity"]) values[field] = options[field] ?? (field === "uiScale" ? 1 : .3);
            presets[key] = values;
            setField("customPresets",presets);
        } else if (presets[key]) patch(category,presets[key]);
    }
    onPluginServiceChanged: { reload(); Qt.callLater(deepLink); }
    Component.onCompleted: { reload(); deepLink(); }
    Connections {
        target: root.pluginService
        function onGlobalVarChanged(id,key) { if (id !== root.pluginId) return; if(key === "settingsSection") root.deepLink(); if(key === "applications") root.reload(); }
        function onPluginDataChanged(id) { if(id === root.pluginId) root.reload(); }
    }
    ColumnLayout {
        width: parent.width
        spacing: 10
        Text { Layout.fillWidth: true; text:"DMS Glass"; color:Theme.surfaceText; font.pixelSize:20; font.bold:true }
        Text { Layout.fillWidth: true; text:"Кольори беруться з поточної теми DMS. Розкрийте компонент, який хочете налаштувати: його розміри й ефекти не змінюють решту."; wrapMode:Text.WordWrap; color:Theme.surfaceTextSecondary; font.pixelSize:13 }
        Repeater {
            model: root.sections
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                DankButton {
                    Layout.fillWidth: true
                    text: (root.category === modelData.key ? "−  " : "+  ") + modelData.name
                    Accessible.name: modelData.name + (root.category === modelData.key ? ", згорнути" : ", розгорнути")
                    onClicked: root.category = root.category === modelData.key ? "" : modelData.key
                }
                Text { Layout.fillWidth:true; text:modelData.hint; color:Theme.surfaceTextSecondary; font.pixelSize:12; wrapMode:Text.WordWrap }
                Loader { Layout.fillWidth:true; active:root.category === modelData.key; visible:active; sourceComponent:sectionEditor; Layout.preferredHeight:active && item ? item.implicitHeight : 0 }
            }
        }
    }
    Component {
        id: sectionEditor
        ColumnLayout {
            spacing: 12
            GlassValueControl {
                Layout.fillWidth:true; label:"Розмір інтерфейсу"; description:root.category === "topPanel" ? "Додатковий множник до масштабу за фізичною діагоналлю: 24″ — 1×, приблизно 27″ — 1,13×. Якщо монітор не повідомляє розмір — 1×." : "Менше ← → Більше. Автоматично підлаштовується до монітора; цей масштаб стосується лише поточного компонента."
                unit:"%"; minimum:60; maximum:160; step:5; value:Math.round((root.options.uiScale ?? 1)*100)
                onEdited: number => root.setField("uiScale",number/100)
            }
            DankButton { Layout.fillWidth:true; visible:root.category !== "topPanel"; text:"Переглянути"; onClicked:root.preview() }
            Text { Layout.fillWidth:true; visible:root.category !== "topPanel"; text:"Повернення до цих налаштувань — шестерня в селекторі. Завеликі картки підлаштовуються до екрана без зміни збережених чисел."; wrapMode:Text.WordWrap; color:Theme.surfaceTextSecondary; font.pixelSize:12 }
            DankDropdown {
                Layout.fillWidth:true; visible:root.category === "switcher"; text:"Вигляд селектора Alt+Tab"
                options:["Радіальний","Картки","Сітка","Компактний"]
                currentValue:({wheel:"Радіальний",slice:"Картки",grid:"Сітка",compact:"Компактний"})[root.mode] || "Радіальний"
                onValueChanged: value => root.setField("displayMode",({"Радіальний":"wheel","Картки":"slice","Сітка":"grid","Компактний":"compact"})[value])
            }
            Repeater {
                model: root.fields
                delegate: GlassValueControl {
                    required property var modelData
                    Layout.fillWidth:true
                    label:modelData.label; description:modelData.description || ""
                    unit:modelData.unit ?? "px"; minimum:modelData.min; maximum:modelData.max
                    value:Number(root.options[modelData.key] ?? modelData.value)
                    onEdited: number => root.setField(modelData.key,number)
                }
            }
            Repeater {
                model: root.category === "topPanel" ? [] : [
                    {key:"dimOpacity",label:"Затемнення за селектором",description:"Затемнює робочий стіл позаду всіх карток.",value:.3},
                    {key:"inactiveDimOpacity",label:"Затемнення невибраних карток",description:"Виділена картка залишається яскравою.",value:.3}
                ]
                delegate: GlassValueControl {
                    required property var modelData
                    Layout.fillWidth:true; label:modelData.label; description:modelData.description; unit:"%"; minimum:0; maximum:90
                    value:Math.round(Number(root.options[modelData.key] ?? modelData.value)*100)
                    onEdited: number => root.setField(modelData.key,number/100)
                }
            }
            GlassValueControl { Layout.fillWidth:true; visible:root.category === "switcher"; label:"Розмиття прев’ю столів"; description:"Розмиває зображення кожного стола, не його підписи."; minimum:0; maximum:32; value:root.options.previewBlur ?? 0; onEdited:number => root.setField("previewBlur",number) }
            GlassValueControl { Layout.fillWidth:true; visible:root.category === "switcher"; label:"Збільшення при наведенні"; unit:"%"; minimum:100; maximum:120; value:Math.round((root.options.hoverScale ?? 1.06)*100); onEdited:number => root.setField("hoverScale",number/100) }
            ColumnLayout {
                Layout.fillWidth:true; visible:root.category === "wallpaperSelector"
                Text { Layout.fillWidth:true; text:"Каталог шпалер"; color:Theme.surfaceText; wrapMode:Text.WordWrap }
                DankTextField { Layout.fillWidth:true; text:root.options.directory || ""; placeholderText:"Порожньо — каталог поточних шпалер"; Accessible.name:"Каталог шпалер"; onEditingFinished:root.setField("directory",text.trim()) }
                DankButton {
                    Layout.fillWidth: true
                    text: "Вибрати теку…"
                    onClicked: root.pluginService?.setGlobalVar(root.pluginId,"request",{kind:"wallpaperFolder",screen:""})
                }
            }
            ColumnLayout {
                Layout.fillWidth:true; visible:root.carousel
                Text { text:"Збережені розміри карток"; color:Theme.surfaceText; font.bold:true }
                Flow {
                    Layout.fillWidth:true; spacing:6
                    Repeater {
                        model:[{name:"XS",w:360,h:200,s:52},{name:"S",w:480,h:270,s:68},{name:"M",w:768,h:432,s:108},{name:"L",w:924,h:520,s:135},{name:"XL",w:1280,h:720,s:180}]
                        delegate:DankButton { required property var modelData; text:modelData.name; onClicked:root.patch(root.category,{sliceWidth:modelData.s,sliceHeight:modelData.h,expandedWidth:modelData.w,expandedHeight:modelData.h}) }
                    }
                }
                Repeater {
                    model:["A","B","C","D","E"]
                    delegate:RowLayout {
                        required property string modelData
                        Layout.fillWidth:true
                        Text { text:modelData; color:Theme.surfaceText }
                        DankButton { Layout.fillWidth:true; text:"Застосувати"; enabled:!!root.options.customPresets?.[modelData+"_slice"]; onClicked:root.preset(modelData,false) }
                        DankButton { Layout.fillWidth:true; text:"Зберегти"; onClicked:root.preset(modelData,true) }
                    }
                }
            }
            LauncherSettings {
                Layout.fillWidth:true; visible:root.category === "launcher"
                settings:({launcher:root.data.launcher || {},appOverrides:root.data.appOverrides || {},paths:root.data.paths || {},terminal:root.data.terminal || "kitty"})
                applications:root.applications.length ? root.applications : DesktopEntries.applications.values.filter(a => a && a.name && !a.hidden && !a.noDisplay).map(a => ({name:a.name,id:a.id,icon:a.icon}))
                onConfigurationChanged:patch => root.launcherPatch(patch)
            }
            ColumnLayout {
                Layout.fillWidth:true; visible:root.category === "topPanel"
                Text { Layout.fillWidth:true; text:"Автоховання"; color:Theme.surfaceText; font.bold:true }
                Text { Layout.fillWidth:true; text:"Окремо для кожного монітора. Для відкриття прихованої панелі підведіть курсор до верхнього краю."; color:Theme.surfaceTextSecondary; wrapMode:Text.WordWrap }
                Repeater {
                    model: Quickshell.screens
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text { Layout.fillWidth:true; text:modelData.name; color:Theme.surfaceText }
                        DankToggle {
                            checked: root.options.autoHideScreens?.[modelData.name] === true
                            Accessible.name: "Автоховання моноброви на " + modelData.name
                            onToggled: root.setAutoHide(modelData.name, checked)
                        }
                    }
                }
                DankButton { Layout.fillWidth:true; text:"Перетягнути елементи на моноброві"; onClicked:root.pluginService?.setGlobalVar(root.pluginId,"topPanelEdit",true) }
                Text { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:"У режимі редагування перетягніть елемент. Escape скасовує перетягування; повторний Escape завершує редагування. Або змініть порядок кнопками нижче."; color:Theme.surfaceTextSecondary; font.pixelSize:12 }
                Repeater {
                    model:root.lanes
                    delegate:ColumnLayout {
                        id: laneEditor
                        required property var modelData
                        Layout.fillWidth:true
                        Text { Layout.fillWidth:true; text:laneEditor.modelData.name; color:Theme.primary; font.bold:true; wrapMode:Text.WordWrap }
                        Repeater {
                            model:root.data.topPanel?.[laneEditor.modelData.key] || root.defaultPanel[laneEditor.modelData.key]
                            delegate:ColumnLayout {
                                required property string modelData
                                Layout.fillWidth:true
                                RowLayout {
                                    Layout.fillWidth:true
                                    Text { Layout.fillWidth:true; text:root.widgetNames[modelData] || modelData; color:Theme.surfaceText; wrapMode:Text.WordWrap }
                                    DankButton { text:"↑"; Accessible.name:"Перемістити вище: " + modelData; onClicked:root.moveWidget(modelData,laneEditor.modelData.key,-1) }
                                    DankButton { text:"↓"; Accessible.name:"Перемістити нижче: " + modelData; onClicked:root.moveWidget(modelData,laneEditor.modelData.key,1) }
                                }
                                DankDropdown {
                                    Layout.fillWidth:true; text:""; Accessible.name:"Блок для " + (root.widgetNames[modelData] || modelData); options:root.lanes.map(l => l.name); currentValue:laneEditor.modelData.name
                                    onValueChanged:value => { const lane = root.lanes.find(l => l.name === value); if(lane) root.moveWidget(modelData,lane.key,0); }
                                }
                            }
                        }
                    }
                }
                DankButton { Layout.fillWidth:true; text:"Відновити початковий порядок"; onClicked:root.patch("topPanel",{left:root.defaultPanel.left,centerBeforeClock:root.defaultPanel.centerBeforeClock,centerAfterClock:root.defaultPanel.centerAfterClock,right:root.defaultPanel.right}) }
            }
        }
    }
}
