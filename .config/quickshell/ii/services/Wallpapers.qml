import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Provides a list of wallpapers and an "apply" action that calls the existing
 * switchwall.sh script. Pretty much a limited file browsing service.
 */
Singleton {
    id: root

    property string thumbgenScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/thumbgen.py`
    property string generateThumbnailsMagickScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/generate-thumbnails-magick.sh`
    property alias directory: folderModel.folder
    readonly property string effectiveDirectory: FileUtils.trimFileProtocol(folderModel.folder.toString())
    property url defaultFolder: Qt.resolvedUrl(`${Directories.pictures}/Wallpapers`)
    property alias folderModel: folderModel // Expose for direct binding when needed
    property string searchQuery: ""
        // Supported extensions (images + videos)
        readonly property list<string> extensions: [
            "jpg", "jpeg", "png", "webp", "avif", "bmp", "svg",
            "webm", "mp4", "mkv", "avi", "mov"
        ]

    property list<string> wallpapers: [] // List of absolute file paths (without file://)

    signal changed()
    signal thumbnailGenerated(directory: string)

    // Executions
    Process {
        id: applyProc
    }
    
    function openFallbackPicker(darkMode = Appearance.m3colors.darkmode, wallpaperGroup = true, monitorName = "") {
        const args = [
            Directories.wallpaperSwitchScriptPath,
            "--mode", (darkMode ? "dark" : "light")
        ]
        if (wallpaperGroup) {
            args.push("--group")
        }
        if (monitorName && monitorName.length) {
            args.push("--monitor", monitorName)
        }
        applyProc.exec(args)
    }

    function apply(path, darkMode = Appearance.m3colors.darkmode, wallpaperGroup = true, monitorName = "") {
        if (!path || path.length === 0) return
        const args = [
            Directories.wallpaperSwitchScriptPath,
            "--image", path,
            "--mode", (darkMode ? "dark" : "light")
        ]
        if (wallpaperGroup) {
            args.push("--group")
        }
        if (monitorName && monitorName.length) {
            args.push("--monitor", monitorName)
        }
        applyProc.exec(args)
        root.changed()
    }

    Process {
        id: selectProc
        property string filePath: ""
        property bool darkMode: Appearance.m3colors.darkmode
        property bool wallpaperGroup: true
        property string monitorName: ""

        function select(filePath, darkMode = Appearance.m3colors.darkmode, wallpaperGroup = true, monitorName = "") {
            selectProc.filePath = filePath
            selectProc.darkMode = darkMode
            selectProc.wallpaperGroup = wallpaperGroup
            selectProc.monitorName = monitorName
            selectProc.exec(["test", "-d", FileUtils.trimFileProtocol(filePath)])
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                setDirectory(selectProc.filePath);
                return;
            }
            // NOTE: correct order: (path, darkMode, wallpaperGroup, monitorName)
            root.apply(selectProc.filePath, selectProc.darkMode, selectProc.wallpaperGroup, selectProc.monitorName);
        }
    }

    function select(filePath, darkMode = Appearance.m3colors.darkmode, wallpaperGroup = true, monitorName = "") {
        selectProc.select(filePath, darkMode, wallpaperGroup, monitorName);
    }

    Process {
        id: validateDirProc
        property string nicePath: ""
        function setDirectoryIfValid(path) {
            validateDirProc.nicePath = FileUtils.trimFileProtocol(path).replace(/\/+$/, "")
            if (/^\/*$/.test(validateDirProc.nicePath)) validateDirProc.nicePath = "/";
            validateDirProc.exec(["test", "-d", nicePath])
        }
        stdout: StdioCollector {
            onStreamFinished: {
                    root.directory = Qt.resolvedUrl(validateDirProc.nicePath)
                const result = text.trim()
                if (result === "dir") {
                } else if (result === "file") {
                    root.directory = Qt.resolvedUrl(FileUtils.parentDirectory(validateDirProc.nicePath))
                } else {
                    // Ignore
                }
            }
        }
    }
    function setDirectory(path) {
        validateDirProc.setDirectoryIfValid(path)
    }
    function navigateUp() {
        folderModel.navigateUp()
    }
    function navigateBack() {
        folderModel.navigateBack()
    }
    function navigateForward() {
        folderModel.navigateForward()
    }

    // Folder model
    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(root.defaultFolder)
        caseSensitive: false
        nameFilters: root.extensions.map(ext => `*${searchQuery.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)}*.${ext}`)
        showDirs: true
        showDotAndDotDot: false
        showOnlyReadable: true
        showDirsFirst: true
        sortField: FolderListModel.Name
        sortReversed: false
        onCountChanged: {
            root.wallpapers = []
            for (let i = 0; i < folderModel.count; i++) {
                const path = folderModel.get(i, "filePath") || FileUtils.trimFileProtocol(folderModel.get(i, "fileURL"))
                if (path && path.length) root.wallpapers.push(path)
            }
        }
    }

    // Thumbnail generation
    function generateThumbnail(size: string) {
        // console.log("[Wallpapers] Updating thumbnails")
        if (!["normal", "large", "x-large", "xx-large"].includes(size)) throw new Error("Invalid thumbnail size");
        thumbgenProc.directory = root.directory
        thumbgenProc.running = false
        thumbgenProc.command = [
            "bash", "-c",
            `${thumbgenScriptPath} --size ${size} --machine_progress -d ${FileUtils.trimFileProtocol(root.directory)} || ${generateThumbnailsMagickScriptPath} --size ${size} -d ${root.directory}`,
        ]
        thumbgenProc.running = true
    }
    Process {
        id: thumbgenProc
        property string directory
        onExited: (exitCode, exitStatus) => {
            root.thumbnailGenerated(thumbgenProc.directory)
        }
    }
}
