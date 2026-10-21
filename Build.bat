@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Build.bat - собрать готовую программу: build\Shellbit\Shellbit.exe
rem  Просто двойной щелчок.
rem
rem  Что делает:
rem    1) если нет release-версии C++-модуля - собирает её (native\build.bat release);
rem    2) проверяет, что установлены шаблоны экспорта Godot;
rem    3) экспортирует проект по пресету "Windows Desktop" (export_presets.cfg).
rem
rem  ВАЖНО: закройте Godot перед сборкой C++-модуля, иначе .dll будет занята.
rem ==================================================================

cd /d "%~dp0"
set "ROOT=%CD%"
set "OUT=%ROOT%\build\Shellbit"

call "%ROOT%\tools\godot.bat" || goto :fail

rem --- 1. C++-модуль для готовой программы ---
set "DLL=addons\shellbit_core\bin\shellbit_core.windows.template_release.x86_64.dll"
if exist "%DLL%" goto :templates
echo.
echo === Нет release-версии C++-модуля, собираю её. Godot должен быть закрыт. ===
rem SHELLBIT_QUIET - чтобы native\build.bat не ждал нажатия клавиши в конце.
rem Потом возвращаем, как было: этот файл сам решает, ждать ли в конце.
set "WAS_QUIET=%SHELLBIT_QUIET%"
set "SHELLBIT_QUIET=1"
call native\build.bat release
set "SHELLBIT_QUIET=%WAS_QUIET%"
cd /d "%ROOT%"
if not exist "%DLL%" goto :fail

:templates
rem --- 2. Шаблоны экспорта ---
rem Godot отвечает на --version так: 4.7.2.stable.official.ed1daf0bf
rem Шаблоны лежат в папке с именем 4.7.2.stable (у версий без третьей цифры - 4.7.stable).
set "V4="
set "V3="
for /f "tokens=1-4 delims=." %%a in ('call "%GODOT_CONSOLE%" --version') do (
    set "V4=%%a.%%b.%%c.%%d"
    set "V3=%%a.%%b.%%c"
)
set "TPL=%APPDATA%\Godot\export_templates"
if exist "%TPL%\%V4%\windows_release_x86_64.exe" goto :export
if exist "%TPL%\%V3%\windows_release_x86_64.exe" goto :export
echo.
echo [?] Не вижу шаблонов экспорта для Godot %V4%.
echo     Если сборка ниже не получится, откройте проект в Godot:
echo     Редактор - Управление шаблонами экспорта - Загрузить и установить.

:export
rem --- 3. Экспорт ---
echo.
echo === Собираю Shellbit.exe ===
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
rem .gdignore - чтобы редактор Godot не просматривал папку сборки.
if not exist "%ROOT%\build\.gdignore" type nul > "%ROOT%\build\.gdignore"
"%GODOT_CONSOLE%" --headless --path "%ROOT%" --export-release "Windows Desktop" "%OUT%\Shellbit.exe"
if not exist "%OUT%\Shellbit.exe" goto :fail

echo.
echo === Готово! Программа лежит в build\Shellbit\ ===
if not defined SHELLBIT_QUIET explorer "%OUT%"
if not defined SHELLBIT_QUIET pause
exit /b 0

:fail
echo.
echo === Сборка не удалась. Скопируйте текст выше и покажите Claude. ===
if not defined SHELLBIT_QUIET pause
exit /b 1
