#pragma once

// =====================================================================
// SevenZip — распаковка архивов .7z прямо внутри Shellbit.
//
// Раньше .7z распаковывала отдельная программа 7-Zip (7zr.exe в Windows,
// 7z в Linux). На Android чужие программы запускать нельзя, поэтому
// распаковщик встроен сюда — это код из LZMA SDK (папка lzma/), которую
// автор 7-Zip, Игорь Павлов, отдал в общественное достояние.
//
// Из GDScript:
//   var zip := SevenZip.new()
//   var files: PackedStringArray = zip.list("D:/Games/Sonic.7z")
//   var error: String = zip.extract("D:/Games/Sonic.7z", "C:/.../cache/abc")
//   # error == "" — всё распаковано; иначе — текст ошибки
// =====================================================================

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class SevenZip : public RefCounted {
	GDCLASS(SevenZip, RefCounted)

protected:
	static void _bind_methods();

public:
	// Имена файлов в архиве (с папками: "Disc 1/game.cue"). Пусто — не открылся.
	PackedStringArray list(const String &archive_path);
	// Распаковать всё в папку dest. Возвращает "" или текст ошибки.
	String extract(const String &archive_path, const String &dest);
};

} // namespace godot
