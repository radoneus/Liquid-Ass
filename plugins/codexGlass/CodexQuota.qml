import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Item {
    id: root
    property real scaleFactor: 1
    property real remaining: NaN
    property real used: NaN
    property real fetchedAt: NaN
    property real resetsAt: NaN
    property real resetCredits: NaN
    property string problem: "Завантаження…"
    property bool timedOut: false
    property real now: Date.now()
    readonly property bool stale: !isFinite(fetchedAt) || now - fetchedAt > 30 * 60000 || now < fetchedAt - 60000
    readonly property bool valid: isFinite(remaining) && isFinite(resetsAt) && resetsAt > now && !stale && !problem
    readonly property real resetHours: Math.max(0, Math.floor((resetsAt - now) / 3600000))
    readonly property string resetLabel: Math.floor(resetHours / 24) + "d" + (resetHours % 24) + "h"
    readonly property color good: "#86c88f"
    readonly property color caution: "#e9c46a"
    readonly property color bad: "#e77878"
    readonly property string tooltipText: {
        if (problem) return "Codex: " + problem;
        if (stale || !valid) return "Codex: дані застаріли або час скидання минув. Очікування оновлення OMP.";
        return "Codex · тижневий ліміт\nЗалишилось: " + Math.round(remaining) + "% · використано: "
            + Math.round(used) + "%\nДо скидання: " + resetLabel + " (" + Qt.formatDateTime(new Date(resetsAt), "dd.MM hh:mm") + ")"
            + "\nДоступних reset credits: " + (isFinite(resetCredits) ? resetCredits : "невідомо")
            + "\nОновлено: " + age(fetchedAt);
    }
    implicitWidth: values.implicitWidth
    implicitHeight: values.implicitHeight
    function age(timestamp) {
        const minutes = Math.max(0, Math.floor((now - timestamp) / 60000));
        return minutes < 1 ? "щойно" : minutes < 60 ? minutes + " хв тому" : Math.floor(minutes / 60) + " год тому";
    }
    function refresh() {
        if (usage.running) return;
        timedOut = false;
        deadline.restart();
        usage.running = true;
    }
    function parseResult(text) {
        const data = JSON.parse(text);
        const report = (data.reports || []).find(item => item.provider === "openai-codex");
        const limit = (report?.limits || []).find(item => item.window?.id === "7d" && item.status === "ok");
        const amount = limit?.amount;
        const left = Number(amount?.remainingFraction);
        const spent = Number(amount?.usedFraction);
        const stamp = Number(report?.fetchedAt);
        const reset = Number(limit?.window?.resetsAt);
        const credits = report?.resetCredits?.availableCount;
        if (!amount || !isFinite(left) || !isFinite(spent) || left < 0 || left > 1 || spent < 0 || spent > 1
                || !isFinite(stamp) || stamp <= 0 || !isFinite(reset) || reset <= Date.now())
            throw new Error("немає актуального тижневого ліміту в OMP");
        remaining = left * 100;
        used = spent * 100;
        fetchedAt = stamp;
        resetsAt = reset;
        resetCredits = Number.isInteger(credits) && credits >= 0 ? credits : NaN;
        problem = "";
    }
    Component.onCompleted: refresh()
    Component.onDestruction: { deadline.stop(); usage.running = false; }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: { root.now = Date.now(); root.refresh(); } }
    Timer {
        id: deadline
        interval: 12000
        onTriggered: { root.timedOut = true; usage.running = false; root.problem = "OMP не відповідає"; }
    }
    Process {
        id: usage
        command: [(Quickshell.env("HOME") || "") + "/.local/bin/omp", "usage", "--provider", "openai-codex", "--redact", "--json"]
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            deadline.stop();
            if (root.timedOut) return;
            if (code !== 0) { root.problem = "не вдалося отримати дані OMP"; return; }
            try { root.parseResult(output.text); }
            catch (error) { root.problem = "немає коректного тижневого ліміту"; }
            root.now = Date.now();
        }
    }
    Row {
        id: values
        spacing: 6 * root.scaleFactor
        anchors.centerIn: parent
        Text {
            text: root.valid ? Math.round(root.remaining) + "%" : "—%"
            color: !root.valid ? Theme.surfaceVariantText : root.remaining >= 70 ? root.good : root.remaining >= 30 ? root.caution : root.bad
            font.pixelSize: 12 * root.scaleFactor
        }
        Text {
            text: root.valid ? root.resetLabel : "—"
            color: !root.valid ? Theme.surfaceVariantText : root.resetHours <= 48 ? root.good : root.resetHours <= 120 ? root.caution : root.bad
            font.pixelSize: 12 * root.scaleFactor
        }
        Text {
            text: root.valid && isFinite(root.resetCredits) ? root.resetCredits + "R" : "—R"
            color: !root.valid || !isFinite(root.resetCredits) ? Theme.surfaceVariantText
                : root.resetCredits >= 2 ? root.good : root.resetCredits === 1 ? root.caution : root.bad
            font.pixelSize: 12 * root.scaleFactor
        }
    }
}
