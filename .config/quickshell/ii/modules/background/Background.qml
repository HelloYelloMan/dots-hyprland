pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland


Variants {
    id: root
    readonly property bool fixedClockPosition: Config.options.background.fixedClockPosition
    readonly property real fixedClockX: Config.options.background.clockX
    readonly property real fixedClockY: Config.options.background.clockY
    readonly property real clockSizePadding: 20
    readonly property real screenSizePadding: 50
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace=>workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace=>((workspace.toplevels.values.filter(window=>window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10

        // Wallpaper (per-monitor with staged apply)
        property string monitorKey: (monitor?.name || "").toLowerCase().replace(/-/g, "_")
        property var    perMonCfg: Config?.options?.background?.perMonitor?.[monitorKey]
        property string baseWallpaperPath: (perMonCfg && perMonCfg.wallpaperPath && perMonCfg.wallpaperPath !== "") ? perMonCfg.wallpaperPath : (Config?.options?.background?.wallpaperPath || "")
        property string baseThumbnailPath: (perMonCfg && perMonCfg.thumbnailPath && perMonCfg.thumbnailPath !== "") ? perMonCfg.thumbnailPath : (Config?.options?.background?.thumbnailPath || "")
        property bool   wallpaperIsVideo: baseWallpaperPath.endsWith(".mp4") || baseWallpaperPath.endsWith(".webm") || baseWallpaperPath.endsWith(".mkv") || baseWallpaperPath.endsWith(".avi") || baseWallpaperPath.endsWith(".mov")
        property string stagedWallpaperPath: wallpaperIsVideo ? baseThumbnailPath : baseWallpaperPath
        property string wallpaperPath: ""

        // Animation
        property bool parallaxAnimEnabled: false
        Timer {
            id: enableParallaxAnim
            interval: 0
            running: false
            repeat: false
            onTriggered: bgRoot.parallaxAnimEnabled = true
        }
        property bool clockClampEnabled: false

        // Geometry
        property int  wallpaperWidth: modelData.width
        property int  wallpaperHeight: modelData.height
        property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)

        // Fit / Cover / Zoom (relative to FIT)
        property real fitScale: {
            const w = wallpaperWidth, h = wallpaperHeight, sw = screen.width, sh = screen.height;
            if (w <= 0 || h <= 0 || sw <= 0 || sh <= 0) return 1;
            return Math.min(sw / w, sh / h);
        }
        property real coverScale: {
            const w = wallpaperWidth, h = wallpaperHeight, sw = screen.width, sh = screen.height;
            if (w <= 0 || h <= 0 || sw <= 0 || sh <= 0) return 1;
            return Math.max(sw / w, sh / h);
        }
        property real coverN: coverScale / fitScale
        property real fitW: wallpaperWidth * fitScale
        property real fitH: wallpaperHeight * fitScale

        readonly property bool verticalParallax: {
            // Manual override
            if (Config.options.background.parallax.vertical) return true;
            if (!Config.options.background.parallax.autoVertical) return false;

            // Orientation default
            const defaultVertical = bgRoot.screen.height > bgRoot.screen.width;

            // Guards
            const fitWv = bgRoot.fitW, fitHv = bgRoot.fitH;
            const sw = bgRoot.screen.width, sh = bgRoot.screen.height;
            if (!(fitWv > 0) || !(fitHv > 0) || !(sw > 0) || !(sh > 0)) return defaultVertical;

            // Hypothetical normalized scales for each axis
            const sAxisH = sw / fitWv;
            const sAxisV = sh / fitHv;
            const sNormH = Math.max(bgRoot.coverN, sAxisH * bgRoot.targetN);
            const sNormV = Math.max(bgRoot.coverN, sAxisV * bgRoot.targetN);

            // Rendered size along pan axes
            const renderW_H = fitWv * sNormH; // width if we prioritize horizontal parallax
            const renderH_V = fitHv * sNormV; // height if we prioritize vertical parallax

            // Slack percentage along each pan axis
            const slackPctH = Math.max(0, (renderW_H - sw) / sw);
            const slackPctV = Math.max(0, (renderH_V - sh) / sh);

            const th = bgRoot.parallaxSlackSwitchThreshold;

            if (defaultVertical) {
                return (slackPctH - slackPctV) > th ? false : true;
            } else {
                return (slackPctV - slackPctH) > th ? true : false;
            }
        }

        property real preferredWallpaperScale: Math.max(1, (Config?.options?.background?.parallax?.workspaceZoom || 1))
        property real targetN: preferredWallpaperScale

        // Switch only if the other axis gains this much extra slack (as a fraction of screen size)
        property real parallaxSlackSwitchThreshold: 0.16

        // Only count zoom that creates slack on the active parallax axis
        property real sAxis: {
            if (Config?.options?.background?.parallax?.enableWorkspace) {
                return verticalParallax ? (screen.height / fitH) : (screen.width / fitW);
            }
            return 1;
        }
        property real sNormFinal: Math.max(coverN, sAxis * targetN)

        // Effective scale (final size = (W * fitScale) * sNormFinal)
        property real effectiveWallpaperScale: sNormFinal / coverN

        // Travel space
        property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
        property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2

        // Position

        property real clockX: (modelData.width / 2) + ((Math.random() < 0.5 ? -1 : 1) * modelData.width)
        property real clockY: (modelData.height / 2) + ((Math.random() < 0.5 ? -1 : 1) * modelData.height)
        property var textHorizontalAlignment: {
            if (Config.options.background.lockBlur.enable && Config.options.background.lockBlur.centerClock && GlobalStates.screenLocked)
                return Text.AlignHCenter;
            if (clockX < screen.width / 3)
                return Text.AlignLeft;
            if (clockX > screen.width * 2 / 3)
                return Text.AlignRight;
            return Text.AlignHCenter;
        }
        
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.background.lockBlur.enable)
        property color dominantColor: Appearance.colors.colPrimary
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colSecondary : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        // Triggers
        onStagedWallpaperPathChanged: {
            parallaxAnimEnabled = false
            clockClampEnabled = false
            clockLoader.opacity = 0
            seedOffscreenClock()
            updateZoomScale()
        }
        Component.onCompleted: updateZoomScale()

        // Seed off-screen
        function seedOffscreenClock() {
            const off = Math.max(bgRoot.screen.width, bgRoot.screen.height) * 1.2
            const dirX = Math.random() < 0.5 ? -1 : 1
            const dirY = Math.random() < 0.5 ? -1 : 1
            bgRoot.clockX = (dirX < 0 ? -off : (bgRoot.screen.width  + off)) / bgRoot.effectiveWallpaperScale
            bgRoot.clockY = (dirY < 0 ? -off : (bgRoot.screen.height + off)) / bgRoot.effectiveWallpaperScale
        }

        // Size probe
        function updateZoomScale() {
            if (!stagedWallpaperPath || stagedWallpaperPath.length === 0) return;
            getWallpaperSizeProc.path = stagedWallpaperPath
            getWallpaperSizeProc.running = true
        }
        Process {
            id: getWallpaperSizeProc
            property string path: ""
            command: [ "magick", "identify", "-format", "%w %h", path ]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text
                    const parts = output.split(" ")
                    if (parts.length >= 2) {
                        bgRoot.wallpaperWidth = Number(parts[0])
                        bgRoot.wallpaperHeight = Number(parts[1])
                    }
                    bgRoot.updateClockPosition()
                    bgRoot.wallpaperPath = bgRoot.stagedWallpaperPath
                    enableParallaxAnim.start()
                }
            }
        }

        // Trigger clock update position
        function updateClockPosition() {
            leastBusyRegionProc.running = false
            leastBusyRegionProc.running = true
        }
        Process {
            id: leastBusyRegionProc
            property string path: bgRoot.stagedWallpaperPath
            property int contentWidth:  Math.round((400  + root.clockSizePadding * 2) / bgRoot.effectiveWallpaperScale)
            property int contentHeight: Math.round((133 + root.clockSizePadding * 2) / bgRoot.effectiveWallpaperScale)
            property int horizontalPadding: Math.round(root.screenSizePadding / bgRoot.effectiveWallpaperScale)
            property int verticalPadding:   Math.round(root.screenSizePadding / bgRoot.effectiveWallpaperScale)
            command: [ Quickshell.shellPath("scripts/images/least_busy_region.py"),
                "--screen-width",  Math.round(bgRoot.screen.width  / bgRoot.effectiveWallpaperScale),
                "--screen-height", Math.round(bgRoot.screen.height / bgRoot.effectiveWallpaperScale),
                "--width", contentWidth,
                "--height", contentHeight,
                "--stride", "25",
                "--horizontal-padding", horizontalPadding,
                "--vertical-padding", verticalPadding,
                path ]
            stdout: StdioCollector {
                id: leastBusyRegionOutputCollector
                onStreamFinished: {
                    const output = leastBusyRegionOutputCollector.text
                    if (output.length === 0) return
                    const parsed = JSON.parse(output)
                    clockLoader.opacity = 1
                    bgRoot.clockX = parsed.center_x
                    bgRoot.clockY = parsed.center_y
                    bgRoot.dominantColor = parsed.dominant_color || Appearance.colors.colPrimary
                    bgRoot.clockClampEnabled = true
                }
            }
        }

        // Wallpaper
        Image {
            id: wallpaper
            visible: opacity > 0 && !blurLoader.active
            opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            cache: false
            asynchronous: true
            retainWhileLoading: true

            // Parallax
            property int  groupSize: Math.max(1, Config?.options.bar.workspaces.shown ?? 3)
            property int  activeWsId: bgRoot.monitor.activeWorkspace?.id ?? 1
            property int  indexInGroup: ((activeWsId - 1) % groupSize)
            property real normInGroup: groupSize > 1 ? (indexInGroup / (groupSize - 1)) : 0.5

            property real valueX: {
                let r = 0.5
                if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) r = normInGroup
                if (Config.options.background.parallax.enableSidebar) r += (0.15 * GlobalStates.sidebarRightOpen - 0.15 * GlobalStates.sidebarLeftOpen)
                return r
            }
            property real valueY: {
                let r = 0.5
                if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) r = normInGroup
                return r
            }
            property real effectiveValueX: Math.max(0, Math.min(1, valueX))
            property real effectiveValueY: Math.max(0, Math.min(1, valueY))

            x: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
            y: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
            source: bgRoot.wallpaperPath
            fillMode: Image.PreserveAspectCrop

            Behavior on x {
                enabled: bgRoot.parallaxAnimEnabled
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                enabled: bgRoot.parallaxAnimEnabled
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on width {
                enabled: bgRoot.parallaxAnimEnabled
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                enabled: bgRoot.parallaxAnimEnabled
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }

            width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
        }

        Loader {
            id: blurLoader
            active: Config.options.background.lockBlur.enable && (GlobalStates.screenLocked || scaleAnim.running)
            anchors.fill: wallpaper
            scale: GlobalStates.screenLocked ? Config.options.background.lockBlur.extraZoom : 1
            Behavior on scale {
                NumberAnimation {
                    id: scaleAnim
                    duration: 400
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                }
            }
            sourceComponent: GaussianBlur {
                source: wallpaper
                radius: GlobalStates.screenLocked ? Config.options.background.lockBlur.radius : 0
                samples: radius * 2 + 1

                Rectangle {
                    opacity: GlobalStates.screenLocked ? 1 : 0
                    anchors.fill: parent
                    color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                }
            }
        }

        // The clock
        Loader {
            id: clockLoader
            active: Config.options.background.showClock
            anchors {
                left: wallpaper.left
                top: wallpaper.top
                horizontalCenter: undefined
                leftMargin: {
                    const desiredLocal = bgRoot.movableXSpace + ((root.fixedClockPosition ? root.fixedClockX : bgRoot.clockX * bgRoot.effectiveWallpaperScale) - implicitWidth / 2)
                    if (!bgRoot.clockClampEnabled) return desiredLocal
                    const worldLeft = wallpaper.x + desiredLocal
                    const lo = root.screenSizePadding
                    const hi = bgRoot.screen.width - implicitWidth - root.screenSizePadding
                    const clampedWorldLeft = Math.max(lo, Math.min(hi, worldLeft))
                    return clampedWorldLeft - wallpaper.x
                }
                topMargin: {
                    if (bgRoot.shouldBlur)
                        return bgRoot.modelData.height / 3
                    const desiredLocal = bgRoot.movableYSpace + ((root.fixedClockPosition ? root.fixedClockY : bgRoot.clockY * bgRoot.effectiveWallpaperScale) - implicitHeight / 2)
                    if (!bgRoot.clockClampEnabled) return desiredLocal
                    const worldTop = wallpaper.y + desiredLocal
                    const lo = root.screenSizePadding
                    const hi = bgRoot.screen.height - implicitHeight - root.screenSizePadding
                    const clampedWorldTop = Math.max(lo, Math.min(hi, worldTop))
                    return clampedWorldTop - wallpaper.y
                }
                Behavior on leftMargin {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                Behavior on topMargin  {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
            }
            states: State {
                name: "centered"
                when: bgRoot.shouldBlur && Config.options.background.lockBlur.centerClock
                AnchorChanges {
                    target: clockLoader
                    anchors {
                        left: undefined
                        horizontalCenter: wallpaper.horizontalCenter
                        right: undefined
                    }
                }
            }
            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
            sourceComponent: Item {
                id: clock
                implicitWidth: clockColumn.implicitWidth
                implicitHeight: clockColumn.implicitHeight

                ColumnLayout {
                    id: clockColumn
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: bgRoot.textHorizontalAlignment
                        font {
                            family: Appearance.font.family.expressive
                            pixelSize: 90
                            weight: Font.Bold
                        }
                        color: bgRoot.colText
                        style: Text.Raised
                        styleColor: Appearance.colors.colShadow
                        text: DateTime.time
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: -5
                        horizontalAlignment: bgRoot.textHorizontalAlignment
                        font {
                            family: Appearance.font.family.expressive
                            pixelSize: 20
                            weight: Font.DemiBold
                        }
                        color: bgRoot.colText
                        style: Text.Raised
                        styleColor: Appearance.colors.colShadow
                        text: DateTime.date
                        animateChange: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: bgRoot.textHorizontalAlignment
                        font {
                            family: Appearance.font.family.expressive
                            pixelSize: 20
                            weight: Font.DemiBold
                        }
                        color: bgRoot.colText
                        style: Text.Raised
                        visible: Config.options.background.quote !== ""
                        styleColor: Appearance.colors.colShadow
                        text: Config.options.background.quote
                    }
                }

                RowLayout {
                    anchors {
                        top: clockColumn.bottom
                        left: bgRoot.textHorizontalAlignment === Text.AlignLeft ? clockColumn.left : undefined
                        right: bgRoot.textHorizontalAlignment === Text.AlignRight ? clockColumn.right : undefined
                        horizontalCenter: bgRoot.textHorizontalAlignment === Text.AlignHCenter ? clockColumn.horizontalCenter : undefined
                        topMargin: 5
                        leftMargin: -5
                        rightMargin: -5
                    }
                    opacity: GlobalStates.screenLocked && (!Config.options.background.lockBlur.enable || Config.options.background.lockBlur.showLockedText) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Item { Layout.fillWidth: bgRoot.textHorizontalAlignment !== Text.AlignLeft; implicitWidth: 1 }
                    MaterialSymbol {
                        text: "lock"
                        Layout.fillWidth: false
                        iconSize: Appearance.font.pixelSize.huge
                        color: bgRoot.colText
                        style: Text.Raised
                        styleColor: Appearance.colors.colShadow
                    }
                    StyledText {
                        Layout.fillWidth: false
                        text: "Locked"
                        color: bgRoot.colText
                        font.pixelSize: Appearance.font.pixelSize.larger
                        style: Text.Raised
                        styleColor: Appearance.colors.colShadow
                    }
                    Item { Layout.fillWidth: bgRoot.textHorizontalAlignment !== Text.AlignRight; implicitWidth: 1 }

                }
            }
        }
    }
}