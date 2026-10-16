@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Сборка C++-модуля Shellbit (shellbit_core.dll).
rem  Просто запустите этот файл двойным щелчком.
rem  ВАЖНО: перед сборкой закройте Godot, иначе .dll будет занята.
rem
rem  build.bat          - отладочная версия (для редактора Godot)
rem  build.bat release  - версия для готового .exe
rem ==================================================================

cd /d "%~dp0"

set TARGET=template_debug
if /i "%1"=="release" set TARGET=template_release

rem --- 1. Ищем Visual Studio и включаем её компилятор ---
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [!] Visual Studio не найдена. Установите Build Tools - см. README.md
    goto :fail
)
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if not defined VSPATH (
    echo [!] В Visual Studio нет компонента C++. Добавьте "Разработка классических приложений на C++".
    goto :fail
)
call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul

rem --- 2. Проверяем Python и CMake ---
where python >nul 2>nul || (echo [!] Python не найден. Установите его с галочкой "Add python.exe to PATH". & goto :fail)
where cmake >nul 2>nul || (echo [!] CMake не найден. Добавьте в Visual Studio компонент "C++ CMake tools for Windows". & goto :fail)

rem --- 3. Скачиваем библиотеку godot-cpp (только при первом запуске) ---
if not exist "godot-cpp\CMakeLists.txt" (
    echo.
    echo === Скачиваю godot-cpp с GitHub... ===
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/godotengine/godot-cpp/archive/refs/tags/godot-4.5-stable.zip' -OutFile 'godot-cpp.zip'; Expand-Archive -Path 'godot-cpp.zip' -DestinationPath '.' -Force; if (Test-Path 'godot-cpp') { Remove-Item 'godot-cpp' -Recurse -Force }; Rename-Item 'godot-cpp-godot-4.5-stable' 'godot-cpp'; Remove-Item 'godot-cpp.zip'" || goto :fail
)

rem --- 4. Сборка ---
rem Временные файлы сборки кладём в %LOCALAPPDATA%, а не рядом с проектом:
rem их сотни мегабайт, и Яндекс.Диску незачем их синхронизировать.
set "BUILD_DIR=%LOCALAPPDATA%\Shellbit-build\%TARGET%"
echo.
echo === Сборка %TARGET% (первый раз - 5-15 минут) ===
cmake -S . -B "%BUILD_DIR%" -G Ninja -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=%TARGET% || goto :fail
cmake --build "%BUILD_DIR%" || goto :fail

echo.
echo === Готово! Файл лежит в addons\shellbit_core\bin\ ===
echo Теперь откройте проект в Godot.
pause
exit /b 0

:fail
echo.
echo === Сборка не удалась. Скопируйте текст выше и покажите Claude. ===
pause
exit /b 1
