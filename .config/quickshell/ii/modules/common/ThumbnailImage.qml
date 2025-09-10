// modules/common/ThumbnailImage.qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. Original image path (magick) preserved; videos use ffmpegthumbnailer.
 * Fixes:
 *  - "Unable to assign [undefined] to QString" by never emitting undefined strings.
 *  - Thumbnail flicker by not clearing Image.source; we set it only when the file exists.
 */
StyledImage {
    id: root

    // knobs
    property bool generateThumbnail: true
    required property string sourcePath

    // Always-defined size bucket
    property string thumbnailSizeName: (Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height) || "normal")

    // Always-defined thumbnail path ("" until ready)
    property string thumbnailPath: {
        if (!sourcePath || sourcePath.length === 0) return "";
        const resolved = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encoded = resolved.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encoded}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    property string thumbnailDir: `${Directories.genericCache}/thumbnails/${thumbnailSizeName}`

    // Simple extension-based video detection (case-insensitive)
    readonly property bool isVideo: (function () {
        if (!sourcePath || sourcePath.length === 0) return false;
        const p = FileUtils.trimFileProtocol(`${sourcePath}`).toLowerCase();
        return /\.(mp4|mkv|webm|mov|avi|m4v|mpg|mpeg|wmv|flv|3gp)$/.test(p);
    })()

    // Cache-busting nonce used only when we freshly (re)generate
    property int reloadNonce: 0

    // What the Image actually shows. We never assign undefined here.
    property string displayedSource: ""

    // Bind the StyledImage to our controlled source (prevents flicker)
    source: displayedSource

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // ---- triggers: when size/path changes, (re)check/generate ----------------
    function triggerGen() {
        if (!root.generateThumbnail) return;
        if (!root.thumbnailPath) return; // not ready yet
        // kick the generator; it will set displayedSource after it verifies/creates the file
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }

    onSourceSizeChanged: triggerGen()
    onThumbnailPathChanged: triggerGen()
    onSourcePathChanged: triggerGen()

    // ---- generator ----------------------------------------------------------
    Process {
        id: thumbnailGeneration
        command: {
            if (!root.generateThumbnail || !root.thumbnailPath) return [];

            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName] || 256;
            const src = FileUtils.trimFileProtocol(root.sourcePath || "");
            const dst = FileUtils.trimFileProtocol(root.thumbnailPath || "");
            const dir = FileUtils.trimFileProtocol(root.thumbnailDir || "");
            const isVid = root.isVideo ? "1" : "0";

            // Behavior:
            //   0 -> dst exists already
            //   1 -> freshly generated
            return ["bash", "-lc",
                `set -eu; ` +
                `dir=${JSON.stringify(dir)}; src=${JSON.stringify(src)}; dst=${JSON.stringify(dst)}; size=${JSON.stringify(maxSize)}; isvid=${JSON.stringify(isVid)}; ` +
                `[ -n "$dst" ] || exit 0; ` +                        // path not ready -> treat as "not set" yet
                `[ -d "$dir" ] || mkdir -p "$dir"; ` +
                `[ -f "$dst" ] && exit 0 || { ` +
                `  if [ "$isvid" = "1" ]; then ` +
                `    command -v ffmpegthumbnailer >/dev/null 2>&1 || exit 0; ` +
                `    ffmpegthumbnailer -i "$src" -o "$dst" -s "$size" -q 8 -c png -t 5% >/dev/null 2>&1 && exit 1; ` +
                `  else ` +
                `    magick '${root.sourcePath}' -resize ${maxSize}x${maxSize} "$dst" >/dev/null 2>&1 && exit 1; ` +
                `  fi; ` +
                `}`
            ];
        }
        onExited: (exitCode) => {
            if (!root.thumbnailPath) return;

            if (exitCode === 0) {
                // File already exists -> show it (no cache bust to keep disk cache effective)
                root.displayedSource = root.thumbnailPath;
            } else if (exitCode === 1) {
                // Freshly generated -> bump nonce to dodge QML cache without clearing source (no flicker)
                root.reloadNonce = root.reloadNonce + 1;
                root.displayedSource = `${root.thumbnailPath}?v=${root.reloadNonce}`;
            }
            // other exit codes ignored quietly
        }
    }
}
