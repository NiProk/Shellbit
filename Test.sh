#!/usr/bin/env bash
# ==================================================================
#  Test.sh — запустить автотесты Shellbit (папка test/).
#  Linux-версия Test.bat. Займёт около минуты.
#
#  Тесты меняют настройки, библиотеку и сохранения. Чтобы не тронуть
#  настоящие, здесь подменяется XDG_DATA_HOME: Godot кладёт данные
#  программы в ~/.local/share/Shellbit, а на время тестов это будет
#  временная папка /tmp/shellbit-tests/Shellbit.
# ==================================================================

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$ROOT/tools/common.sh"
open_terminal "$@"

find_godot || finish 2

export XDG_DATA_HOME="/tmp/shellbit-tests"
rm -rf "$XDG_DATA_HOME"
mkdir -p "$XDG_DATA_HOME"

# Новые тесты (class_name TestCase и др.) Godot должен сначала «увидеть».
echo "=== Подготовка проекта ==="
"$GODOT" --headless --path "$ROOT" --import > "$XDG_DATA_HOME/import.log" 2>&1

"$GODOT" --headless --path "$ROOT" res://test/run_tests.tscn
CODE=$?

echo
case $CODE in
    0) echo "=== Все тесты прошли ===" ;;
    1) echo "=== Есть упавшие тесты — список выше, со значком ✗ ===" ;;
    *) echo "=== Тесты не запустились — причина выше ===" ;;
esac
finish $CODE
