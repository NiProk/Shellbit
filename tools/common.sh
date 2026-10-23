# ==================================================================
#  Общие помощники для .sh-файлов Shellbit (Linux, Steam Deck).
#  Сам по себе не запускается — его подключают другие файлы:
#    source "$ROOT/tools/common.sh"
#
#  Linux-версия того, что в Windows делает tools/godot.bat, плюс две мелочи:
#    open_terminal  — если файл запустили двойным щелчком (без окна
#                     терминала), открыть терминал, чтобы было видно, что
#                     происходит;
#    finish         — «Нажмите Enter, чтобы закрыть окно» в конце.
#    find_godot     — найти Godot и записать путь в переменную GODOT.
# ==================================================================

# Перезапустить вызвавший файл в окне терминала, если окна нет.
# [ -t 1 ] — «вывод идёт в терминал?». При двойном щелчке в Dolphin — нет.
open_terminal() {
    if [ -t 1 ] || [ -n "$SHELLBIT_QUIET" ] || [ -n "$SHELLBIT_IN_TERMINAL" ]; then
        return 0
    fi
    export SHELLBIT_IN_TERMINAL=1
    local script
    script="$(readlink -f "$0")"
    # Перебираем терминалы, которые бывают в Linux. Первый найденный — наш.
    for term in konsole gnome-terminal kgx xfce4-terminal alacritty kitty xterm; do
        if command -v "$term" >/dev/null 2>&1; then
            case "$term" in
                gnome-terminal|kgx) exec "$term" -- bash "$script" "$@" ;;
                *)                  exec "$term" -e bash "$script" "$@" ;;
            esac
        fi
    done
    # Терминала нет — работаем молча.
}

# Пауза в конце, чтобы окно терминала не закрылось сразу.
finish() {
    local code="${1:-0}"
    if [ -z "$SHELLBIT_QUIET" ] && [ -n "$SHELLBIT_IN_TERMINAL" ]; then
        echo
        read -r -p "Нажмите Enter, чтобы закрыть окно…" _
    fi
    exit "$code"
}

# Найти Godot. Где ищем, по порядку:
#   1) файл godot_path_linux.txt в папке проекта (путь запоминается сам;
#      у Windows свой godot_path.txt — они не мешают друг другу);
#   2) godot или godot4 в системе (например, после «sudo pacman -S godot»);
#   3) Godot_v4.*_linux.x86_64 в папке «Загрузки»;
#   4) спрашиваем: перетащите файл Godot в окно терминала.
# Godot переехал? Удалите godot_path_linux.txt — путь спросится заново.
find_godot() {
    local path_file="$ROOT/godot_path_linux.txt"
    GODOT=""
    if [ -f "$path_file" ]; then
        GODOT="$(head -n 1 "$path_file")"
        [ -x "$GODOT" ] && return 0
        GODOT=""
    fi

    for name in godot godot4; do
        if command -v "$name" >/dev/null 2>&1; then
            GODOT="$(command -v "$name")"
            break
        fi
    done
    if [ -z "$GODOT" ]; then
        # ls -t — самый свежий файл первым.
        GODOT="$(ls -t "$HOME"/Downloads/Godot_v4*_linux.x86_64 "$HOME"/Загрузки/Godot_v4*_linux.x86_64 2>/dev/null | head -n 1)"
    fi
    if [ -z "$GODOT" ]; then
        echo
        echo "Не нашёл Godot."
        echo "Перетащите в это окно файл Godot, например Godot_v4.7.2-stable_linux.x86_64,"
        read -r -p "и нажмите Enter: " GODOT
        # Терминал добавляет кавычки вокруг перетащенного пути — убираем их.
        GODOT="${GODOT//\'/}"
        GODOT="${GODOT//\"/}"
        GODOT="$(echo "$GODOT" | xargs)"  # и пробелы по краям
    fi
    if [ -z "$GODOT" ] || [ ! -f "$GODOT" ]; then
        echo "[!] Файл Godot не найден: \"$GODOT\""
        return 1
    fi
    # Скачанный с сайта Godot ещё не помечен как программа — помечаем.
    [ -x "$GODOT" ] || chmod +x "$GODOT"
    echo "$GODOT" > "$path_file"
    echo "Путь к Godot запомнен в godot_path_linux.txt"
    return 0
}
