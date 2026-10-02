pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    readonly property var defaults: ({
            debounceDelay: 300,
            virshBinary: "virsh",
            libvirtUri: "qemu:///system",
            viewerCommand: "virt-viewer",
            pollingInterval: 0
        })

    readonly property string pluginId: "virtManager"

    // libvirt domain states (virDomainState)
    readonly property var stateLabels: ({
            0: "No state",
            1: "Running",
            2: "Blocked",
            3: "Paused",
            4: "Shutting down",
            5: "Shut off",
            6: "Crashed",
            7: "Suspended"
        })

    property bool systemdRunAvailable: false
    property bool libvirtAvailable: false
    property int debounceDelay: defaults.debounceDelay
    property string virshBinary: defaults.virshBinary
    property string libvirtUri: defaults.libvirtUri
    property string viewerCommand: defaults.viewerCommand
    property int pollingInterval: defaults.pollingInterval

    function loadSettings() {
        const load = key => PluginService.loadPluginData(pluginId, key) || defaults[key];
        debounceDelay = load("debounceDelay");
        virshBinary = load("virshBinary");
        libvirtUri = load("libvirtUri");
        viewerCommand = load("viewerCommand");
        pollingInterval = load("pollingInterval");

        refresh();
    }

    Component.onCompleted: {
        loadSettings();
        initialize();
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === root.pluginId) {
                loadSettings();
            }
        }
    }

    function virshCommand(args) {
        return ["env", "LC_ALL=C", virshBinary, "-c", libvirtUri, ...args];
    }

    function restartEvents() {
        eventsProcess.running = false;
        eventsProcess.command = virshCommand(["event", "--all", "--loop"]);
        eventsProcess.running = true;
    }

    onVirshBinaryChanged: restartEvents()
    onLibvirtUriChanged: restartEvents()

    property var debounceTimer: Timer {
        interval: root.debounceDelay
        running: false
        repeat: false
        onTriggered: fetchVms()
    }

    property var eventsProcess: Process {
        command: root.virshCommand(["event", "--all", "--loop"])
        running: false

        stdout: SplitParser {
            onRead: data => {
                // e.g. "event 'lifecycle' for domain 'win11': Started Booted"
                if (/^event '(lifecycle|reboot|pm-suspend|pm-wakeup|pmsuspend|pmwakeup)'/.test(data)) {
                    console.log(`VirtManager: Domain event detected - ${data}`);
                    debounceTimer.restart();
                }
            }
        }

        onRunningChanged: {
            if (!running) {
                console.log("VirtManager: virsh event process not running");
                restartTimer.start();
            }
        }
    }

    property var restartTimer: Timer {
        interval: 5000
        running: false
        repeat: false
        onTriggered: {
            if (libvirtAvailable) {
                console.log("VirtManager: Attempting to restart events listener...");
                eventsProcess.running = true;
            } else {
                root.refresh();
            }
        }
    }

    property var pollingTimer: Timer {
        interval: Math.max(root.pollingInterval, 1000)
        running: root.libvirtAvailable && root.pollingInterval > 0
        repeat: true
        onTriggered: fetchVms()
    }

    function initialize() {
        Proc.runCommand(`${pluginId}.systemdRunCheck`, ["which", "systemd-run"], (stdout, exitCode) => {
            systemdRunAvailable = exitCode === 0;
        }, 100);

        refresh();

        eventsProcess.running = true;
    }

    function refresh() {
        Proc.runCommand(`${pluginId}.libvirtCheck`, virshCommand(["uri"]), (stdout, exitCode) => {
            const wasAvailable = root.libvirtAvailable;
            root.libvirtAvailable = exitCode === 0;
            PluginService.setGlobalVar(pluginId, "libvirtAvailable", libvirtAvailable);
            if (libvirtAvailable) {
                if (!wasAvailable && !eventsProcess.running)
                    eventsProcess.running = true;
                fetchVms();
            } else {
                updateVms();
            }
        }, 100);
    }

    function fetchVms() {
        // Positional args avoid any quoting issue with the binary or the URI.
        const script = 'export LC_ALL=C\n' + '"$1" -c "$2" domstats --state --balloon --vcpu | grep -v "^ *vcpu\\.[0-9]"\n' + 'echo ---MANAGEDSAVE---\n' + '"$1" -c "$2" list --all --with-managed-save --name';

        Proc.runCommand(`${pluginId}.fetchVms`, ["sh", "-c", script, "sh", virshBinary, libvirtUri], (stdout, exitCode) => {
            if (exitCode !== 0) {
                updateVms();
                return;
            }
            try {
                const parts = stdout.split("---MANAGEDSAVE---");
                const saved = new Set((parts[1] || "").split("\n").map(s => s.trim()).filter(s => s.length > 0));
                const vms = [];
                let current = null;

                (parts[0] || "").split("\n").forEach(line => {
                    const header = line.match(/^Domain: '(.*)'$/);
                    if (header) {
                        current = {
                            name: header[1],
                            stats: {}
                        };
                        vms.push(current);
                        return;
                    }
                    const kv = line.trim().match(/^([^=]+)=(.*)$/);
                    if (current && kv)
                        current.stats[kv[1]] = kv[2];
                });

                const result = vms.map(vm => {
                    const state = parseInt(vm.stats["state.state"] ?? "0");
                    const memKiB = parseInt(vm.stats["balloon.maximum"] ?? vm.stats["balloon.current"] ?? "0");
                    const isRunning = state === 1 || state === 2;
                    const isPaused = state === 3;
                    const isSuspended = state === 7;
                    const isActive = isRunning || isPaused || isSuspended || state === 4;
                    const hasSavedState = saved.has(vm.name);
                    return {
                        id: vm.name,
                        name: vm.name,
                        state: state,
                        status: !isActive && hasSavedState ? "Saved" : (stateLabels[state] || "Unknown"),
                        isRunning: isRunning,
                        isPaused: isPaused,
                        isSuspended: isSuspended,
                        isShuttingDown: state === 4,
                        isActive: isActive,
                        hasSavedState: hasSavedState,
                        vcpus: parseInt(vm.stats["vcpu.current"] ?? "0"),
                        memoryGiB: Math.round(memKiB / 1048576 * 10) / 10
                    };
                }).sort((a, b) => {
                    const priority = vm => vm.isRunning ? 1 : (vm.isPaused || vm.isSuspended || vm.isShuttingDown) ? 2 : vm.hasSavedState ? 3 : 4;
                    const pa = priority(a), pb = priority(b);
                    if (pa !== pb)
                        return pa - pb;
                    return a.name.localeCompare(b.name);
                });

                updateVms(result, result.filter(vm => vm.isActive).length);
            } catch (e) {
                console.error("VirtManager: Failed to parse virsh output:", e);
                updateVms();
            }
        }, 100);
    }

    function updateVms(vms = [], runningVms = 0) {
        PluginService.setGlobalVar(pluginId, "vms", vms);
        PluginService.setGlobalVar(pluginId, "runningVms", runningVms);
    }

    readonly property var actions: ({
            start: {
                args: ["start"],
                label: "Starting"
            },
            pause: {
                args: ["suspend"],
                label: "Pausing"
            },
            resume: {
                args: ["resume"],
                label: "Resuming"
            },
            wakeup: {
                args: ["dompmwakeup"],
                label: "Waking up"
            },
            shutdown: {
                args: ["shutdown"],
                label: "Shutting down"
            },
            reboot: {
                args: ["reboot"],
                label: "Rebooting"
            },
            reset: {
                args: ["reset"],
                label: "Force rebooting"
            },
            destroy: {
                args: ["destroy"],
                label: "Force stopping"
            },
            save: {
                args: ["managedsave"],
                label: "Saving state of"
            },
            discardSave: {
                args: ["managedsave-remove"],
                label: "Discarding saved state of"
            }
        })

    function executeAction(vmName, action) {
        const def = actions[action];
        if (!def)
            return false;

        ToastService.showInfo(`${def.label} ${vmName}`);
        const cmd = ["sh", "-c", 'exec "$@" 2>&1', "sh", ...virshCommand([...def.args, vmName])];
        // managedsave/shutdown can take a long time: no timeout.
        Proc.runCommand(`${pluginId}.action.${action}.${vmName}`, cmd, (output, exitCode) => {
            if (exitCode !== 0) {
                const msg = output.trim().replace(/^error: /gm, "") || `exit code ${exitCode}`;
                ToastService.showError(`VM ${vmName}: ${action} failed`, msg);
            }
            root.fetchVms();
        }, 0, -1);
        return true;
    }

    function openViewer(vmName) {
        const viewer = viewerCommand.trim().split(/\s+/).filter(s => s.length > 0);
        const cmd = [...viewer, "--connect", libvirtUri, "--wait", vmName];
        Quickshell.execDetached(systemdRunAvailable ? ["systemd-run", "--user", "--scope", "--", ...cmd] : cmd);
    }
}
