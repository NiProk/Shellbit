#!/usr/bin/env bash
# ==================================================================
#  Сборка C++-модуля Shellbit для Linux (shellbit_core....so).
#  Linux-версия build.bat. Двойной щелчок (или ./build.sh в терминале).
#
#  build.sh          — обе версии сразу (так проще не запутаться):
#                      отладочная — для редактора Godot и Run.sh,
#                      release    — для готовой программы (Build.sh)
#  build.sh debug    — только отладочная
#  build.sh release  — только release
#  Если код C++ не менялся, сборка занимает пару секунд.
#
#  Что нужно установить один раз (CachyOS / Arch):
#    sudo pacman -S --needed base-devel cmake ninja python git
#  (Ubuntu / Mint: sudo apt install build-essential cmake ninja-build python3 git)
# ==================================================================

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(dirname "$HERE")"
source "$ROOT/tools/common.sh"
open_terminal "$@"
cd "$HERE" || exit 1

fail() {
    echo
    echo "=== Сборка не удалась. Скопируйте текст выше и покажите Claude. ==="
    finish 1
}

TARGETS="template_debug template_release"
[ "$1" = "debug" ] && TARGETS="template_debug"
[ "$1" = "release" ] && TARGETS="template_release"

# --- 1. Проверяем инструменты ---
missing=""
for tool in cmake g++ python3; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "[!] Не хватает программ:$missing"
    echo "    CachyOS / Arch:  sudo pacman -S --needed base-devel cmake ninja python git"
    echo "    Ubuntu / Mint:   sudo apt install build-essential cmake ninja-build python3 git"
    fail
fi
# Ninja быстрее, но если его нет — подойдёт и обычный make.
GENERATOR="Unix Makefiles"
command -v ninja >/dev/null 2>&1 && GENERATOR="Ninja"

# --- 2. Скачиваем библиотеку godot-cpp (только при первом запуске) ---
# Если проект пришёл из Windows вместе с папкой godot-cpp — она подойдёт:
# это исходники, они одинаковые для всех систем.
if [ ! -f "godot-cpp/CMakeLists.txt" ]; then
    echo
    echo "=== Скачиваю godot-cpp с GitHub... ==="
    git clone --depth 1 -b godot-4.5-stable https://github.com/godotengine/godot-cpp.git godot-cpp || fail
fi

# --- 3. Сборка: каждой версии по очереди ---
for TARGET in $TARGETS; do
    # Временные файлы сборки — в ~/.cache, а не рядом с проектом:
    # их сотни мегабайт, и синхронизировать их незачем.
    BUILD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/shellbit-build/$TARGET"
    # Временные файлы помнят, в какой папке лежал проект. Если проект
    # переносили, CMake отказывается работать ("source ... does not match").
    # Тогда удаляем старые временные файлы — они создадутся заново.
    if [ -f "$BUILD_DIR/CMakeCache.txt" ] && ! grep -qF "CMAKE_HOME_DIRECTORY:INTERNAL=$HERE" "$BUILD_DIR/CMakeCache.txt"; then
        echo "Проект переносили в другую папку — удаляю старые временные файлы сборки..."
        rm -rf "$BUILD_DIR"
    fi
    echo
    echo "=== Сборка $TARGET (первый раз — 5–15 минут) ==="
    cmake -S . -B "$BUILD_DIR" -G "$GENERATOR" -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=$TARGET || fail
    # nproc — сколько ядер у процессора: собираем на всех сразу.
    cmake --build "$BUILD_DIR" -j "$(nproc)" || fail
done

echo
echo "=== Готово! Файл лежит в addons/shellbit_core/bin/ ==="
echo "Теперь откройте проект в Godot."
finish 0
