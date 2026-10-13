import SwiftUI

/// Which parts of the interface animate, on every Space on this device.
struct BrowserAnimationAppearanceGroup: View {
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    var body: some View {
        CrestSettingsGroup("Animations", settings: settings) {
            CrestSettingRow("Command palette", setting: paletteMorph.resettable("Command palette")) {
                Toggle("Command palette", isOn: paletteMorph.binding)
                    .labelsHidden()
            }
            CrestSettingRow("Sidebar", setting: sidebar.resettable("Sidebar")) {
                Toggle("Sidebar", isOn: sidebar.binding)
                    .labelsHidden()
            }
        }
    }

    private var paletteMorph: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.address.animatesIntoCommandPalette,
            default: BrowserLookAndFeelDefaults.address.animatesIntoCommandPalette)
    }

    private var sidebar: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.animatesSidebar, default: BrowserLookAndFeelDefaults.animatesSidebar)
    }

    private var settings: [CrestResettableSetting] {
        [paletteMorph.resettable("Command palette"), sidebar.resettable("Sidebar")]
    }
}
