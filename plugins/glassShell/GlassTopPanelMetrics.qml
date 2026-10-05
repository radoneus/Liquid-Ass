import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import qs.Common

Item {
    id: root
    readonly property bool available: DgopService.dgopAvailable && DgopService.refCount > 0
    readonly property real cpu: available ? DgopService.cpuUsage : NaN
    readonly property real cpuTemperature: available && DgopService.cpuTemperature > 0 ? DgopService.cpuTemperature : NaN
    readonly property real memoryBytes: available ? DgopService.usedMemoryMB * 1048576 : NaN
    readonly property real totalMemoryBytes: available ? DgopService.totalMemoryMB * 1048576 : NaN
    readonly property real rx: available ? DgopService.networkRxRate : NaN
    readonly property real tx: available ? DgopService.networkTxRate : NaN
    property real gpu: NaN
    property real gpuTemperature: NaN
    property real vramBytes: NaN
    property real totalVramBytes: NaN
    // nvidia-smi accepts a GPU index, UUID or PCI bus ID; select one per machine.
    property string gpuId: Quickshell.env("GLASS_GPU_ID") || ""
    property bool inFlight: false
    property bool expired: false
    function invalidateGpu() {
        gpu = NaN;
        gpuTemperature = NaN;
        vramBytes = NaN;
        totalVramBytes = NaN;
    }
    function parseField(field) {
        const value = String(field || "").trim();
        return /^(?:\d+(?:\.\d+)?|\.\d+)$/.test(value) ? Number(value) : NaN;
    }
    function sample() {
        if (inFlight || !gpuId) return;
        gpuProcess.command = ["nvidia-smi", "--id=" + gpuId,
                              "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                              "--format=csv,noheader,nounits"];
        expired = false;
        inFlight = true;
        gpuDeadline.restart();
        gpuProcess.running = true;
    }
    Component.onCompleted: {
        DgopService.addRef(["cpu", "memory", "network"]);
        sample();
    }
    Component.onDestruction: {
        gpuDeadline.stop();
        gpuProcess.running = false;
        DgopService.removeRef(["cpu", "memory", "network"]);
    }
    onGpuIdChanged: {
        invalidateGpu();
        if (!inFlight) sample();
    }
    Timer { interval: 2000; running: true; repeat: true; onTriggered: root.sample() }
    Timer {
        id: gpuDeadline
        interval: 3000
        onTriggered: {
            root.expired = true;
            root.invalidateGpu();
            gpuProcess.running = false;
        }
    }
    Process {
        id: gpuProcess
        running: false
        stdout: StdioCollector { id: gpuOutput }
        onExited: (exitCode, exitStatus) => {
            gpuDeadline.stop();
            root.inFlight = false;
            if (root.expired || exitCode !== 0) { root.invalidateGpu(); return; }
            const fields = gpuOutput.text.trim().split(",");
            if (fields.length !== 4) { root.invalidateGpu(); return; }
            root.gpu = root.parseField(fields[0]);
            root.gpuTemperature = root.parseField(fields[1]);
            const used = root.parseField(fields[2]);
            const total = root.parseField(fields[3]);
            root.vramBytes = isFinite(used) ? used * 1048576 : NaN;
            root.totalVramBytes = isFinite(total) ? total * 1048576 : NaN;
        }
    }
}
