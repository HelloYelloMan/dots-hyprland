// modules/wallpaperSelector/WallpaperDirectoryItem.qml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

MouseArea {
    id: root
    required property var fileModelData
    property bool isDirectory: fileModelData.fileIsDir

    // ---- Media helpers -----------------------------------------------------

    // Case-insensitive image check
    function isImageName(name) {
        return /\.(png|jpe?g|webp|avif|bmp|gif|tiff)$/i.test(name || "");
    }

    // Case-insensitive video check
    function isVideoName(name) {
        return /\.(mp4|mkv|webm|mov|avi|m4v|flv)$/i.test(name || "");
    }

    function isMediaName(name) {
        return isImageName(name) || isVideoName(name);
    }

    // Regexes used for preview selection inside folders.
    // Prefer files named "main.*" where * is any supported media extension.
    // You can tweak or expand these without touching FolderListModel.
    property var rxPrefer: /^(?:main)\.(?:png|jpe?g|webp|avif|bmp|gif|tiff|mp4|mkv|webm|mov|avi|m4v|flv)$/i
    property var rxMedia:  /\.(?:png|jpe?g|webp|avif|bmp|gif|tiff|mp4|mkv|webm|mov|avi|m4v|flv)$/i

    // Load ALL files; we filter with JS regex above (replaces nameFilters).
    FolderListModel {
        id: mediaModel
        folder: isDirectory ? ("file://" + fileModelData.filePath) : ""
        nameFilters: ["*"]               // intentionally broad; filtering done via regex
        showDirs: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        sortReversed: false
    }

    // Utility: scan a FolderListModel and return first filePath whose fileName matches rx
    function firstMatchPath(model, rx) {
        if (!root.isDirectory || !model || model.count === 0) return "";
        for (let i = 0; i < model.count; ++i) {
            const name = model.get(i, "fileName") || "";
            if (rx.test(name)) {
                return FileUtils.trimFileProtocol(model.get(i, "filePath") || "");
            }
        }
        return "";
    }

    // Resolved preview path for folders (no file://)
    property string folderPreviewPath: {
        if (!isDirectory) return "";
        // Preferred: main.* (image or video)
        const preferred = firstMatchPath(mediaModel, rxPrefer);
        if (preferred) return preferred;
        // Fallback: first media file in folder
        const anyMedia = firstMatchPath(mediaModel, rxMedia);
        if (anyMedia) return anyMedia;
        return "";
    }

    // Use thumbnail for files if media; for folders if a preview exists
    property bool useThumbnail: !isDirectory
        ? isMediaName(fileModelData.fileName)
        : folderPreviewPath.length > 0

    // What we want thumbnailed / previewed
    property string displayPath: isDirectory ? folderPreviewPath : fileModelData.filePath

    // Force a refresh by briefly clearing and restoring sourcePath
    function refreshThumbnail() {
        if (!thumbnailImageLoader.active || !thumbnailImageLoader.item) return;
        const ti = thumbnailImageLoader.item;
        const path = root.displayPath;
        if (!path || path.length === 0) return;

        ti.sourcePath = "";
        Qt.callLater(() => { ti.sourcePath = path; });
    }

    // Safety: nudge after component starts up (covers early races)
    Timer {
        id: safetyNudge
        interval: 200
        repeat: false
        onTriggered: refreshThumbnail()
    }

    Component.onCompleted: safetyNudge.start()

    // Keep display fresh when folder listing changes
    Connections {
        target: mediaModel
        function onStatusChanged() {
            if (mediaModel.status === FolderListModel.Ready && root.isDirectory) refreshThumbnail();
        }
        function onCountChanged() {
            if (root.isDirectory) refreshThumbnail();
        }
    }

    // When Wallpapers finishes building thumbs for a directory, refresh items from that directory
    Connections {
        target: Wallpapers
        function onThumbnailGenerated(directory) {
            if (!root.useThumbnail) return;
            const parentDir = FileUtils.parentDirectory(root.displayPath);
            if (parentDir === directory) refreshThumbnail();
        }
    }

    // If the target path changes (e.g., folder gets a preview candidate), refresh
    onDisplayPathChanged: refreshThumbnail()

    property alias colBackground: background.color
    property alias colText: wallpaperItemName.color
    property alias radius: background.radius
    property alias margins: background.anchors.margins
    property alias padding: wallpaperItemColumnLayout.anchors.margins
    margins: Appearance.sizes.wallpaperSelectorItemMargins
    padding: Appearance.sizes.wallpaperSelectorItemPadding

    signal activated()

    hoverEnabled: true
    onClicked: root.activated()

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Appearance.rounding.normal
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        ColumnLayout {
            id: wallpaperItemColumnLayout
            anchors.fill: parent
            spacing: 4

            Item {
                id: wallpaperItemImageContainer
                Layout.fillHeight: true
                Layout.fillWidth: true

                // Only show shadow when an image is actually drawn
                Loader {
                    id: thumbnailShadowLoader
                    active: thumbnailImageLoader.active && thumbnailImageLoader.item.status === Image.Ready
                    anchors.fill: thumbnailImageLoader
                    sourceComponent: StyledRectangularShadow {
                        target: thumbnailImageLoader
                        anchors.fill: undefined
                        radius: Appearance.rounding.small
                    }
                }

                // Unified preview (image or video thumbnail), with internal thumbnail generation
                Loader {
                    id: thumbnailImageLoader
                    anchors.fill: parent
                    active: root.useThumbnail && root.displayPath.length > 0
                    sourceComponent: ThumbnailImage {
                        id: thumbnailImage
                        generateThumbnail: true
                        sourcePath: root.displayPath

                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        sourceSize.width: wallpaperItemColumnLayout.width
                        sourceSize.height: wallpaperItemColumnLayout.height
                                              - wallpaperItemColumnLayout.spacing
                                              - wallpaperItemName.height

                        // Mask to rounded rectangle
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: wallpaperItemImageContainer.width
                                height: wallpaperItemImageContainer.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }

                // === Folder badge (only for directories that have thumbnails) ===
                Rectangle {
                    id: folderBadge
                    visible: root.isDirectory
                            && root.useThumbnail
                            && thumbnailImageLoader.active
                            && thumbnailImageLoader.item
                            && thumbnailImageLoader.item.status === Image.Ready
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    width: 32
                    height: 32
                    radius: height / 2
                    color: Appearance.colors.colSecondaryContainer
                    opacity: 0.95
                    z: 10

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "folder"            // folder glyph
                        iconSize: 22
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                // Fallback icon when no media thumbnail available
                Loader {
                    id: iconLoader
                    active: !root.useThumbnail
                    anchors.fill: parent
                    sourceComponent: DirectoryIcon {
                        fileModelData: root.fileModelData
                        sourceSize.width: wallpaperItemColumnLayout.width
                        sourceSize.height: wallpaperItemColumnLayout.height - wallpaperItemColumnLayout.spacing - wallpaperItemName.height
                    }
                }
            }

            StyledText {
                id: wallpaperItemName
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                text: fileModelData.fileName
            }
        }
    }
}
