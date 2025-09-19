import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real dialogPadding: 15
    property real dialogMargin: 30
    property string titleText: "Select Font"
    property alias items: fullModel.values
    property int selectedId: choiceListView.currentIndex
    property var defaultChoice
    property string searchQuery: ""

    signal canceled();
    signal selected(var result);

    // internal model for caller-provided items (or auto-filled onCompleted)
    ScriptModel { id: fullModel }

    // fastest-width strategy: measure only the longest visible family name (by char length)
    property string _longestFamily: ""
    property string _longestText: ""

    function applyFilter() {
        var src = fullModel.values || [];
        var q = (root.searchQuery || "").toLowerCase();

        var prevValue = null;
        if (choiceListView.currentIndex >= 0 && choiceModel.values && choiceModel.values.length > choiceListView.currentIndex) {
            prevValue = choiceModel.values[choiceListView.currentIndex];
        }

        var filtered = q.length
            ? src.filter(function(v) { return v !== null && v !== undefined && v.toString().toLowerCase().indexOf(q) !== -1; })
            : src.slice();

        // ---- update model with a clean rebuild to avoid geometry jank
        choiceListView.model = null;
        choiceModel.values = filtered.slice();
        choiceListView.model = choiceModel;

        // ---- recompute "longest" by string length (cheap), probe measures its pixel width
        var longest = "";
        var bestLen = -1;
        for (var i = 0; i < filtered.length; ++i) {
            var s = (filtered[i] ?? "").toString();
            var L = s.length;
            if (L > bestLen) { bestLen = L; longest = s; }
        }
        root._longestFamily = longest;
        root._longestText = longest;

        // ---- reselect a sensible index
        choiceListView.currentIndex = -1;
        var idx = -1;
        if (prevValue !== null) idx = filtered.indexOf(prevValue);
        if (idx === -1 && root.defaultChoice !== undefined) idx = filtered.indexOf(root.defaultChoice);
        if (idx === -1 && filtered.length > 0) idx = 0;

        choiceListView.currentIndex = idx;
        if (idx >= 0) choiceListView.positionViewAtIndex(idx, ListView.Center);
    }

    onSearchQueryChanged: applyFilter()
    onItemsChanged: applyFilter()
    onDefaultChoiceChanged: applyFilter()
    Component.onCompleted: {
        if (!fullModel.values || fullModel.values.length === 0) {
            fullModel.values = Qt.fontFamilies().slice().sort();
        }
        applyFilter();
        if (searchField) searchField.forceActiveFocus();
    }

    Rectangle { // Scrim
        id: scrimOverlay
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim
        MouseArea {
            hoverEnabled: true
            anchors.fill: parent
            preventStealing: true
            propagateComposedEvents: false
        }
    }

    Rectangle { // The dialog
        id: dialog
        color: Appearance.colors.colSurfaceContainerHigh
        radius: Appearance.rounding.normal

        // Fill height; width fits to content via single width probe (fast)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: dialogMargin
        implicitHeight: dialogColumnLayout.implicitHeight

        readonly property int _indicatorMax: 40  // matches hover ring size
        readonly property int _gap: 10           // spacing between indicator and label

        // Hidden single width probe (cheap): measure the longest family name in its own font
        Text {
            id: widthProbe
            visible: false
            text: root._longestText
            font.family: root._longestFamily
            font.pixelSize: Appearance.font.pixelSize.normal
            renderType: Text.NativeRendering
        }

        // Dialog width = max(title, longest row (indicator + gap + text), bottom row)
        width: Math.max(
            dialogTitle.implicitWidth + root.dialogPadding * 2,
            root.dialogPadding + _indicatorMax + _gap + widthProbe.implicitWidth + root.dialogPadding,
            dialogButtonsRowLayout.implicitWidth + root.dialogPadding * 2
        )
        
        ColumnLayout {
            id: dialogColumnLayout
            anchors.fill: parent
            spacing: 16

            StyledText {
                id: dialogTitle
                Layout.topMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.alignment: Qt.AlignLeft
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: Appearance.font.pixelSize.larger
                text: root.titleText
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            StyledListView {
                id: choiceListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: root.defaultChoice !== undefined ? root.items.indexOf(root.defaultChoice) : -1
                spacing: 6
                reuseItems: false
                cacheBuffer: 0

                model: ScriptModel {
                    id: choiceModel
                }

                delegate: Item {
                    id: rowRoot
                    required property var modelData
                    required property int index
                    anchors {
                        left: parent?.left
                        right: parent?.right
                        leftMargin: root.dialogPadding
                        rightMargin: root.dialogPadding
                    }
                    height: Math.max(indicator.implicitHeight, label.implicitHeight) + 4

                    RowLayout {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: dialog._gap

                        // Local radio-like indicator whose hover reacts to whole row
                        Item {
                            id: indicator
                            implicitWidth: 20
                            implicitHeight: 20
                            width: 20
                            height: 20

                            Rectangle {
                                anchors.centerIn: parent
                                width: rowHover.hovered ? dialog._indicatorMax : 20
                                height: rowHover.hovered ? dialog._indicatorMax : 20
                                radius: Appearance.rounding.full
                                color: Appearance.m3colors.m3onSurface
                                opacity: rowHover.hovered ? 0.08 : 0
                                Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                Behavior on height { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                radius: Appearance.rounding.full
                                color: "transparent"
                                border.width: 2
                                border.color: (index === choiceListView.currentIndex)
                                             ? Appearance.colors.colPrimary
                                             : Appearance.m3colors.m3onSurfaceVariant
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: (index === choiceListView.currentIndex) ? 10 : 4
                                height: (index === choiceListView.currentIndex) ? 10 : 4
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colPrimary
                                opacity: (index === choiceListView.currentIndex) ? 1 : 0
                                Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                Behavior on height { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                            }
                        }

                        // Single-line label rendered in the font family itself
                        StyledText {
                            id: label
                            Layout.fillWidth: true
                            text: modelData?.toString() ?? ""
                            color: Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.family: modelData?.toString() ?? ""
                            elide: Text.ElideRight
                        }
                    }

                    HoverHandler { id: rowHover }
                    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: choiceListView.currentIndex = index }
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            RowLayout {
                id: dialogButtonsRowLayout
                Layout.bottomMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.alignment: Qt.AlignRight

                ToolbarTextField {
                    id: searchField
                    Layout.fillHeight: false
                    implicitWidth: 280
                    padding: 6
                    placeholderText: Translation.tr("Search…")
                    onTextChanged: root.searchQuery = text
                    onAccepted: {
                        if (root.selectedId >= 0 && choiceModel.values && choiceModel.values.length > root.selectedId) {
                            root.selected(choiceModel.values[root.selectedId]);
                        }
                    }
                }
                Item { Layout.fillWidth: true }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.canceled()
                }
                DialogButton {
                    buttonText: Translation.tr("OK")
                    onClicked: root.selected(
                        root.selectedId === -1 ? null :
                        choiceModel.values[root.selectedId]
                    )
                }
            }
        }
    }
}
