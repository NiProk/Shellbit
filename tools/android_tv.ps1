# Подготовить «Gradle-сборку» Android для значка на Android TV.
# Вызывается из Build-Android.bat перед экспортом.
#
# Зачем: обычная сборка Godot берёт готовый APK-шаблон, и поменять в нём
# можно немногое. Чтобы Shellbit появился на ГЛАВНОМ экране Android TV,
# нужен баннер (картинка 320x180) и пометка «это приложение для TV»
# (LEANBACK_LAUNCHER) — а это правки в AndroidManifest.xml. Такие правки
# возможны только в Gradle-сборке: Godot кладёт исходники Android-части
# в папку android\build проекта и собирает APK из них.
#
# Что делает этот скрипт (каждый раз — повторять безопасно):
#   1) нет android\build — распаковывает туда android_source.zip
#      из шаблонов экспорта Godot (то же, что «Проект -> Установить шаблон
#      сборки Android» в редакторе);
#   2) кладёт баннер data\android\banner.png в android\build\res\drawable-xhdpi;
#   3) вписывает баннер в android\build\src\main\AndroidManifest.xml и
#      помечает, что сенсорный экран и «телевизионность» не обязательны
#      (иначе на TV или на телефоне Android скажет «не поддерживается»).
# LEANBACK_LAUNCHER Godot добавляет сам (галочка «Show In Android TV» в пресете).

param([string]$Root, [string]$Templates, [string]$Version)

$ErrorActionPreference = 'Stop'
$android = Join-Path $Root 'android'
$build = Join-Path $android 'build'

# --- 1. Шаблон Gradle-сборки ---
$versionFile = Join-Path $android '.build_version'
$installed = ''
if (Test-Path $versionFile) { $installed = (Get-Content $versionFile -Raw).Trim() }
if (-not (Test-Path $build) -or $installed -ne $Version) {
    $zip = Join-Path $Templates 'android_source.zip'
    if (-not (Test-Path $zip)) {
        Write-Host "[!] Нет $zip - установите шаблоны экспорта Godot $Version."
        exit 1
    }
    Write-Host '=== Устанавливаю шаблон Gradle-сборки в android\build (один раз) ==='
    if (Test-Path $build) { Remove-Item $build -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $build | Out-Null
    tar -xf $zip -C $build
    if ($LASTEXITCODE -ne 0) { Write-Host '[!] Не удалось распаковать шаблон'; exit 1 }
    # Так помечает установленный шаблон сам Godot: версия и .gdignore,
    # чтобы редактор не пытался «импортировать» Java-исходники.
    [IO.File]::WriteAllText($versionFile, "$Version`n")
    [IO.File]::WriteAllText((Join-Path $build '.gdignore'), "`n")
}

# --- 2. Баннер ---
$drawable = Join-Path $build 'res\drawable-xhdpi'
New-Item -ItemType Directory -Force -Path $drawable | Out-Null
Copy-Item (Join-Path $Root 'data\android\banner.png') (Join-Path $drawable 'banner.png') -Force

# --- 3. AndroidManifest.xml ---
$manifest = Join-Path $build 'src\main\AndroidManifest.xml'
$text = [IO.File]::ReadAllText($manifest)
if ($text -notmatch 'android:banner=') {
    $text = $text.Replace('android:icon="@mipmap/icon"', "android:icon=`"@mipmap/icon`"`n        android:banner=`"@drawable/banner`"")
}
if ($text -notmatch 'android.software.leanback') {
    $features = '    <uses-feature android:name="android.software.leanback" android:required="false" />' + "`n" +
                '    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />' + "`n`n" +
                '    <application'
    $text = ([regex]'    <application').Replace($text, $features, 1)
}
[IO.File]::WriteAllText($manifest, $text, (New-Object System.Text.UTF8Encoding($false)))
exit 0
