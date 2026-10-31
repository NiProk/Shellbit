# Прописать в настройках редактора Godot пути к Android SDK и Java.
# Godot берёт их только оттуда (Редактор -> Настройки редактора ->
# Export -> Android), поэтому Build-Android.bat вписывает их сам.
#
# Настройки лежат в %APPDATA%\Godot\editor_settings-4.7.tres - текстовый
# файл со строками вида:  export/android/java_sdk_path = "C:/..."
# Godot должен быть закрыт: иначе при выходе он запишет файл заново, по-старому.

param([string]$Sdk, [string]$Java)

$dir = Join-Path $env:APPDATA 'Godot'
$files = Get-ChildItem -Path $dir -Filter 'editor_settings-4*.tres' -ErrorAction SilentlyContinue
if (-not $files) {
    Write-Host '[!] Не нашёл настроек редактора Godot в' $dir
    exit 1
}

# Godot пишет пути с прямыми слешами: C:/Users/...
$wanted = [ordered]@{
    'export/android/android_sdk_path' = $Sdk.Replace('\', '/')
    'export/android/java_sdk_path'    = $Java.Replace('\', '/')
}

foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($key in $wanted.Keys) {
        $line = $key + ' = "' + $wanted[$key] + '"'
        $pattern = '(?m)^' + [regex]::Escape($key) + ' = .*$'
        if ([regex]::IsMatch($text, $pattern)) {
            # Строка уже есть - заменяем значение.
            $text = [regex]::Replace($text, $pattern, { param($m) $line })
        } else {
            # Строки нет - дописываем в конец (раздел [resource] - последний).
            $text = $text.TrimEnd() + "`n" + $line + "`n"
        }
    }
    # UTF-8 без BOM - так файл пишет сам Godot.
    [IO.File]::WriteAllText($file.FullName, $text, (New-Object System.Text.UTF8Encoding($false)))
}
exit 0
