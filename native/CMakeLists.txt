# Сборка C++-модуля shellbit_core.
# Готовая .dll попадает в addons/shellbit_core/bin/ проекта Godot.
#
# Обычно запускать не нужно — используйте build.bat.

cmake_minimum_required(VERSION 3.17)
project(shellbit_core LANGUAGES C CXX)

# template_debug — для редактора и отладки, template_release — для готового .exe
set(GODOTCPP_TARGET "template_debug" CACHE STRING "template_debug или template_release")

add_subdirectory(godot-cpp)

add_library(shellbit_core SHARED
    src/register_types.cpp
    src/retro_core.cpp
    src/dynamic_library.cpp
    src/gl_context.cpp
    src/seven_zip.cpp
)

# Распаковщик .7z из LZMA SDK (папка src/lzma, написан на C, public domain).
# Только распаковка: Z7_EXTRACT_ONLY; PPMd — один из способов сжатия в .7z.
file(GLOB LZMA_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/lzma/*.c")
add_library(lzma_dec STATIC ${LZMA_SOURCES})
target_compile_definitions(lzma_dec PRIVATE Z7_PPMD_SUPPORT Z7_EXTRACT_ONLY)
set_target_properties(lzma_dec PROPERTIES POSITION_INDEPENDENT_CODE ON)
# (Библиотеку C в Windows lzma_dec берёт ту же, что godot-cpp: тот выставляет
# CMAKE_MSVC_RUNTIME_LIBRARY для всех целей, созданных после него.)

target_link_libraries(shellbit_core PRIVATE godot-cpp lzma_dec ${CMAKE_DL_LIBS})

# Аппаратная отрисовка (gl_context.cpp): в Windows — OpenGL через WGL.
# opengl32 — сам OpenGL, gdi32 — выбор формата пикселей, user32 — скрытое окно.
# В Linux библиотеку EGL загружаем сами (dlopen), подключать ничего не нужно.
if(WIN32)
    target_link_libraries(shellbit_core PRIVATE opengl32 gdi32 user32)
endif()

# Linux: стандартную библиотеку C++ вшиваем прямо в .so. Тогда модуль
# не зависит от версии libstdc++ в системе — важно для Steam Deck,
# где система обновляется реже, чем, например, CachyOS.
# (Android тоже «UNIX», но там своя библиотека C++ — её вшивает
# настройка ANDROID_STL=c++_static в build_android.bat.)
if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_options(shellbit_core PRIVATE -static-libstdc++ -static-libgcc)
endif()

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

# Android принимает в APK только библиотеки с именем на «lib»:
# libshellbit_core.android.template_release.arm64.so. Остальным системам — без приставки.
set(SHELLBIT_PREFIX "")
if(ANDROID)
    set(SHELLBIT_PREFIX "lib")
endif()
set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../addons/shellbit_core/bin/")

set_target_properties(shellbit_core PROPERTIES
    CXX_STANDARD 17
    CXX_EXTENSIONS OFF
    CXX_VISIBILITY_PRESET ${GODOTCPP_SYMBOL_VISIBILITY}
    POSITION_INDEPENDENT_CODE ON
    PREFIX "${SHELLBIT_PREFIX}"
    OUTPUT_NAME "shellbit_core${GODOTCPP_SUFFIX}"
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
)
