#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

handle_kde_material_you_colors() {
    # Check if Qt app theming is enabled in config
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "false" ]; then
            return
        fi
    fi

    # Map $type_flag to allowed scheme variants for kde-material-you-colors-wrapper.sh
    local kde_scheme_variant=""
    case "$type_flag" in
        scheme-content|scheme-expressive|scheme-fidelity|scheme-fruit-salad|scheme-monochrome|scheme-neutral|scheme-rainbow|scheme-tonal-spot)
            kde_scheme_variant="$type_flag"
            ;;
        *)
            kde_scheme_variant="scheme-tonal-spot" # default
            ;;
    esac
    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant"
}

pre_process() {
    local mode_flag="$1"
    # Set GNOME color-scheme if mode_flag is dark or light
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"


    handle_kde_material_you_colors &

    # Determine the largest region on the wallpaper that's sufficiently un-busy to put widgets in
    # if [ ! -f "$MATUGEN_DIR/scripts/least_busy_region.py" ]; then
    #     echo "Error: least_busy_region.py script not found in $MATUGEN_DIR/scripts/"
    # else
    #     "$MATUGEN_DIR/scripts/least_busy_region.py" \
    #         --screen-width "$screen_width" --screen-height "$screen_height" \
    #         --width 300 --height 200 \
    #         "$wallpaper_path" > "$STATE_DIR"/user/generated/wallpaper/least_busy_region.json
    # fi
}

check_and_prompt_upscale() {
    local img="$1"
    min_width_desired="$(hyprctl monitors -j | jq '([.[].width] | max)' | xargs)" # max monitor width
    min_height_desired="$(hyprctl monitors -j | jq '([.[].height] | max)' | xargs)" # max monitor height

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then # Not check resolution for videos, just let em pass
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            action=$(notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "open_upscayl=Open Upscayl"\
                -a "Wallpaper switcher")
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        kitty -1 yay -S upscayl-bin
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" ]] && return 0 || return 1
}

spawn_mpvpaper() {
    # Usage: spawn_mpvpaper <MONITOR> <PATH>
    if command -v setsid >/dev/null 2>&1; then
        setsid -f mpvpaper -o "$VIDEO_OPTS" "$1" "$2" >/dev/null 2>&1 &
    else
        nohup mpvpaper -o "$VIDEO_OPTS" "$1" "$2" >/dev/null 2>&1 &
    fi
}

spawn_mpvpaper_paused_with_ipc() {
    # Usage: spawn_mpvpaper_paused_with_ipc <MONITOR> <PATH> <SOCK>
    local opts="$VIDEO_OPTS --pause --input-ipc-server=$3"
    [ -S "$3" ] && rm -f "$3"
    if command -v setsid >/dev/null 2>&1; then
        setsid -f mpvpaper -o "$opts" "$1" "$2" >/dev/null 2>&1 &
    else
        nohup mpvpaper -o "$opts" "$1" "$2" >/dev/null 2>&1 &
    fi
}

kill_existing_mpvpaper() { pkill -f -9 mpvpaper || true; }
kill_mpvpaper_for_monitor() { pkill -f -9 "mpvpaper .*${1}" 2>/dev/null || true; }

# ---- IPC HELPERS -------------------------------------------------------------
IPC_TOOL=""
detect_ipc_tool() {
    if command -v socat >/dev/null 2>&1; then IPC_TOOL="socat"
    elif command -v nc   >/dev/null 2>&1 && nc -h 2>&1 | grep -q -- '-U'; then IPC_TOOL="nc"
    elif command -v ncat >/dev/null 2>&1; then IPC_TOOL="ncat"
    else IPC_TOOL=""
    fi
}
ipc_send_json() {
    local sock="$1"; shift
    local payload="$*"
    case "$IPC_TOOL" in
        socat) printf '%s\n' "$payload" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1 ;;
        nc)    printf '%s\n' "$payload" | nc -U -w 1 "$sock" >/dev/null 2>&1 ;;
        ncat)  printf '%s\n' "$payload" | ncat -U -w 1 "$sock" >/dev/null 2>&1 ;;
        *)     return 1 ;;
    esac
}

# Start multiple videos nearly simultaneously (group mode)
start_videos_simul() {
    local pairs=("$@")    # each: "MON|PATH"
    detect_ipc_tool
    if [[ -z "$IPC_TOOL" ]]; then
        local p m path
        for p in "${pairs[@]}"; do m="${p%%|*}"; kill_mpvpaper_for_monitor "$m" || true; done
        for p in "${pairs[@]}"; do m="${p%%|*}"; path="${p#*|}"; spawn_mpvpaper "$m" "$path"; done
        return 0
    fi
    local socks=() p m path sock
    for p in "${pairs[@]}"; do m="${p%%|*}"; kill_mpvpaper_for_monitor "$m" || true; done
    for p in "${pairs[@]}"; do
        m="${p%%|*}"; path="${p#*|}"
        sock="$RUNTIME_DIR/mpvpaper-$m.sock"
        spawn_mpvpaper_paused_with_ipc "$m" "$path" "$sock"
        socks+=("$sock")
    done
    local i; for i in {1..100}; do
        local ready=1
        for sock in "${socks[@]}"; do [ -S "$sock" ] || { ready=0; break; }; done
        [ "$ready" -eq 1 ] && break
        sleep 0.05
    done
    for sock in "${socks[@]}"; do ipc_send_json "$sock" '{ "command": ["set", "pause", false] }' & done
    wait
}

create_restore_script() { :; }
remove_restore() { :; }

set_wallpaper_path() {
    local path="$1"
    local monitor="$2" # Optional: second argument is the monitor name

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        if [[ -n "$monitor" ]]; then
            # Set per-monitor path
            local key; key="$(normalize_monitor_key "$monitor")"
            jq --arg mon "$key" --arg path "$path" \
               '(.background.perMonitor //= {}) | .background.perMonitor[$mon].wallpaperPath = $path' \
               "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        else
            # Set global path (backward compatible)
            jq --arg path "$path" '.background.wallpaperPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        fi
    fi
}

set_thumbnail_path() {
    local path="$1"
    local monitor="$2" # Optional: second argument is the monitor name

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        if [[ -n "$monitor" ]]; then
            # Set per-monitor thumbnail path
            local key; key="$(normalize_monitor_key "$monitor")"
            jq --arg mon "$key" --arg path "$path" \
               '(.background.perMonitor //= {}) | .background.perMonitor[$mon].thumbnailPath = $path' \
               "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        else
            # Set global thumbnail path (backward compatible)
            jq --arg path "$path" '.background.thumbnailPath = $path' \
                "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        fi
    fi
}

clear_thumbnail_path() {
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq '.background.thumbnailPath = ""' \
            "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

normalize_monitor_key() { tr '[:upper:]' '[:lower:]' <<< "$1" | tr '-' '_'; }

set_wallpaper_path_for_monitor() {
    local monitor="$1" path="$2"
    if [ -f "$SHELL_CONFIG_FILE" ] && [ -n "$monitor" ]; then
        local key; key="$(normalize_monitor_key "$monitor")"
        jq --arg mon "$key" --arg path "$path" \
           '(.background.perMonitor //= {}) | .background.perMonitor[$mon].wallpaperPath = $path' \
           "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}
set_thumbnail_path_for_monitor() {
    local monitor="$1" path="$2"
    if [ -f "$SHELL_CONFIG_FILE" ] && [ -n "$monitor" ]; then
        local key; key="$(normalize_monitor_key "$monitor")"
        jq --arg mon "$key" --arg path "$path" \
           '(.background.perMonitor //= {}) | .background.perMonitor[$mon].thumbnailPath = $path' \
           "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}
clear_permonitor_for() {
    local monitor="$1"
    if [ -f "$SHELL_CONFIG_FILE" ] && [ -n "$monitor" ]; then
        local key; key="$(normalize_monitor_key "$monitor")"
        jq --arg mon "$key" \
           '(.background.perMonitor //= {}) 
            | .background.perMonitor[$mon].wallpaperPath = "" 
            | .background.perMonitor[$mon].thumbnailPath = ""' \
           "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

# ---- GROUP HELPERS -----------------------------------------------------------
has_monitor() { local m; for m in "${MONITORS[@]}"; do [[ "$m" == "$1" ]] && return 0; done; return 1; }
leftmost_monitor()  { hyprctl monitors -j | jq -r 'min_by(.x) | .name'; }
rightmost_monitor() { hyprctl monitors -j | jq -r 'max_by(.x) | .name'; }
focused_monitor()   { hyprctl monitors -j | jq -r '.[] | select(.focused==true) | .name' | head -n1; }
center_monitor() {
    hyprctl monitors -j | jq -r '
        . as $m |
        ($m | map(.x + (.width/2)) | add / length) as $cx |
        ($m | min_by((.x + (.width/2) - $cx) | abs) | .name)'
}
keyword_to_monitor() {
    case "$1" in
        main|primary)  local mon; mon="$(jq -r '.[] | select((.id==1) or (.name=="1")) | .monitor' <<< "$(hyprctl workspaces -j)" | head -n1)"; if [[ -n "$mon" ]]; then echo "$mon"; else focused_monitor; fi ;;
        left|leftmonitor)   leftmost_monitor ;;
        right|rightmonitor) rightmost_monitor ;;
        center|middle|centermonitor|middlemonitor) center_monitor ;;
        *) return 1 ;;
    esac
}
find_group_file_for_monitor() {
    local dir="$1" mon="$2" f
    local m1="$mon" m2="${mon//-/_}" m3="${mon//-/}" m4="${mon//_/-}"
    while IFS= read -r -d '' f; do echo "$f"; return 0
    done < <(find "$dir" -maxdepth 1 -type f \( -iname "${m1}.*" -o -iname "${m2}.*" -o -iname "${m3}.*" -o -iname "${m4}.*" \) -print0 | head -z -n1)
    local kw mapped
    for kw in left right center middle main primary; do
        mapped="$(keyword_to_monitor "$kw" 2>/dev/null || true)"
        if [[ "$mapped" == "$mon" ]]; then
            while IFS= read -r -d '' f; do echo "$f"; return 0
            done < <(find "$dir" -maxdepth 1 -type f \( -iname "${kw}.*" -o -iname "${kw}monitor.*" \) -print0 | head -z -n1)
        fi
    done
    return 1
}

GROUP_VIDEOS=()
GROUP_IMAGES=()
GROUP_BLANKS=()

collect_group_actions() {
    local selected="$1" skip_mon="$2" dir; dir="$(dirname -- "$selected")"
    local mon f matched_any=0
    GROUP_VIDEOS=(); GROUP_IMAGES=(); GROUP_BLANKS=()
    for mon in "${MONITORS[@]}"; do
        [[ -n "$skip_mon" && "$mon" == "$skip_mon" ]] && continue
        if f="$(find_group_file_for_monitor "$dir" "$mon")"; then
            matched_any=1
            if is_video "$f"; then GROUP_VIDEOS+=("$mon|$f"); else GROUP_IMAGES+=("$mon|$f"); fi
        else
            GROUP_BLANKS+=("$mon")
        fi
    done
    [[ "$matched_any" -eq 0 ]] && GROUP_BLANKS=()
}

# ---- GLOBAL/THEME UPDATERS ---------------------------------------------------
snapshot_video_thumbnail() {
    # Usage: snapshot_video_thumbnail <VIDEO_PATH> -> echoes thumbnail path (if created)
    local v="$1" tn="$THUMBNAIL_DIR/$(basename "$v").jpg"
    mkdir -p "$THUMBNAIL_DIR"
    command -v ffmpeg &>/dev/null && ffmpeg -y -i "$v" -vframes 1 "$tn" 2>/dev/null || true
    [ -f "$tn" ] && printf '%s\n' "$tn"
}

GLOBAL_UPDATED=0
update_global_for_image() {
    local path="$1"
    set_wallpaper_path "$path"
    clear_thumbnail_path
    matugen_args=(image "$path")
    generate_colors_material_args=(--path "$path")
    GLOBAL_UPDATED=1
}
update_global_for_video() {
    local path="$1" tn
    tn="$(snapshot_video_thumbnail "$path")"
    set_wallpaper_path "$path"
    [ -n "$tn" ] && set_thumbnail_path "$tn"
    if [ -n "$tn" ]; then
        matugen_args=(image "$tn")
        generate_colors_material_args=(--path "$tn")
    else
        matugen_args=(); generate_colors_material_args=()
    fi
    GLOBAL_UPDATED=1
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"
    target_monitor="$6"
    group_mode="$7"

    read scale screenx screeny screensizey < <(hyprctl monitors -j | jq '.[] | select(.focused) | .scale, .x, .y, .height' | xargs)
    cursorposx=$(hyprctl cursorpos -j | jq '.x' 2>/dev/null) || cursorposx=960
    cursorposx=$(bc <<< "scale=0; ($cursorposx - $screenx) * $scale / 1")
    cursorposy=$(hyprctl cursorpos -j | jq '.y' 2>/dev/null) || cursorposy=540
    cursorposy=$(bc <<< "scale=0; ($cursorposy - $screeny) * $scale / 1")
    cursorposy_inverted=$((screensizey - cursorposy))

    local DEFAULT_MON="$(
        hyprctl workspaces -j \
            | jq -r '.[] | select((.id==1) or (.name=="1")) | .monitor' \
            | head -n1
    )"

    if [[ "$color_flag" == "1" ]]; then
        matugen_args=(color hex "$color")
        generate_colors_material_args=(--color "$color")
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        # For videos, ensure deps exist
        if is_video "$imgpath"; then
            local missing=()
            command -v mpvpaper &>/dev/null || missing+=("mpvpaper")
            command -v ffmpeg  &>/dev/null || missing+=("ffmpeg")
            if [ ${#missing[@]} -gt 0 ]; then
                echo "Missing deps: ${missing[*]}"
                echo "Arch: sudo pacman -S ${missing[*]}"
                action=$(notify-send -a "Wallpaper switcher" -c "im.error" \
                         -A "install_arch=Install (Arch)" \
                         "Can't switch to video wallpaper" \
                         "Missing dependencies: ${missing[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing[*]}"
                    if command -v mpvpaper &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi
        fi

        # --- APPLY -------------------------------------------------------------
        if [[ "$group_mode" == "1" ]]; then
            # GROUP MODE (unchanged behavior)
            GLOBAL_UPDATED=0
            local acting_mon="${target_monitor:-$DEFAULT_MON}"

            collect_group_actions "$imgpath" "$acting_mon"
            local other_matches_count=$(( ${#GROUP_IMAGES[@]} + ${#GROUP_VIDEOS[@]} ))

            if [[ "$other_matches_count" -eq 0 ]]; then
                # One file → apply to all
                if ! is_video "$imgpath"; then
                    for m in "${MONITORS[@]}"; do
                        kill_mpvpaper_for_monitor "$m" || true
                        set_wallpaper_path "$imgpath" "$m"
                        set_thumbnail_path "" "$m"
                    done
                    update_global_for_image "$imgpath"
                    remove_restore
                else
                    local vpairs=() m
                    for m in "${MONITORS[@]}"; do vpairs+=("$m|$imgpath"); done
                    start_videos_simul "${vpairs[@]}"
                    local tn; tn="$(snapshot_video_thumbnail "$imgpath")"
                    for m in "${MONITORS[@]}"; do
                        set_wallpaper_path "$imgpath" "$m"
                        [ -n "$tn" ] && set_thumbnail_path "$tn" "$m"
                    done
                    update_global_for_video "$imgpath"
                    create_restore_script
                fi
            else
                # Named/mixed group
                if is_video "$imgpath"; then GROUP_VIDEOS+=("$acting_mon|$imgpath"); else GROUP_IMAGES+=("$acting_mon|$imgpath"); fi

                # Images first
                local pair mon path
                for pair in "${GROUP_IMAGES[@]}"; do
                    mon="${pair%%|*}"; path="${pair#*|}"
                    kill_mpvpaper_for_monitor "$mon" || true
                    set_wallpaper_path "$path" "$mon"
                    set_thumbnail_path "" "$mon"
                done

                # Videos simult.
                if ((${#GROUP_VIDEOS[@]} > 0)); then
                    start_videos_simul "${GROUP_VIDEOS[@]}"
                    for pair in "${GROUP_VIDEOS[@]}"; do
                        mon="${pair%%|*}"; path="${pair#*|}"
                        set_wallpaper_path "$path" "$mon"
                        tn="$(snapshot_video_thumbnail "$path")"
                        [ -n "$tn" ] && set_thumbnail_path "$tn" "$mon"
                    done
                fi

                # Blank unmatched monitors (only if we had any match)
                if [[ "$other_matches_count" -gt 0 ]]; then
                    for mon in "${GROUP_BLANKS[@]}"; do
                        kill_mpvpaper_for_monitor "$mon" || true
                        clear_permonitor_for "$mon"
                    done
                fi

                # Global follows default monitor
                local def_candidate=""
                local dir; dir="$(dirname -- "$imgpath")"
                if [[ "$acting_mon" == "$DEFAULT_MON" ]]; then
                    def_candidate="$imgpath"
                else
                    if f="$(find_group_file_for_monitor "$dir" "$DEFAULT_MON")"; then def_candidate="$f"; fi
                fi
                if [[ -n "$def_candidate" ]]; then
                    if is_video "$def_candidate"; then update_global_for_video "$def_candidate"; create_restore_script
                    else update_global_for_image "$def_candidate"; fi
                fi
            fi

        else
            # NON-GROUP MODE (simple, restored behavior)
            local acting_mon
            if [[ -n "$target_monitor" ]]; then acting_mon="$target_monitor"; else acting_mon="$DEFAULT_MON"; fi

            if is_video "$imgpath"; then
                kill_mpvpaper_for_monitor "$acting_mon" || true
                spawn_mpvpaper "$acting_mon" "$imgpath"
                set_wallpaper_path "$imgpath" "$acting_mon"
                tn="$(snapshot_video_thumbnail "$imgpath")"
                [ -n "$tn" ] && set_thumbnail_path "$tn" "$acting_mon"

                # Update global only if acting on default (or no monitor flag)
                if [[ -z "$target_monitor" || "$acting_mon" == "$DEFAULT_MON" ]]; then
                    update_global_for_video "$imgpath"
                fi
            else
                kill_mpvpaper_for_monitor "$acting_mon" || true
                set_wallpaper_path "$imgpath" "$acting_mon"
                set_thumbnail_path "" "$acting_mon"

                if [[ -z "$target_monitor" || "$acting_mon" == "$DEFAULT_MON" ]]; then
                    update_global_for_image "$imgpath"
                fi
            fi
        fi
    fi

    # -- Theming (same as original) --------------------------------------------
    if [[ -z "$mode_flag" ]]; then
        current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        mode_flag=$([[ "$current_mode" == "prefer-dark" ]] && echo "dark" || echo "light")
    fi

    [[ -n "$mode_flag" ]] && matugen_args+=(--mode "$mode_flag") && generate_colors_material_args+=(--mode "$mode_flag")
    [[ -n "$type_flag"  ]] && matugen_args+=(--type "$type_flag") && generate_colors_material_args+=(--scheme "$type_flag")
    generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
    generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

    pre_process "$mode_flag"

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    # Set harmony and related properties
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && generate_colors_material_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
    fi

    matugen "${matugen_args[@]}" || true
    source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate" 2>/dev/null || true
    python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" \
        > "$STATE_DIR"/user/generated/material_colors.scss || true
    "$SCRIPT_DIR"/applycolor.sh || true
    deactivate 2>/dev/null || true

    local minw minh
    minw="$(hyprctl monitors -j | jq '([.[].width] | min)' | xargs)"
    minh="$(hyprctl monitors -j | jq '([.[].height] | min)' | xargs)"
    post_process "$minw" "$minh" "$imgpath"
}

# ---- MAIN --------------------------------------------------------------------
main() {
    local imgpath="" mode_flag="" type_flag="" color_flag="" color=""
    local noswitch_flag="" target_monitor="" group_mode="0"
    
    local -a MONITORS
    readarray -t MONITORS < <(hyprctl monitors -j | jq -r '.[].name')

    get_type_from_config() { jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"; }
    detect_scheme_type_from_image() { local img="$1"; "$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n'; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)     mode_flag="$2"; shift 2 ;;
            --type)     type_flag="$2"; shift 2 ;;
            --color)
                color_flag="1"
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then color="$2"; shift 2
                else color=$(hyprpicker --no-fancy); shift; fi
                ;;
            --image)    imgpath="$2"; shift 2 ;;
            --noswitch) noswitch_flag="1"; imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""); shift ;;
            --monitor)  target_monitor="$2"; shift 2 ;;
            --group)    group_mode="1"; shift ;;
            *)          if [[ -z "$imgpath" ]]; then imgpath="$1"; fi; shift ;;
        esac
    done

    if [[ -z "$type_flag" ]]; then type_flag="$(get_type_from_config)"; fi
    local allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
    local valid_type=0 t
    for t in "${allowed_types[@]}"; do [[ "$type_flag" == "$t" ]] && { valid_type=1; break; }; done
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    if [[ -z "$imgpath" && -z "$color_flag" && -z "$noswitch_flag" ]]; then
        cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null \
        || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null \
        || cd "$(xdg-user-dir PICTURES)" || return 1
        imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
    fi

    if [[ "$type_flag" == "auto" ]]; then
        if [[ -n "$imgpath" && -f "$imgpath" ]]; then
            local detected; detected="$(detect_scheme_type_from_image "$imgpath")"
            local ok=0; for t in "${allowed_types[@]}"; do [[ "$detected" == "$t" && "$detected" != "auto" ]] && { ok=1; break; }; done
            if [[ $ok -eq 1 ]]; then type_flag="$detected"
            else
                echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
                type_flag="scheme-tonal-spot"
            fi
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color" "$target_monitor" "$group_mode"
}

main "$@"