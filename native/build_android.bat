@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Сборка C++-модуля Shellbit для Android (телефоны и TV-приставки).
rem  Получается addons\shellbit_core\bin\libshellbit_core.android.*.arm64.so
rem
rem  Нужна, ТОЛЬКО если менялся код C++ (папка native\src): готовые
rem  .so уже лежат в проекте, и Build-Android.bat берёт их.
rem
rem  Первый запуск скачает компилятор Android NDK (около 1 ГБ) и CMake -
rem  это может занять полчаса. Дальше - пара минут.
rem
rem  arm64 - процессоры почти всех телефонов и приставок последних лет.
rem ==================================================================

cd /d "%~dp0"

rem --- 1. NDK, CMake и Ninja ---
call "%~dp0..\tools\android.bat" ndk || goto :fail

rem --- 2. Python (godot-cpp генерирует им свой код) ---
where python >nul 2>nul || (echo [!] Python не найден. Установите его с галочкой "Add python.exe to PATH". & goto :fail)

rem --- 3. godot-cpp: если ещё нет - качает native\build.bat ---
if not exist "godot-cpp\CMakeLists.txt" (
    echo [!] Нет папки native\godot-cpp. Сначала запустите native\build.bat - он её скачает.
    goto :fail
)

rem --- 4. Сборка: отладочная и release ---
for %%T in (template_debug template_release) do (
    call :build %%T || goto :fail
)

echo.
echo === Готово! Файлы лежат в addons\shellbit_core\bin\ ===
if not defined SHELLBIT_QUIET pause
exit /b 0

:fail
echo.
echo === Сборка не удалась. Скопируйте текст выше и покажите Claude. ===
if not defined SHELLBIT_QUIET pause
exit /b 1


rem ==================================================================
rem  Собрать одну версию. %~1 - template_debug или template_release.
rem ==================================================================
:build
set "BUILD_DIR=%LOCALAPPDATA%\Shellbit-build\android-%~1"
set "HERE=%CD:\=/%"
if exist "%BUILD_DIR%\CMakeCache.txt" (
    findstr /i /c:"CMAKE_HOME_DIRECTORY:INTERNAL=%HERE%" "%BUILD_DIR%\CMakeCache.txt" >nul || (
        echo Проект переносили в другую папку - удаляю старые временные файлы сборки...
        rmdir /s /q "%BUILD_DIR%"
    )
)

echo.
echo === Сборка для Android: %~1 (первый раз - 5-15 минут) ===
rem Toolchain-файл из NDK говорит CMake: «собирай не для Windows, а для Android».
rem ANDROID_PLATFORM=android-24 - самая старая версия Android, где заработает (7.0);
rem ANDROID_STL=c++_static - библиотеку C++ вшить внутрь .so.
"%ANDROID_CMAKE%\cmake.exe" -S . -B "%BUILD_DIR%" -G Ninja ^
    -DCMAKE_MAKE_PROGRAM="%ANDROID_CMAKE%\ninja.exe" ^
    -DCMAKE_TOOLCHAIN_FILE="%ANDROID_NDK%\build\cmake\android.toolchain.cmake" ^
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_static ^
    -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=%~1 || exit /b 1
"%ANDROID_CMAKE%\cmake.exe" --build "%BUILD_DIR%" || exit /b 1
exit /b 0
