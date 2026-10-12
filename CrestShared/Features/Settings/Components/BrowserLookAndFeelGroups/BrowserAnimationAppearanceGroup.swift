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
        }
    }

    private var paletteMorph: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.address.animatesIntoCommandPalette,
            default: BrowserLookAndFeelDefaults.address.animatesIntoCommandPalette)
    }

    private var settings: [CrestResettableSetting] {
        [paletteMorph.resettable("Command palette")]
    }
}
