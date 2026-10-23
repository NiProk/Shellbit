#!/usr/bin/env bash
# ==================================================================
#  Build.sh — собрать готовую программу для Linux и Steam Deck:
#  build/Shellbit-linux/Shellbit.x86_64
#  Linux-версия Build.bat. Двойной щелчок (или ./Build.sh в терминале).
#
#  Что делает:
#    1) если нет release-версии C++-модуля — собирает её (native/build.sh release);
#    2) проверяет, что установлены шаблоны экспорта Godot;
#    3) экспортирует проект по пресету "Linux" (export_presets.cfg).
# ==================================================================

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$ROOT/tools/common.sh"
open_terminal "$@"
cd "$ROOT" || finish 1
OUT="$ROOT/build/Shellbit-linux"

fail() {
    echo
    echo "=== Сборка не удалась. Скопируйте текст выше и покажите Claude. ==="
    finish 1
}

find_godot || fail

# --- 1. C++-модуль для готовой программы ---
SO="addons/shellbit_core/bin/shellbit_core.linux.template_release.x86_64.so"
if [ ! -f "$SO" ]; then
    echo
    echo "=== Нет release-версии C++-модуля, собираю её ==="
    SHELLBIT_QUIET=1 bash native/build.sh release || fail
    [ -f "$SO" ] || fail
fi

# --- 2. Шаблоны экспорта ---
# Godot отвечает на --version так: 4.7.2.stable.official.ed1daf0bf
# Шаблоны лежат в папке 4.7.2.stable — берём первые четыре части.
VERSION="$("$GODOT" --headless --version 2>/dev/null | tail -n 1 | cut -d. -f1-4)"
TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION"
if [ ! -f "$TPL/linux_release.x86_64" ]; then
    echo
    echo "[?] Не вижу шаблонов экспорта для Godot $VERSION."
    echo "    Если сборка ниже не получится, откройте проект в Godot:"
    echo "    Редактор → Управление шаблонами экспорта → Загрузить и установить."
fi

# --- 3. Экспорт ---
echo
echo "=== Собираю Shellbit для Linux ==="
rm -rf "$OUT"
mkdir -p "$OUT"
# .gdignore — чтобы редактор Godot не просматривал папку сборки.
touch "$ROOT/build/.gdignore"
"$GODOT" --headless --path "$ROOT" --export-release "Linux" "$OUT/Shellbit.x86_64"
[ -f "$OUT/Shellbit.x86_64" ] || fail
chmod +x "$OUT/Shellbit.x86_64"

echo
echo "=== Готово! Программа лежит в build/Shellbit-linux/ ==="
if [ -z "$SHELLBIT_QUIET" ]; then
    xdg-open "$OUT" >/dev/null 2>&1 &
fi
finish 0
