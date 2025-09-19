import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick.Layouts

ContentPage {
    forceWidth: true
    property bool showFontPicker: false
    property string currentFontKey: ""
    property var fontSlots: [
        { key: "main",         label: Translation.tr("Main"),            default: "Rubik" },
        { key: "title",        label: Translation.tr("Title"),           default: "Gabarito" },
        { key: "monospace",    label: Translation.tr("Monospace"),       default: "JetBrainsMono NF" },
        { key: "reading",      label: Translation.tr("Reading"),         default: "Readex Pro" },
        { key: "expressive",   label: Translation.tr("Expressive"),      default: "Space Grotesk" }
    ]

    ContentSection {
        icon: "colors"
        title: Translation.tr("Color generation")

        ConfigSwitch {
            buttonIcon: "hardware"
            text: Translation.tr("Shell & utilities")
            checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "tv_options_input_settings"
            text: Translation.tr("Qt apps")
            checked: Config.options.appearance.wallpaperTheming.enableQtApps
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableQtApps = checked;
            }
            StyledToolTip {
                content: Translation.tr("Shell & utilities theming must also be enabled")
            }
        }
        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Terminal")
            checked: Config.options.appearance.wallpaperTheming.enableTerminal
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableTerminal = checked;
            }
            StyledToolTip {
                content: Translation.tr("Shell & utilities theming must also be enabled")
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Force dark mode in terminal")
                checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                onCheckedChanged: {
                     Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode= checked;
                }
                StyledToolTip {
                    content: Translation.tr("Ignored if terminal theming is not enabled")
                }
            }
        }

        ConfigSpinBox {
            icon: "invert_colors"
            text: Translation.tr("Terminal: Harmony (%)")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
            from: 0
            to: 100
            stepSize: 10
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100;
            }
        }
        ConfigSpinBox {
            icon: "gradient"
            text: Translation.tr("Terminal: Harmonize threshold")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
            from: 0
            to: 100
            stepSize: 10
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value;
            }
        }
        ConfigSpinBox {
            icon: "format_color_text"
            text: Translation.tr("Terminal: Foreground boost (%)")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
            from: 0
            to: 100
            stepSize: 10
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100;
            }
        }
    }

    ContentSection {
        icon: "brand_family"
        title: Translation.tr("Fonts")

        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr('Choosing custom fonts can reduce readability or cause the layout of some UI elements to break')
        }

        Repeater {
            model: fontSlots

            ColumnLayout {
                Layout.fillWidth: true

                ContentSubsection {
                    title: modelData.label + " " + Translation.tr("Font")

                    ConfigSelectionArray {
                        Layout.fillWidth: false
                        options: [
                            {
                                "displayName": (Config.options.appearance.fonts[modelData.key] == modelData.default)
                                                ? Config.options.appearance.fonts[modelData.key]
                                                : "Default",
                                "icon": "check",
                                "value":
                                "default"
                            },
                            {
                                "displayName":  (Config.options.appearance.fonts[modelData.key] != modelData.default)
                                                ? Config.options.appearance.fonts[modelData.key]
                                                : "Custom",
                                "icon": "edit",
                                "value": "custom"
                            }
                        ]

                        // Binding decides which pill looks active
                        currentValue: (
                            Config.options.appearance.fonts[modelData.key]
                            && Config.options.appearance.fonts[modelData.key].length
                            && Config.options.appearance.fonts[modelData.key] !== modelData.default
                        ) ? "custom" : "default"

                        // Behavior: switch to default resets to default string; custom opens picker
                        onSelected: (val) => {
                            if (val === "default") {
                                Config.options.appearance.fonts[modelData.key] = modelData.default;
                            } else {
                                currentFontKey = modelData.key;
                                showFontPicker = true;
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 60
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    StyledText {
                        anchors.fill: parent
                        anchors.margins: 10
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: 22
                        font.family: Config.options.appearance.fonts[modelData.key]
                        text: qsTr("The quick brown fox jumps over 1234567890 — %&!?")
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "emoji_symbols"
        title: Translation.tr("Icons")

        ContentSubsection {
            title: "Material Icons Style"

            ConfigSelectionArray {
                Layout.fillWidth: false
                options: [
                    {
                        "displayName": "Outlined",
                        "icon": "check",
                        "value": "Material Symbols Outlined"
                    },
                    {
                        "displayName": "Rounded",
                        "icon": "check",
                        "value": "Material Symbols Rounded"
                    },
                    {
                        "displayName": "Sharp",
                        "icon": "check",
                        "value": "Material Symbols Sharp"
                    }
                ]

                currentValue: Config.options.appearance.fonts.iconMaterial

                onSelected: (value) => {
                    Config.options.appearance.fonts.iconMaterial = value;
                }
            }
            ConfigSwitch {
                buttonIcon: "format_color_fill"
                text: Translation.tr("Fill Icons")
                checked: Config.options.appearance.iconFill
                onCheckedChanged: {
                    Config.options.appearance.iconFill = checked;
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 150
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            MaterialSymbol {
                anchors.fill: parent
                anchors.centerIn: parent
                anchors.margins: 10
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer1
                font.pixelSize: 48
                text: qsTr("homesearchsettingsfavoritewarningcheck_circleclosemenuplay_arrowpausevolume_upalarmcamera_altlocation_onflightshopping_cartlockvisibilitypersonlanguagetranslatedark_modelight_modecalendar_today")
            }
        }
    }
    Loader {
        parent: pageLoader
        anchors.fill: parent
        active: showFontPicker
        visible: showFontPicker

        sourceComponent: FontSelectionDialog {
            titleText: Translation.tr("Select Font")
            items: Qt.fontFamilies().slice().sort()
            defaultChoice: Config.options.appearance.fonts[currentFontKey]

            onCanceled: showFontPicker = false
            onSelected: (result) => {
                showFontPicker = false
                if (!result) return
                Config.options.appearance.fonts[currentFontKey] = result
            }
        }
    }
}
