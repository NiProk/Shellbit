@echo off
rem ==================================================================
rem  Инструменты для сборки под Android: Java и Android SDK.
rem  Сам по себе не запускается - его вызывают Build-Android.bat
rem  и native\build_android.bat:  call "%~dp0tools\android.bat"
rem
rem  Чего нет - скачивает сам (один раз) в %LOCALAPPDATA%\Android:
rem    jdk17      - Java 17 от Microsoft (~190 МБ): ею Android подписывает APK;
rem    Sdk        - Android SDK, туда же ставит Android Studio, если её
rem                 когда-нибудь установить - она найдёт всё готовое:
rem      platform-tools - программа adb: ставит APK на телефон по USB;
rem      build-tools    - apksigner: подписывает APK;
rem    и только для сборки C++-модуля (call ... android.bat ndk):
rem      ndk            - компилятор C++ под процессоры телефонов (~1 ГБ);
rem      cmake          - CMake и Ninja, которые им управляют.
rem
rem  Записывает в переменные: ANDROID_HOME, JAVA_HOME, ANDROID_NDK,
rem  ANDROID_CMAKE (папка с cmake.exe и ninja.exe), ADB.
rem  Здесь нет setlocal: переменные должны дожить до вызвавшего файла.
rem ==================================================================

set "ANDROID_ROOT=%LOCALAPPDATA%\Android"
set "ANDROID_HOME=%ANDROID_ROOT%\Sdk"
set "JAVA_HOME=%ANDROID_ROOT%\jdk17"
set "ANDROID_NDK_VERSION=27.2.12479018"
set "ANDROID_NDK=%ANDROID_HOME%\ndk\%ANDROID_NDK_VERSION%"
set "ANDROID_CMAKE=%ANDROID_HOME%\cmake\3.31.6\bin"
set "ANDROID_BUILD_TOOLS=36.0.0"
set "SDKMANAGER=%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat"
set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
set "NEED_NDK="
if /i "%~1"=="ndk" set "NEED_NDK=1"
if not exist "%ANDROID_ROOT%" mkdir "%ANDROID_ROOT%"

rem --- 1. Java ---
if exist "%JAVA_HOME%\bin\java.exe" goto :have_java
echo.
echo === Скачиваю Java 17 (около 190 МБ, один раз)... ===
call :download "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip" "%ANDROID_ROOT%\jdk.zip" || exit /b 1
tar -xf "%ANDROID_ROOT%\jdk.zip" -C "%ANDROID_ROOT%" || exit /b 1
del "%ANDROID_ROOT%\jdk.zip"
rem В архиве папка с номером версии, например jdk-17.0.13+11 - даём ей простое имя.
for /d %%d in ("%ANDROID_ROOT%\jdk-17*") do move "%%d" "%JAVA_HOME%" >nul
if not exist "%JAVA_HOME%\bin\java.exe" (
    echo [!] Java не распаковалась в %JAVA_HOME%
    exit /b 1
)
:have_java

rem --- 2. Менеджер Android SDK (sdkmanager) ---
if exist "%SDKMANAGER%" goto :have_tools
echo.
echo === Скачиваю Android SDK (около 150 МБ, один раз)... ===
if not exist "%ANDROID_HOME%\cmdline-tools" mkdir "%ANDROID_HOME%\cmdline-tools"
call :download "https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip" "%ANDROID_HOME%\cmdline-tools\tools.zip" || exit /b 1
tar -xf "%ANDROID_HOME%\cmdline-tools\tools.zip" -C "%ANDROID_HOME%\cmdline-tools" || exit /b 1
del "%ANDROID_HOME%\cmdline-tools\tools.zip"
rem sdkmanager хочет лежать в cmdline-tools\latest, а в архиве папка называется cmdline-tools.
move "%ANDROID_HOME%\cmdline-tools\cmdline-tools" "%ANDROID_HOME%\cmdline-tools\latest" >nul
if not exist "%SDKMANAGER%" (
    echo [!] Android SDK не распаковался в %ANDROID_HOME%
    exit /b 1
)
:have_tools

rem --- 3. Части SDK, которых не хватает ---
if not exist "%ADB%" call :install "platform-tools" || exit /b 1
if not exist "%ANDROID_HOME%\build-tools\%ANDROID_BUILD_TOOLS%\apksigner.bat" call :install "build-tools;%ANDROID_BUILD_TOOLS%" || exit /b 1
if not defined NEED_NDK exit /b 0
if not exist "%ANDROID_NDK%\build\cmake\android.toolchain.cmake" call :install "ndk;%ANDROID_NDK_VERSION%" || exit /b 1
if not exist "%ANDROID_CMAKE%\cmake.exe" call :install "cmake;3.31.6" || exit /b 1
exit /b 0


rem ==================================================================
rem  Подпрограммы
rem ==================================================================

rem Скачать файл: %1 - адрес, %2 - куда сохранить.
:download
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%~1' -OutFile '%~2'"
if not exist "%~2" (
    echo [!] Не скачалось: %~1
    exit /b 1
)
exit /b 0

rem Установить часть SDK: %1 - её имя, например "build-tools;36.0.0".
rem Перед установкой Google просит согласиться с лицензиями - отвечаем «y» за нас.
:install
echo.
echo === Устанавливаю %~1 (один раз)... ===
(for /l %%i in (1,1,30) do @echo y) | "%SDKMANAGER%" --sdk_root="%ANDROID_HOME%" --licenses >nul 2>&1
call "%SDKMANAGER%" --sdk_root="%ANDROID_HOME%" "%~1"
if errorlevel 1 (
    echo [!] Не удалось установить %~1
    exit /b 1
)
exit /b 0
