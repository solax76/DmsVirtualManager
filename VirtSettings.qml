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
        settingKey: "viewerCommand"
        label: "Viewer Command"
        description: "Command used to open the VM console. '--connect <uri> --wait <vm>' is appended (virt-viewer syntax)."
        defaultValue: VirtService.defaults.viewerCommand
        placeholder: VirtService.defaults.viewerCommand
    }
}
