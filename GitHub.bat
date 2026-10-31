@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  GitHub.bat - отправить изменения на GitHub (github.com/NiProk/Shellbit).
rem  Просто двойной щелчок.
rem
rem  Что делает:
rem    1) находит Git (обычный или тот, что внутри GitHub Desktop);
rem    2) показывает, какие файлы изменились;
rem    3) спрашивает, что изменилось, и делает коммит - «снимок» проекта
rem       с этой подписью;
rem    4) отправляет коммиты на GitHub (git push).
rem
rem  Что НЕ попадает на GitHub - написано в .gitignore (кеш Godot,
rem  готовые сборки, ключ подписи Android, godot-cpp).
rem ==================================================================

cd /d "%~dp0"

rem --- 1. Ищем Git ---
set "GIT="
where git >nul 2>nul && set "GIT=git"
if not defined GIT if exist "%ProgramFiles%\Git\cmd\git.exe" set "GIT=%ProgramFiles%\Git\cmd\git.exe"
rem GitHub Desktop хранит свой Git в папке своей версии: app-3.4.9 и т.п.
rem Цикл перебирает их все - останется последняя.
if not defined GIT for /d %%d in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do (
    if exist "%%d\resources\app\git\cmd\git.exe" set "GIT=%%d\resources\app\git\cmd\git.exe"
)
if not defined GIT (
    echo [!] Не нашёл Git. Установите его: https://git-scm.com/download/win
    echo     ^(или GitHub Desktop: https://desktop.github.com/^) и запустите снова.
    goto :fail
)

rem --- 2. Убираем из Git то, что теперь в .gitignore ---
rem Папки .godot и native\godot-cpp раньше попали в репозиторий.
rem --cached - убрать только из Git, файлы на диске остаются.
rem --ignore-unmatch - не ругаться, если их там уже нет.
"%GIT%" rm -r -q --cached --ignore-unmatch .godot native/godot-cpp >nul

rem --- 3. Что изменилось ---
"%GIT%" add -A || goto :fail
echo.
echo === Изменённые файлы (A - новый, M - изменён, D - удалён) ===
"%GIT%" status --short
echo.

rem diff --cached --quiet: «тихо» сравнить - код 0, если изменений нет.
"%GIT%" diff --cached --quiet
if not errorlevel 1 (
    echo Новых изменений нет - просто отправляю то, что ещё не отправлено.
    goto :push
)

set "MSG="
set /p "MSG=Коротко, что изменилось (Enter - «Обновление»): "
if not defined MSG set "MSG=Обновление"
"%GIT%" commit -q -m "%MSG%" || goto :fail

:push
echo.
echo === Отправляю на GitHub... ===
"%GIT%" push || goto :fail
echo.
echo === Готово! https://github.com/NiProk/Shellbit ===
pause
exit /b 0

:fail
echo.
echo === Не получилось. Скопируйте текст выше и покажите Claude. ===
pause
exit /b 1
