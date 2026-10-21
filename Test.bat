@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Test.bat - запустить автотесты Shellbit (папка test\).
rem  Просто двойной щелчок. Займёт около минуты.
rem
rem  Тесты меняют настройки, библиотеку и сохранения. Чтобы не тронуть
rem  настоящие, здесь подменяется APPDATA: Godot кладёт данные программы
rem  в %%APPDATA%%\Shellbit, а на время тестов это будет временная папка
rem  %%TEMP%%\shellbit-tests\Shellbit. Подмена действует только на это окно.
rem ==================================================================

cd /d "%~dp0"
set "ROOT=%CD%"

call "%ROOT%\tools\godot.bat" || goto :fail

set "APPDATA=%TEMP%\shellbit-tests"
if exist "%APPDATA%" rmdir /s /q "%APPDATA%"
mkdir "%APPDATA%"

rem Новые тесты (class_name TestCase и др.) Godot должен сначала «увидеть».
echo === Подготовка проекта ===
"%GODOT_CONSOLE%" --headless --path "%ROOT%" --import > "%APPDATA%\import.log" 2>&1

"%GODOT_CONSOLE%" --headless --path "%ROOT%" res://test/run_tests.tscn
set "CODE=%ERRORLEVEL%"

echo.
if "%CODE%"=="0" echo === Все тесты прошли ===
if "%CODE%"=="1" echo === Есть упавшие тесты - список выше, со значком x ===
if "%CODE%"=="2" echo === Тесты не запустились - причина выше ===
if not defined SHELLBIT_QUIET pause
exit /b %CODE%

:fail
if not defined SHELLBIT_QUIET pause
exit /b 2
