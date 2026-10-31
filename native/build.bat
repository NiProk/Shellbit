@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Сборка C++-модуля Shellbit (shellbit_core.dll).
rem  Просто запустите этот файл двойным щелчком.
rem  ВАЖНО: перед сборкой закройте Godot, иначе .dll будет занята.
rem
rem  build.bat          - обе версии сразу (так проще не запутаться):
rem                       отладочная - для редактора Godot и Run.bat,
rem                       release    - для готового Shellbit.exe (Build.bat)
rem  build.bat debug    - только отладочная
rem  build.bat release  - только release
rem  Если код C++ не менялся, сборка занимает пару секунд.
rem ==================================================================

cd /d "%~dp0"

set "TARGETS=template_debug template_release"
if /i "%1"=="debug" set "TARGETS=template_debug"
if /i "%1"=="release" set "TARGETS=template_release"

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

rem --- 4. Сборка: каждой версии по очереди (подпрограмма :build ниже) ---
for %%T in (%TARGETS%) do (
    call :build %%T || goto :fail
)

echo.
echo === Готово! Файл лежит в addons\shellbit_core\bin\ ===
echo Теперь откройте проект в Godot.
if not defined SHELLBIT_QUIET pause
exit /b 0

:fail
echo.
echo === Сборка не удалась. Скопируйте текст выше и покажите Claude. ===
if not defined SHELLBIT_QUIET pause
exit /b 1


rem ==================================================================
rem  Подпрограмма: собрать одну версию. %~1 - template_debug или template_release.
rem  call :build ... - «вызвать» её; exit /b - вернуться (1 - ошибка).
rem ==================================================================
:build
rem Временные файлы сборки кладём в %LOCALAPPDATA%, а не рядом с проектом:
rem их сотни мегабайт, и Яндекс.Диску незачем их синхронизировать.
set "BUILD_DIR=%LOCALAPPDATA%\Shellbit-build\%~1"

rem Временные файлы помнят, в какой папке лежал проект. Если проект
rem переносили (например, с Яндекс.Диска в D:\Programming), CMake
rem отказывается работать: "source ... does not match the source ...".
rem Тогда просто удаляем старые временные файлы - они создадутся заново.
rem %CD:\=/% - текущая папка, где \ заменены на / (так её пишет CMake).
set "HERE=%CD:\=/%"
if exist "%BUILD_DIR%\CMakeCache.txt" (
    findstr /i /c:"CMAKE_HOME_DIRECTORY:INTERNAL=%HERE%" "%BUILD_DIR%\CMakeCache.txt" >nul || (
        echo Проект переносили в другую папку - удаляю старые временные файлы сборки...
        rmdir /s /q "%BUILD_DIR%"
    )
)

echo.
echo === Сборка %~1 (первый раз - 5-15 минут) ===
cmake -S . -B "%BUILD_DIR%" -G Ninja -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=%~1 || exit /b 1
cmake --build "%BUILD_DIR%" || exit /b 1
exit /b 0
