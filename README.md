# Shellbit

Фронтенд для ретро-эмуляторов на Godot 4.6 (GDScript). Сейчас — **этап 1**: интерфейс, библиотека игр и запуск игр через ядра libretro.

## Как запустить

1. Открой Godot 4.6 → **Import** → выбери файл `project.godot` из этой папки.
2. Нажми **F5** (или ▶ в правом верхнем углу).
3. Нажми «+ Папка с играми» и выбери папку с ROM-файлами (.nes, .sfc, .md, .gba…).

Управление: стрелки / крестовина / стик — перемещение, **A / Enter** — выбрать, **B / Esc** — назад,
**Y / F** — избранное, **LB RB / Q E** — другая приставка, **X / Tab** на главном — пересканировать папки.

## Что где лежит

| Путь | Что это |
| --- | --- |
| `autoload/Settings.gd` | Настройки (файл `user://settings.cfg`) |
| `autoload/CoreManager.gd` | Список приставок из `data/systems.json` |
| `autoload/Library.gd` | Поиск игр, недавние, избранное (`user://library.json`) |
| `autoload/InputMapper.gd` | Свои действия ввода, определение типа геймпада |
| `autoload/UiTheme.gd` | Цвета, шрифты, стиль кнопок и рамки фокуса |
| `autoload/SceneRouter.gd` | Переходы между экранами, «Назад», всплывающие сообщения |
| `scenes/home/` | Главный экран |
| `scenes/library/` | Экран одной приставки |
| `scenes/components/` | Карточка игры, плитка приставки, строка подсказок |
| `scenes/player/` | Экран игры: картинка, звук, кнопки |
| `native/` | C++-модуль RetroCore (исходники + godot-cpp) |
| `addons/shellbit_core/` | Собранный модуль (.dll) и его описание для Godot |

`user://` в Windows — это `%APPDATA%\Godot\app_userdata\Shellbit`.

## Важно при экспорте в .exe

`data/systems.json` — не ресурс Godot, поэтому в настройках экспорта добавь его вручную:
**Project → Export → Resources → Filters to export non-resource files** → впиши `data/*.json`.

## Этап 1: сборка C++-модуля (Windows, один раз)

1. **Visual Studio Build Tools 2022 или новее** (бесплатно): https://visualstudio.microsoft.com/downloads/ →
   «Build Tools for Visual Studio». В установщике отметь **«Разработка классических приложений на C++»**
   (Desktop development with C++). Справа проверь, что отмечены **MSVC**, **Windows SDK** и **C++ CMake tools for Windows**.
2. **Python 3**: https://www.python.org/downloads/ — при установке поставь галочку **«Add python.exe to PATH»**.
3. **Закрой Godot**, затем дважды щёлкни `native/build.bat`. При первом запуске он сам скачает библиотеку godot-cpp
   в `native/godot-cpp`, сборка идёт 5–15 минут. Временные файлы сборки лежат в `%LOCALAPPDATA%\Shellbit-build`.
4. В папке `addons/shellbit_core/bin/` появится `shellbit_core.windows.template_debug.x86_64.dll`.

## Ядра libretro

Ядро — это готовый эмулятор одной приставки. Скачай нужное с официального сервера:
https://buildbot.libretro.com/nightly/windows/x86_64/latest/ (например, `fceumm_libretro.dll.zip` для NES),
распакуй и положи `.dll` в папку ядер:

`%APPDATA%\Godot\app_userdata\Shellbit\cores`

(Её можно открыть кнопкой «Открыть папку ядер» на экране ошибки.) Какое ядро нужно какой приставке —
поле `default_core` в `data/systems.json`.

## Управление в игре

| Геймпад | Клавиатура | RetroPad |
| --- | --- | --- |
| Крестовина / левый стик | Стрелки | Крестовина |
| A (нижняя) | Z | B |
| B (правая) | X | A |
| X (левая) | A | Y |
| Y (верхняя) | S | X |
| LB / RB | Q / W | L / R |
| Start / Back | Enter / Shift | Start / Select |
| **Правый стик (нажать)** или **View + Menu** | **Esc** | Меню паузы |

## Сохранения

- **Меню паузы:** продолжить, начать заново, 3 слота сохранений, выйти в библиотеку.
- На слоте: **A** — загрузить (в пустой — сохранить), **X** — сохранить сюда.
- При выходе игра **сохраняется сама**, а при следующем запуске продолжается с того же места.
- Файлы лежат в `%APPDATA%\Godot\app_userdata\Shellbit\states\` — своя папка для каждого файла игры.
