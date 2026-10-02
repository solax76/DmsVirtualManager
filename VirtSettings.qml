import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: VirtService.pluginId

    StyledText {
        width: parent.width
        text: "Virtual Machine Manager Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure how libvirt/KVM virtual machines are monitored and managed from your bar."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "libvirtUri"
        label: "Libvirt Connection URI"
        description: "Hypervisor connection used for all operations (e.g., 'qemu:///system' or 'qemu:///session')."
        defaultValue: VirtService.defaults.libvirtUri
        placeholder: VirtService.defaults.libvirtUri
    }

    StringSetting {
        settingKey: "virshBinary"
        label: "Virsh Binary"
        description: "Path or name of the virsh binary."
        defaultValue: VirtService.defaults.virshBinary
        placeholder: VirtService.defaults.virshBinary
    }

    StringSetting {
        settingKey: "viewerCommand"
        label: "Viewer Command"
        description: "Command used to open the VM console. '--connect <uri> --wait <vm>' is appended (virt-viewer syntax)."
        defaultValue: VirtService.defaults.viewerCommand
        placeholder: VirtService.defaults.viewerCommand
    }

    SliderSetting {
        settingKey: "debounceDelay"
        label: "Debounce Delay"
        description: "Delay before refreshing the VM list after libvirt events (prevents excessive updates during rapid changes)."
        defaultValue: VirtService.defaults.debounceDelay
        minimum: 100
        maximum: 2000
        unit: "ms"
        leftIcon: "schedule"
    }

    SliderSetting {
        settingKey: "pollingInterval"
        label: "Background Polling Interval"
        description: "Fallback polling interval to refresh VM state in case event-based updates don't work reliably. Set to 0 to disable polling."
        defaultValue: VirtService.defaults.pollingInterval
        minimum: 0
        maximum: 120000
        unit: "ms"
        leftIcon: "sync"
    }

    ToggleSetting {
        settingKey: "showDetails"
        label: "Show VM Details"
        description: "Display vCPU count and memory next to the VM state."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "autoScrollOnExpand"
        label: "Auto-scroll on Expand"
        description: "Automatically scroll to show the action list when expanding a VM."
        defaultValue: true
    }
}
