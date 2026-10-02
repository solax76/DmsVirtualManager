import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var expandedVms: ({})
    property bool showDetails: pluginData.showDetails ?? true
    property bool autoScrollOnExpand: pluginData.autoScrollOnExpand ?? true

    property string selectedVm: ""
    property int selectedActionIndex: -1
    property bool keyboardNavigationActive: false
    property var vmListView: null

    // "<vm>:<action>" of a destructive action waiting for a second click
    property string pendingConfirmKey: ""

    Timer {
        id: confirmTimer
        interval: 3000
        repeat: false
        onTriggered: root.pendingConfirmKey = ""
    }

    Timer {
        id: scrollTimer
        interval: 16
        repeat: true
        property int iterations: 0
        property int maxIterations: Math.ceil((Theme.expressiveDurations["expressiveFastSpatial"] ?? 300) / interval) + 1
        onTriggered: {
            if (++iterations >= maxIterations) {
                stop();
                iterations = 0;
            }
            ensureVisible();
        }
        function restart() {
            iterations = 0;
            maxIterations = Math.ceil((Theme.expressiveDurations["expressiveFastSpatial"] ?? 300) / interval);
            start();
        }
    }

    Component.onCompleted: {
        // Note: referencing VirtService here is necessary because Singletons are lazy-loaded in QML.
        console.log(VirtService.pluginId, "loaded.");
    }

    PluginGlobalVar {
        id: globalLibvirtAvailable
        varName: "libvirtAvailable"
        defaultValue: false
    }

    PluginGlobalVar {
        id: globalVms
        varName: "vms"
        defaultValue: []
    }

    PluginGlobalVar {
        id: globalRunningVms
        varName: "runningVms"
        defaultValue: 0
    }

    // Single source of truth for the per-VM actions, used by both the UI and keyboard navigation.
    // Only the actions available in the current VM state are returned.
    function vmActions(vm) {
        if (!vm)
            return [];
        const pauseAction = vm.isSuspended ? {
            key: "wakeup",
            text: "Wake Up",
            icon: "wb_sunny"
        } : vm.isPaused ? {
            key: "resume",
            text: "Resume",
            icon: "play_arrow"
        } : {
            key: "pause",
            text: "Pause",
            icon: "pause"
        };
        return [
            {
                key: "viewer",
                text: "Open Viewer",
                icon: "desktop_windows",
                enabled: true
            },
            {
                key: "start",
                text: vm.hasSavedState ? "Restore" : "Start",
                icon: vm.hasSavedState ? "restore" : "play_arrow",
                enabled: !vm.isActive
            },
            Object.assign(pauseAction, {
                enabled: vm.isRunning || vm.isPaused || vm.isSuspended
            }),
            {
                key: "shutdown",
                text: "Shut Down",
                icon: "power_settings_new",
                enabled: vm.isRunning
            },
            {
                key: "reboot",
                text: "Reboot",
                icon: "restart_alt",
                enabled: vm.isRunning
            },
            {
                key: "reset",
                text: "Force Reboot",
                icon: "autorenew",
                enabled: vm.isRunning || vm.isPaused,
                destructive: true
            },
            {
                key: "destroy",
                text: "Force Stop",
                icon: "stop",
                enabled: vm.isActive,
                destructive: true
            },
            {
                key: "save",
                text: "Save State",
                icon: "save",
                enabled: vm.isRunning || vm.isPaused
            },
            {
                key: "discardSave",
                text: "Discard Saved State",
                icon: "delete",
                enabled: !vm.isActive && vm.hasSavedState,
                destructive: true
            }
        ].filter(action => action.enabled);
    }

    function triggerAction(vm, action) {
        if (!vm || !action || !action.enabled)
            return;

        const confirmKey = `${vm.name}:${action.key}`;
        if (action.destructive && pendingConfirmKey !== confirmKey) {
            pendingConfirmKey = confirmKey;
            confirmTimer.restart();
            return;
        }
        pendingConfirmKey = "";
        confirmTimer.stop();

        if (action.key === "viewer")
            VirtService.openViewer(vm.name);
        else
            VirtService.executeAction(vm.name, action.key);
    }

    function toggleVm(vmName) {
        const wasExpanded = root.expandedVms[vmName] || false;
        const expanded = root.expandedVms;
        expanded[vmName] = !expanded[vmName];
        root.expandedVms = expanded;
        root.expandedVmsChanged();

        if (!wasExpanded && !keyboardNavigationActive && autoScrollOnExpand) {
            selectedVm = vmName;
            scrollTimer.restart();
        }
    }

    function getSelectedIndex() {
        return selectedVm ? globalVms.value.findIndex(vm => vm.name === selectedVm) : -1;
    }

    function selectedVmData() {
        const idx = getSelectedIndex();
        return idx >= 0 ? globalVms.value[idx] : null;
    }

    function ensureValidSelection() {
        const list = globalVms.value;
        if (!list.length) {
            selectedVm = "";
            return;
        }
        if (getSelectedIndex() === -1)
            selectedVm = list[0].name;
    }

    function findEnabledAction(fromIndex, step) {
        const actions = vmActions(selectedVmData());
        for (let i = fromIndex + step; i >= 0 && i < actions.length; i += step) {
            if (actions[i].enabled)
                return i;
        }
        return -1;
    }

    function selectNext() {
        const list = globalVms.value;
        if (!list.length)
            return;

        if (!keyboardNavigationActive) {
            keyboardNavigationActive = true;
            ensureValidSelection();
            return;
        }

        if (selectedActionIndex >= 0) {
            const next = findEnabledAction(selectedActionIndex, 1);
            if (next >= 0) {
                selectedActionIndex = next;
                return;
            }
            selectedActionIndex = -1;
        }

        const idx = getSelectedIndex();
        if (idx >= list.length - 1)
            return;
        selectedVm = list[idx + 1].name;
        ensureVisible();
    }

    function selectPrevious() {
        const list = globalVms.value;
        if (!list.length)
            return;

        if (!keyboardNavigationActive) {
            keyboardNavigationActive = true;
            ensureValidSelection();
            return;
        }

        if (selectedActionIndex >= 0) {
            const prev = findEnabledAction(selectedActionIndex, -1);
            if (prev >= 0) {
                selectedActionIndex = prev;
                return;
            }
            selectedActionIndex = -1;
            ensureVisible();
            return;
        }

        const idx = getSelectedIndex();
        if (idx <= 0)
            return;
        selectedVm = list[idx - 1].name;
        ensureVisible();
    }

    function toggleSelected() {
        if (!selectedVm)
            return;

        if (selectedActionIndex >= 0) {
            const vm = selectedVmData();
            triggerAction(vm, vmActions(vm)[selectedActionIndex]);
            return;
        }

        const wasExpanded = expandedVms[selectedVm] || false;
        toggleVm(selectedVm);
        !wasExpanded && autoScrollOnExpand ? scrollTimer.restart() : Qt.callLater(ensureVisible);
    }

    function enterActions() {
        if (!selectedVm || selectedActionIndex >= 0)
            return;
        if (!expandedVms[selectedVm])
            toggleSelected();
        selectedActionIndex = findEnabledAction(-1, 1);
        if (selectedActionIndex < 0)
            selectedActionIndex = 0;
        ensureVisible();
    }

    function exitActions() {
        if (selectedActionIndex >= 0) {
            selectedActionIndex = -1;
            ensureVisible();
            return;
        }
        if (expandedVms[selectedVm])
            toggleVm(selectedVm);
    }

    function ensureVisible() {
        if (!selectedVm || !vmListView)
            return;
        Qt.callLater(() => {
            const index = getSelectedIndex();
            if (index >= 0)
                vmListView.positionViewAtIndex(index, ListView.Contain);
        });
    }

    function stateColor(vm) {
        if (!vm)
            return Theme.surfaceText;
        if (vm.state === 6)
            return Theme.error;
        if (vm.isPaused || vm.isSuspended || vm.isShuttingDown)
            return Theme.warning;
        if (vm.isRunning)
            return Theme.primary;
        if (vm.hasSavedState)
            return Theme.secondary;
        return Theme.surfaceText;
    }

    component VmIcon: DankIcon {
        name: "computer"
        size: root.iconSize
        color: {
            if (!globalLibvirtAvailable.value)
                return Theme.error;
            if (globalRunningVms.value > 0)
                return Theme.primary;
            return Theme.widgetIconColor || Theme.surfaceText;
        }
    }

    component VmCount: StyledText {
        text: globalRunningVms.value.toString()
        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
        color: Theme.widgetTextColor || Theme.surfaceText
        visible: globalRunningVms.value > 0
    }

    component VmHeader: StyledRect {
        id: vmHeader
        property var vmData: null
        property bool isExpanded: false
        property bool isCurrentItem: false
        property real baseHeight: 48
        signal clicked

        width: parent.width
        height: baseHeight
        radius: Theme.cornerRadius
        color: (isCurrentItem || headerMouse.containsMouse) ? Theme.surfaceHover : "transparent"
        border.width: 0

        DankIcon {
            id: vmIcon
            name: vmData?.hasSavedState && !vmData?.isActive ? "save" : "computer"
            size: Theme.iconSize
            color: root.stateColor(vmData)
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.left: vmIcon.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: expandIcon.left
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            StyledText {
                text: vmData?.name || ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                width: parent.width
            }

            StyledText {
                text: {
                    if (!vmData)
                        return "";
                    const parts = [vmData.status];
                    if (root.showDetails) {
                        if (vmData.vcpus > 0)
                            parts.push(`${vmData.vcpus} vCPU`);
                        if (vmData.memoryGiB > 0)
                            parts.push(`${vmData.memoryGiB} GiB`);
                    }
                    return parts.join(" • ");
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                width: parent.width
            }
        }

        DankIcon {
            id: expandIcon
            name: isExpanded ? "expand_less" : "expand_more"
            size: Theme.iconSize
            color: Theme.surfaceText
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.keyboardNavigationActive = false;
                vmHeader.clicked();
            }
        }
    }

    component VmActions: Column {
        id: vmActionsPart
        property var vmData: null
        property real leftIndent: Theme.spacingL + Theme.spacingM
        property bool isExpanded: false
        property bool isCurrentItem: false

        width: parent.width
        spacing: 0
        clip: true

        height: isExpanded ? actionsColumn.height : 0
        opacity: isExpanded ? 1 : 0

        Behavior on height {
            NumberAnimation {
                duration: Theme.expressiveDurations["expressiveFastSpatial"]
                easing.type: Theme.standardEasing
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations["expressiveEffects"]
                easing.type: Theme.standardEasing
            }
        }

        Column {
            id: actionsColumn
            width: parent.width
            spacing: 0

            Repeater {
                model: root.vmActions(vmActionsPart.vmData)

                ActionButton {
                    required property var modelData
                    required property int index

                    text: modelData.text
                    icon: modelData.icon
                    enabled: modelData.enabled
                    destructive: modelData.destructive || false
                    awaitingConfirm: root.pendingConfirmKey === `${vmActionsPart.vmData?.name}:${modelData.key}`
                    isSelected: vmActionsPart.isCurrentItem && root.selectedActionIndex === index
                    leftIndent: vmActionsPart.leftIndent
                    onTriggered: root.triggerAction(vmActionsPart.vmData, modelData)
                }
            }
        }
    }

    horizontalBarPill: Row {
        spacing: Theme.spacingXS

        VmIcon {
            anchors.verticalCenter: parent.verticalCenter
        }

        VmCount {
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    verticalBarPill: Column {
        spacing: Theme.spacingXS

        VmIcon {
            anchors.horizontalCenter: parent.horizontalCenter
        }

        VmCount {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    popoutContent: Component {
        FocusScope {
            implicitWidth: popoutColumn.implicitWidth
            implicitHeight: popoutColumn.implicitHeight
            focus: true

            property var parentPopout: null
            Connections {
                target: parentPopout
                function onOpened() {
                    VirtService.refresh();
                    Qt.callLater(() => {
                        forceActiveFocus();
                    });
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier) || (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier) || event.key === Qt.Key_Tab) {
                    root.selectNext();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier) || (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier) || event.key === Qt.Key_Backtab) {
                    root.selectPrevious();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    root.toggleSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || (event.key === Qt.Key_L && event.modifiers & Qt.ControlModifier)) {
                    root.enterActions();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_H && event.modifiers & Qt.ControlModifier)) {
                    root.exitActions();
                    event.accepted = true;
                } else if (event.key === Qt.Key_R && !(event.modifiers & Qt.ControlModifier)) {
                    VirtService.refresh();
                    event.accepted = true;
                }
            }

            Column {
                id: popoutColumn
                spacing: 0
                width: parent.width

                Rectangle {
                    width: parent.width
                    height: 46
                    color: "transparent"

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: refreshButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!globalLibvirtAvailable.value)
                                return "libvirt not available";
                            const n = globalRunningVms.value;
                            return `${n} running VM${n !== 1 ? "s" : ""}`;
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    HeaderButton {
                        id: refreshButton
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "refresh"
                        onClicked: VirtService.refresh()
                    }
                }

                Item {
                    width: parent.width
                    height: root.popoutHeight - 46 - Theme.spacingXL

                    StyledText {
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingL * 2
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: globalVms.value.length === 0
                        text: globalLibvirtAvailable.value ? "No virtual machines found" : `Cannot connect to ${VirtService.libvirtUri}.\nCheck that libvirtd is running and your user is in the 'libvirt' group.`
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                    }

                    DankListView {
                        id: vmList
                        anchors.fill: parent
                        topMargin: 0
                        bottomMargin: Theme.spacingS
                        leftMargin: Theme.spacingM
                        rightMargin: Theme.spacingM
                        spacing: Theme.spacingS
                        clip: true
                        model: globalVms.value
                        currentIndex: root.keyboardNavigationActive ? root.getSelectedIndex() : -1

                        Component.onCompleted: {
                            root.vmListView = vmList;
                        }

                        delegate: StyledRect {
                            id: vmDelegate
                            required property var modelData

                            width: vmList.width - vmList.leftMargin - vmList.rightMargin
                            radius: Theme.cornerRadius
                            Component.onCompleted: height = Qt.binding(() => vmHeaderPart.height + vmActionsPart.height)
                            color: isCurrentItem ? Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                            border.width: 1
                            border.color: {
                                if (modelData.isRunning || modelData.isPaused || modelData.isSuspended || modelData.isShuttingDown || modelData.hasSavedState || modelData.state === 6) {
                                    const c = root.stateColor(modelData);
                                    return Qt.rgba(c.r, c.g, c.b, 0.5);
                                }
                                return Theme.outlineLight;
                            }
                            clip: true

                            property bool isExpanded: root.expandedVms[modelData.name] || false
                            property bool isCurrentItem: root.keyboardNavigationActive && root.selectedVm === modelData.name

                            VmHeader {
                                id: vmHeaderPart
                                width: parent.width
                                vmData: vmDelegate.modelData
                                isExpanded: vmDelegate.isExpanded
                                isCurrentItem: vmDelegate.isCurrentItem
                                onClicked: root.toggleVm(vmDelegate.modelData.name)
                            }

                            VmActions {
                                id: vmActionsPart
                                width: parent.width
                                anchors.top: vmHeaderPart.bottom
                                vmData: vmDelegate.modelData
                                isExpanded: vmDelegate.isExpanded
                                isCurrentItem: vmDelegate.isCurrentItem
                            }
                        }
                    }
                }
            }
        }
    }

    component HeaderButton: Rectangle {
        property string iconName: ""
        signal clicked

        width: 36
        height: 36
        radius: Theme.cornerRadius
        color: mouseArea.containsMouse ? Theme.surfaceHover : "transparent"

        DankIcon {
            anchors.centerIn: parent
            name: iconName
            size: 18
            color: Theme.surfaceText
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component ActionButton: Rectangle {
        id: actionButton
        property string text: ""
        property string icon: ""
        property bool enabled: true
        property bool isSelected: false
        property bool destructive: false
        property bool awaitingConfirm: false
        property real leftIndent: Theme.spacingL + Theme.spacingM
        signal triggered

        width: parent.width
        height: 44
        radius: 0
        color: {
            if (awaitingConfirm)
                return Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15);
            if (isSelected)
                return Theme.primaryHover;
            return actionMouse.containsMouse ? Theme.surfaceHover : "transparent";
        }
        border.width: 0
        opacity: enabled ? 1.0 : 0.5

        Row {
            anchors.fill: parent
            anchors.leftMargin: actionButton.leftIndent
            spacing: Theme.spacingM

            DankIcon {
                name: actionButton.awaitingConfirm ? "warning" : actionButton.icon
                size: Theme.iconSize
                color: actionButton.awaitingConfirm ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: actionButton.awaitingConfirm ? `${actionButton.text}: click again to confirm` : actionButton.text
                font.pixelSize: Theme.fontSizeMedium
                font.weight: actionButton.awaitingConfirm ? Font.Medium : Font.Normal
                color: actionButton.awaitingConfirm ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: actionButton.enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
            enabled: actionButton.enabled
            onClicked: {
                root.keyboardNavigationActive = false;
                actionButton.triggered();
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 500
}
