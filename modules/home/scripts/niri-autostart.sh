#!/usr/bin/env bash
# ==============================================================================
# Niri Autostart & Window Management Script
# ==============================================================================
# Скрипт автоматического запуска приложений Niri с поддержкой:
#  - Динамического ожидания окон (без фиксированных костыльных sleep)
#  - Вкладчатых колонок для экрана ноутбука (Spotify + Cassette + Cava)
#  - Строгой компоновки 1-main: [ LibreWolf | Obsidian | tmux ]
#  - Двух режимов работы: Внешний монитор (HDMI-A-2) vs Автономный (Laptop)
# ==============================================================================

# ------------------------------------------------------------------------------
# Вспомогательные функции
# ------------------------------------------------------------------------------

# Ожидание появления окна в Niri по шаблону имя/app-id
wait_window() {
    local pattern="$1"
    local max_attempts="${2:-30}"
    local delay="${3:-0.3}"

    for ((i=1; i<=max_attempts; i++)); do
        if niri msg windows | grep -iq "$pattern"; then
            sleep 0.3
            return 0
        fi
        sleep "$delay"
    done
    return 1
}

# Spotify's CEF renderer occasionally fails to pick up the resize into the
# tabbed column correctly when it launches under real cold-start CPU load
# (competing with noctalia/xray/ciadpi/cassette/cava all starting at once) -
# its content ends up taller than the column and renders past the bottom of
# the screen. Confirmed via niri's own IPC that replaying the exact same
# spawn/consume/tab sequence by hand on an already-idle session always
# produces correct, uniform tile sizes - so this is a startup-contention
# race, not a logic bug in the sequence itself, and no amount of sleeping
# before the tabbed-display toggle fixed it. Comparing Spotify's resulting
# height against Cassette's (which isn't affected) after the dust settles
# and relaunching it once if they don't match is the reliable fix: an
# unhurried restart later, after the rest of autostart has finished
# competing for CPU, has consistently produced the correct size.
fix_spotify_geometry_if_broken() {
    sleep 1
    local windows spotify_id spotify_h cassette_h diff
    windows=$(niri msg -j windows 2>/dev/null) || return 0
    spotify_id=$(echo "$windows" | jq -r '.[] | select(.app_id=="Spotify") | .id' | head -1)
    spotify_h=$(echo "$windows" | jq -r '.[] | select(.app_id=="Spotify") | .layout.tile_size[1]' | head -1)
    cassette_h=$(echo "$windows" | jq -r '.[] | select(.app_id=="space.rirusha.Cassette") | .layout.tile_size[1]' | head -1)
    [[ -z "$spotify_id" || -z "$spotify_h" || -z "$cassette_h" ]] && return 0

    diff=$(awk -v a="$spotify_h" -v b="$cassette_h" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
    if awk -v d="$diff" 'BEGIN{exit !(d>5)}'; then
        niri msg action close-window --id "$spotify_id" || true
        sleep 1
        spotify &
        wait_window "spotify" 20
        niri msg action consume-or-expel-window-left || true
        # consume-or-expel appends onto the end of cassette/cava's existing
        # column instead of the front (unlike the original spawn order,
        # where spotify was the anchor the others got consumed into) - walk
        # it back up to the first tab. move-window-up is a no-op once
        # already at the top, so a few extra calls are harmless.
        niri msg action move-window-up || true
        niri msg action move-window-up || true
    fi
}

# Obsidian's real Wayland app-id is "md.Obsidian" (capital O, "md." prefix -
# confirmed live via `niri msg -j windows`), not the lowercase "obsidian"
# window-rules used to assume. Since niri's app-id match is an exact regex
# match, not a case-insensitive substring, the 1-main window-rule (see
# niri.nix) never actually matched Obsidian at all - it opened with no
# open-maximized applied, so its column stayed at whatever default width
# Obsidian itself picked (usually wider than the other two, since it isn't
# clipped to the maximized-column gap the others get), which spilled the
# extra width off the edge of the screen. Fixed the rule to also match
# "md.Obsidian". This check stays as a safety net for the same kind of
# Electron/Chromium cold-start sizing race already seen with Spotify (see
# fix_spotify_geometry_if_broken above) in case one still slips through:
# compare Obsidian's width against tmux-dev's (unaffected, same rule/output)
# and re-trigger maximize-column (what Mod+F does manually) if they differ.
fix_obsidian_width_if_broken() {
    sleep 1
    local windows obsidian_id obsidian_w tmux_w diff
    windows=$(niri msg -j windows 2>/dev/null) || return 0
    obsidian_id=$(echo "$windows" | jq -r '.[] | select(.app_id=="md.Obsidian") | .id' | head -1)
    obsidian_w=$(echo "$windows" | jq -r '.[] | select(.app_id=="md.Obsidian") | .layout.tile_size[0]' | head -1)
    tmux_w=$(echo "$windows" | jq -r '.[] | select(.app_id=="tmux-dev") | .layout.tile_size[0]' | head -1)
    [[ -z "$obsidian_id" || -z "$obsidian_w" || -z "$tmux_w" ]] && return 0

    diff=$(awk -v a="$obsidian_w" -v b="$tmux_w" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
    if awk -v d="$diff" 'BEGIN{exit !(d>5)}'; then
        niri msg action focus-window --id "$obsidian_id" || true
        niri msg action maximize-column || true
    fi
}

# LibreWolf can take much longer than the others to map its first window
# (profile/extension init), so launching it and then blocking on wait_window
# before even starting Obsidian both stalls the whole sequence AND loses the
# ordering race: by the time LibreWolf's timeout expires and Obsidian is
# spawned, Obsidian ends up mapping (and becoming the focused/leftmost
# column) before LibreWolf. Fix: spawn all three in parallel, wait for all
# of them, then force the [ LibreWolf | Obsidian | tmux ] column order
# explicitly by id - independent of whatever order they actually mapped in.
setup_main_desktop() {
    librewolf &
    obsidian &
    alacritty --class tmux-dev -e tmux attach-session -t main &

    wait_window "librewolf" 150
    wait_window "obsidian" 60
    wait_window "tmux-dev" 30

    local windows lw_id ob_id tm_id
    windows=$(niri msg -j windows 2>/dev/null) || return 0
    lw_id=$(echo "$windows" | jq -r '.[] | select(.app_id=="LibreWolf" or .app_id=="librewolf") | .id' | head -1)
    ob_id=$(echo "$windows" | jq -r '.[] | select(.app_id=="md.Obsidian") | .id' | head -1)
    tm_id=$(echo "$windows" | jq -r '.[] | select(.app_id=="tmux-dev") | .id' | head -1)

    if [[ -n "$lw_id" ]]; then
        niri msg action focus-window --id "$lw_id" || true
        niri msg action move-column-to-first || true
    fi
    if [[ -n "$ob_id" ]]; then
        niri msg action focus-window --id "$ob_id" || true
        niri msg action move-column-to-index 2 || true
    fi
    if [[ -n "$tm_id" ]]; then
        niri msg action focus-window --id "$tm_id" || true
        niri msg action move-column-to-last || true
    fi

    fix_obsidian_width_if_broken

    niri msg action focus-workspace "1-main" || true
    niri msg action focus-column-first || true
}

# xdg-desktop-portal.service ловит гонку при холодной загрузке: первая
# DBus-активация происходит слишком рано, и после неё запросы к порталу
# (например ScreenCast для шаринга экрана в Discord) молча никуда не
# доходят - ни диалога, ни ошибки, ни трафика на шине. Подтверждено вживую:
# ни перезапуск клиента, ни повторные попытки это не лечат, а простой
# `systemctl --user restart xdg-desktop-portal.service` - лечит сразу и
# полностью (см. docs/repo-notes.md). sleep даёт демону сначала подняться в своём
# обычном (сбойном) состоянии, прежде чем мы его пересоздаём.
restart_portal_daemon() {
    sleep 5
    systemctl --user restart xdg-desktop-portal.service || true
}

# Инициализация фоновой сессии tmux (если еще не создана)
init_tmux_session() {
    if ! tmux has-session -t main 2>/dev/null; then
        tmux new-session -d -s main -n rebuild -c /home/nix/.nix nvim || true
        tmux new-window -t main:1 -n claude -c /home/nix/.nix claude || true
        tmux new-window -t main:2 -n sit_or_stand -c /home/nix/ /home/nix/Stuff/binaries/sit_or_stand.sh || true
        tmux select-window -t main:0 || true
    fi
}

# Запуск приложений медиа-панели на ноутбуке (eDP-1) в 1 вкладчатую колонку
setup_laptop_media() {
    # 1. Spotify
    # Spotify persists its own window geometry in ~/.config/spotify/prefs
    # and re-saves it (saved=true) on every exit, so a one-off edit doesn't
    # stick. On this laptop that saved height ends up taller than eDP-1's
    # usable space, and niri's own window-rule sizing (open-maximized /
    # default-window-height) can't force a correction - Spotify's Wayland
    # client commits its own buffer size regardless of what the compositor
    # suggests. Clear the restore flags before every launch instead.
    sed -i \
        -e 's/^app.window.state.saved=.*/app.window.state.saved=false/' \
        -e 's/^app.window.position.saved=.*/app.window.position.saved=false/' \
        "$HOME/.config/spotify/prefs" 2>/dev/null || true
    spotify &
    wait_window "spotify" 20

    # 2. Cassette
    cassette &
    wait_window "Cassette" 30
    niri msg action consume-or-expel-window-left || true

    # 3. Cava
    alacritty --class cava -e cava &
    wait_window "cava" 20
    niri msg action consume-or-expel-window-left || true

    # Объединяем 3 окна в вкладчатую колонку (1 окно во весь экран, переключение по Win+J/K)
    niri msg action toggle-column-tabbed-display || true

    fix_spotify_geometry_if_broken
}

# ------------------------------------------------------------------------------
# Основная логика запуска
# ------------------------------------------------------------------------------

# Чиним гонку xdg-desktop-portal.service параллельно с остальным
# автостартом (не блокирует, не зависит от окон - чистый DBus/systemd)
restart_portal_daemon &

# Подготовка tmux
init_tmux_session

# Проверка наличия внешнего монитора
EXTERNAL_OUTPUT="HDMI-A-2"

if niri msg outputs | grep -q "$EXTERNAL_OUTPUT"; then
    # ==========================================================================
    # РЕЖИМ 1: Подключен внешний монитор (HDMI-A-2)
    # ==========================================================================

    # Медиа-панель на дисплее ноутбука (Spotify + Cassette + Cava) - только
    # в этом режиме, без монитора её не открываем вовсе.
    setup_laptop_media

    # 1. Рабочий стол 1-main (слева направо: LibreWolf -> Obsidian -> tmux)
    setup_main_desktop

    # 2. Рабочий стол 2-vms (Виртуальные машины)
    virt-manager &
    wait_window "virt-manager" 30

    # 3. Рабочий стол 3-gaming (Стриминг / Игры)
    moonlight &
    wait_window "moonlight" 30

    # Возврат фокуса на главный рабочий стол и переход к левой колонке (LibreWolf)
    niri msg action focus-workspace "1-main" || true
    niri msg action focus-column-first || true

else
    # ==========================================================================
    # РЕЖИМ 2: Автономная работа (только экран ноутбука eDP-1)
    # ==========================================================================
    # Без монитора рабочий стол "1-main" просто остаётся на eDP-1 (в niri.nix
    # window-rules привязывают LibreWolf/Obsidian/tmux-dev к этому workspace
    # по app-id, а не жёстко к HDMI-A-2 - так что при отсутствии внешнего
    # монитора он естественным образом создаётся на единственном доступном
    # выходе). Открываем тот же базовый набор, что и в режиме с монитором,
    # но без virt-manager/moonlight - им HDMI-A-2 нужен явно.
    setup_main_desktop
fi
