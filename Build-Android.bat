@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Build-Android.bat - собрать Shellbit для Android: build\Shellbit.apk
rem  и, если телефон подключён по USB, сразу поставить на него.
rem  Просто двойной щелчок. Godot перед этим закройте.
rem
rem  Первый раз скачает Java и Android SDK (около 350 МБ) в
rem  %LOCALAPPDATA%\Android - это 5-10 минут. Дальше - около минуты.
rem
rem  Что делает:
rem    1) находит (или скачивает) Java и Android SDK - tools\android.bat;
rem    2) создаёт ключ подписи keystore\shellbit.keystore (один раз);
rem    3) прописывает пути к SDK и Java в настройки редактора Godot;
rem    4) экспортирует проект по пресету "Android" (export_presets.cfg);
rem    5) если телефон подключён - ставит APK через adb.
rem
rem  C++-модуль здесь НЕ пересобирается: готовые .so для Android уже лежат
rem  в addons\shellbit_core\bin\. Менялся код C++ - native\build_android.bat.
rem ==================================================================

cd /d "%~dp0"
set "ROOT=%CD%"
set "APK=%ROOT%\build\Shellbit.apk"
set "SO=%ROOT%\addons\shellbit_core\bin\libshellbit_core.android.template_release.arm64.so"

call "%ROOT%\tools\godot.bat" || goto :fail
call "%ROOT%\tools\android.bat" || goto :fail

if not exist "%SO%" (
    echo [!] Нет C++-модуля для Android. Запустите native\build_android.bat.
    goto :fail
)

rem --- Шаблоны экспорта: в том же наборе, что и для Windows (android_release.apk) ---
set "V4="
set "V3="
for /f "tokens=1-4 delims=." %%a in ('call "%GODOT_CONSOLE%" --version') do (
    set "V4=%%a.%%b.%%c.%%d"
    set "V3=%%a.%%b.%%c"
)
set "TPL=%APPDATA%\Godot\export_templates"
if exist "%TPL%\%V4%\android_release.apk" goto :keys
if exist "%TPL%\%V3%\android_release.apk" goto :keys
echo.
echo [?] Не вижу шаблонов экспорта Android для Godot %V4%.
echo     Если сборка ниже не получится, откройте проект в Godot:
echo     Редактор - Управление шаблонами экспорта - Загрузить и установить.

:keys
rem --- Ключ подписи ---
rem Android ставит только подписанные APK, а ОБНОВИТЬ приложение можно
rem только APK с тем же ключом. Поэтому ключ создаём один раз и храним
rem в проекте. Потеряете его - новый Shellbit встанет только после удаления
rem старого (сохранения при этом можно потерять). Сделайте копию папки keystore!
set "KEYSTORE=%ROOT%\keystore\shellbit.keystore"
if exist "%KEYSTORE%" goto :settings
echo.
echo === Создаю ключ подписи keystore\shellbit.keystore (один раз) ===
if not exist "%ROOT%\keystore" mkdir "%ROOT%\keystore"
rem .gdignore - чтобы Godot не считал папку частью игры.
type nul > "%ROOT%\keystore\.gdignore"
"%JAVA_HOME%\bin\keytool.exe" -genkeypair -keystore "%KEYSTORE%" -alias shellbit -keyalg RSA -keysize 2048 -validity 10000 -storepass shellbit -keypass shellbit -dname "CN=Shellbit" || goto :fail

:settings
rem Godot берёт ключ из этих переменных - вписывать его в проект не нужно.
set "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=%KEYSTORE%"
set "GODOT_ANDROID_KEYSTORE_RELEASE_USER=shellbit"
set "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=shellbit"

echo.
echo === Готовлю проект... ===
rem --import заодно создаёт настройки редактора, если Godot ещё ни разу не открывали.
"%GODOT_CONSOLE%" --headless --path "%ROOT%" --import >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\android_editor_settings.ps1" -Sdk "%ANDROID_HOME%" -Java "%JAVA_HOME%" || goto :fail

rem --- Экспорт ---
echo.
echo === Собираю Shellbit.apk ===
if not exist "%ROOT%\build" mkdir "%ROOT%\build"
if not exist "%ROOT%\build\.gdignore" type nul > "%ROOT%\build\.gdignore"
if exist "%APK%" del "%APK%"
"%GODOT_CONSOLE%" --headless --path "%ROOT%" --export-release "Android" "%APK%"
if not exist "%APK%" goto :fail
echo.
echo === APK готов: build\Shellbit.apk ===

rem --- Поставить на телефон, если он подключён по USB ---
rem adb devices печатает список:  R58M12345AB   device
"%ADB%" start-server >nul 2>&1
set "PHONE="
for /f "skip=1 tokens=1,2" %%a in ('call "%ADB%" devices') do (
    if "%%b"=="device" set "PHONE=%%a"
)
if not defined PHONE goto :manual
echo.
echo === Ставлю на телефон %PHONE%... (на телефоне может появиться вопрос - разрешите) ===
"%ADB%" -s %PHONE% install -r "%APK%" || goto :manual
echo.
echo === Готово! Shellbit на телефоне. ===
if not defined SHELLBIT_QUIET pause
exit /b 0

:manual
echo.
echo Телефон по USB не найден - поставьте APK сами:
echo   1) скопируйте build\Shellbit.apk на телефон (кабелем, через Telegram и т.п.);
echo   2) откройте файл на телефоне и разрешите установку из этого источника.
echo Чтобы в следующий раз ставилось само: включите на телефоне «Отладку по USB»
echo (см. README, раздел «Android»).
if not defined SHELLBIT_QUIET explorer "%ROOT%\build"
if not defined SHELLBIT_QUIET pause
exit /b 0

:fail
echo.
echo === Сборка не удалась. Скопируйте текст выше и покажите Claude. ===
if not defined SHELLBIT_QUIET pause
exit /b 1
