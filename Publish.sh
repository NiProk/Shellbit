#!/usr/bin/env bash
# ==================================================================
#  Publish.sh — проверить тестами, собрать программу для Linux и упаковать
#  её в архив для раздачи: dist/Shellbit-<версия>-linux.tar.gz
#  Linux-версия Publish.bat.
#
#  Почему .tar.gz, а не .zip: в tar сохраняется пометка «это программа»
#  (право на запуск). Из zip Shellbit.x86_64 распаковался бы как простой
#  файл, и его пришлось бы помечать вручную.
#
#  Версия берётся из project.godot (application/config/version).
# ==================================================================

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$ROOT/tools/common.sh"
open_terminal "$@"
cd "$ROOT" || exit 1

fail() {
    echo
    echo "=== Выпуск не удался. Скопируйте текст выше и покажите Claude. ==="
    SHELLBIT_QUIET="" finish 1
}

# --- 0. Автотесты: упал хоть один — выпуск не делаем ---
export SHELLBIT_QUIET=1
bash "$ROOT/Test.sh" || fail

# --- 1. Сборка ---
bash "$ROOT/Build.sh" || fail

# --- 2. Версия из project.godot ---
# Строка там такая: config/version="0.1.0" — берём то, что в кавычках.
VER="$(grep '^config/version=' project.godot | cut -d'"' -f2)"
[ -n "$VER" ] || VER="dev"

# --- 3. Архив ---
mkdir -p dist
touch dist/.gdignore
ARCHIVE="dist/Shellbit-$VER-linux.tar.gz"
rm -f "$ARCHIVE"
echo
echo "=== Упаковываю $ARCHIVE ==="
# -C build — войти в папку build, чтобы в архиве лежала папка
# Shellbit (а не build/Shellbit-linux): распаковал — и запускай.
tar -czf "$ARCHIVE" -C build --transform 's/^Shellbit-linux/Shellbit/' Shellbit-linux || fail

echo
echo "=== Готово: $ARCHIVE ==="
unset SHELLBIT_QUIET
xdg-open dist >/dev/null 2>&1 &
finish 0
