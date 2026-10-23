#!/usr/bin/env bash
# ==================================================================
#  Run.sh — запустить Shellbit из проекта, без открытия редактора.
#  Linux-версия Run.bat. Двойной щелчок (или ./Run.sh в терминале).
# ==================================================================

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$ROOT/tools/common.sh"

if ! find_godot; then
    open_terminal "$@"  # чтобы человек увидел, что не так
    finish 1
fi

# setsid + & — запустить и сразу отпустить: этот файл не ждёт конца игры.
setsid "$GODOT" --path "$ROOT" >/dev/null 2>&1 &
exit 0
