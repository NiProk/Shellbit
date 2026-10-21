@echo off
rem ==================================================================
rem  Находит Godot и записывает путь в переменные:
rem    GODOT          - обычный Godot (с окном) - для Run.bat
rem    GODOT_CONSOLE  - консольный Godot (пишет сообщения в окно сборки)
rem
rem  Сам по себе не запускается - его вызывают Build.bat, Run.bat
rem  и Publish.bat:  call "%~dp0tools\godot.bat"
rem
rem  Где ищем, по порядку:
rem    1) файл godot_path.txt в папке проекта (путь запоминается сам);
rem    2) godot.exe в PATH;
rem    3) спрашиваем: перетащите .exe Godot в окно.
rem  Godot переехал? Удалите godot_path.txt - путь спросится заново.
rem
rem  Здесь нет setlocal: переменные должны дожить до вызвавшего файла.
rem ==================================================================

set "PATH_FILE=%~dp0..\godot_path.txt"
set "GODOT="

if exist "%PATH_FILE%" set /p GODOT=<"%PATH_FILE%"
if defined GODOT if exist "%GODOT%" goto :found

set "GODOT="
for /f "delims=" %%i in ('where godot.exe 2^>nul') do if not defined GODOT set "GODOT=%%i"
if defined GODOT goto :remember

echo.
echo Не нашёл Godot.
echo Перетащите в это окно файл Godot, например Godot_v4.7.2-stable_win64.exe,
echo и нажмите Enter:
set /p "GODOT="
if not defined GODOT goto :missing
rem Убираем кавычки, которые Windows добавляет при перетаскивании.
set "GODOT=%GODOT:"=%"
if not exist "%GODOT%" goto :missing

:remember
> "%PATH_FILE%" echo %GODOT%
echo Путь к Godot запомнен в godot_path.txt

:found
rem Рядом с Godot_v4.7.2-stable_win64.exe обычно лежит
rem Godot_v4.7.2-stable_win64_console.exe - для сборки берём его.
set "GODOT_CONSOLE=%GODOT%"
set "TRY=%GODOT:.exe=_console.exe%"
if exist "%TRY%" set "GODOT_CONSOLE=%TRY%"
exit /b 0

:missing
echo [!] Файл Godot не найден: "%GODOT%"
exit /b 1
