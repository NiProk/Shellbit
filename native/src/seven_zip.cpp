#include "seven_zip.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <cstdlib>
#include <string>

// Код LZMA SDK написан на C. extern "C" говорит компилятору C++:
// «эти функции — из C, не переименовывай их по правилам C++».
extern "C" {
#include "lzma/7z.h"
#include "lzma/7zAlloc.h"
#include "lzma/7zCrc.h"
}

using namespace godot;

void SevenZip::_bind_methods() {
	ClassDB::bind_method(D_METHOD("list", "archive_path"), &SevenZip::list);
	ClassDB::bind_method(D_METHOD("extract", "archive_path", "dest"), &SevenZip::extract);
}

namespace {

// --- Память ---
// LZMA SDK просит память через «распределитель» — пару функций Alloc/Free.
// Отдаём ему обычные malloc/free.
void *sz_alloc(ISzAllocPtr, size_t size) { return size == 0 ? nullptr : malloc(size); }
void sz_free(ISzAllocPtr, void *address) { free(address); }
const ISzAlloc g_alloc = { sz_alloc, sz_free };

// --- Чтение архива ---
// LZMA SDK читает архив через «поток» с двумя функциями: Read и Seek.
// Делаем такой поток поверх FileAccess из Godot — тогда работают любые
// пути, в том числе с русскими буквами и на Android.
struct GodotInStream {
	ISeekInStream vt; // обязательно первым: SDK получает указатель на vt
	Ref<FileAccess> file;
};

SRes stream_read(ISeekInStreamPtr p, void *buf, size_t *size) {
	GodotInStream *self = (GodotInStream *)p;
	if (*size == 0) {
		return SZ_OK;
	}
	uint64_t got = self->file->get_buffer((uint8_t *)buf, *size);
	*size = (size_t)got;
	return SZ_OK; // меньше, чем просили, — это конец файла, а не ошибка
}

SRes stream_seek(ISeekInStreamPtr p, Int64 *pos, ESzSeek origin) {
	GodotInStream *self = (GodotInStream *)p;
	int64_t target = *pos;
	if (origin == SZ_SEEK_CUR) {
		target += (int64_t)self->file->get_position();
	} else if (origin == SZ_SEEK_END) {
		target += (int64_t)self->file->get_length();
	}
	if (target < 0) {
		return SZ_ERROR_PARAM;
	}
	self->file->seek((uint64_t)target);
	*pos = (Int64)self->file->get_position();
	return SZ_OK;
}

// Открытый архив. Конструктор открывает, деструктор всё закрывает и
// освобождает — даже если на полпути случилась ошибка.
struct Archive {
	GodotInStream in;
	CLookToRead2 look;
	CSzArEx db;
	bool ok = false;
	String error;

	static constexpr size_t kInputBufSize = (size_t)1 << 18; // 256 КБ

	explicit Archive(const String &path) {
		SzArEx_Init(&db);
		look.buf = nullptr;
		in.vt.Read = stream_read;
		in.vt.Seek = stream_seek;
		in.file = FileAccess::open(path, FileAccess::READ);
		if (in.file.is_null()) {
			error = String::utf8("Не удалось открыть архив ") + path;
			return;
		}
		LookToRead2_CreateVTable(&look, False);
		look.buf = (Byte *)ISzAlloc_Alloc(&g_alloc, kInputBufSize);
		look.bufSize = kInputBufSize;
		look.realStream = &in.vt;
		LookToRead2_INIT(&look)

		static bool crc_ready = false;
		if (!crc_ready) {
			CrcGenerateTable(); // таблица для проверки контрольных сумм
			crc_ready = true;
		}
		SRes res = SzArEx_Open(&db, &look.vt, &g_alloc, &g_alloc);
		if (res != SZ_OK) {
			error = String::utf8("Архив повреждён или это не .7z (код ") + String::num_int64(res) + ")";
			return;
		}
		ok = true;
	}

	~Archive() {
		SzArEx_Free(&db, &g_alloc);
		if (look.buf) {
			ISzAlloc_Free(&g_alloc, look.buf);
		}
	}

	// Имя файла номер i. В архиве имена хранятся в UTF-16 — переводим в String.
	String name(UInt32 i) {
		size_t len = SzArEx_GetFileNameUtf16(&db, i, nullptr);
		std::u16string text(len, u'\0');
		SzArEx_GetFileNameUtf16(&db, i, (UInt16 *)text.data());
		if (!text.empty() && text.back() == u'\0') {
			text.pop_back();
		}
		return String::utf16((const char16_t *)text.data(), (int)text.size()).replace("\\", "/");
	}
};

// Безопасно ли имя: архив не должен писать за пределы своей папки
// («../../Windows/…») или по абсолютному пути.
bool safe_name(const String &name) {
	if (name.is_empty() || name.begins_with("/") || name.find(":") >= 0) {
		return false;
	}
	PackedStringArray parts = name.split("/");
	for (int64_t i = 0; i < parts.size(); i++) {
		if (parts[i] == "..") {
			return false;
		}
	}
	return true;
}

} // namespace

PackedStringArray SevenZip::list(const String &archive_path) {
	PackedStringArray names;
	Archive archive(archive_path);
	if (!archive.ok) {
		return names;
	}
	for (UInt32 i = 0; i < archive.db.NumFiles; i++) {
		if (!SzArEx_IsDir(&archive.db, i)) {
			names.append(archive.name(i));
		}
	}
	return names;
}

String SevenZip::extract(const String &archive_path, const String &dest) {
	Archive archive(archive_path);
	if (!archive.ok) {
		return archive.error;
	}
	DirAccess::make_dir_recursive_absolute(dest);

	// Файлы в .7z сжаты «блоками»: несколько файлов — один общий блок.
	// SzArEx_Extract распаковывает блок целиком в out_buffer и запоминает
	// его номер: следующий файл из того же блока берётся уже готовым.
	UInt32 block_index = 0xFFFFFFFF;
	Byte *out_buffer = nullptr;
	size_t out_buffer_size = 0;
	String error;

	for (UInt32 i = 0; i < archive.db.NumFiles && error.is_empty(); i++) {
		String name = archive.name(i);
		if (!safe_name(name)) {
			continue; // подозрительное имя — пропускаем файл
		}
		String target = dest.path_join(name);
		if (SzArEx_IsDir(&archive.db, i)) {
			DirAccess::make_dir_recursive_absolute(target);
			continue;
		}
		size_t offset = 0;
		size_t size = 0;
		SRes res = SzArEx_Extract(&archive.db, &archive.look.vt, i, &block_index, &out_buffer,
				&out_buffer_size, &offset, &size, &g_alloc, &g_alloc);
		if (res == SZ_ERROR_UNSUPPORTED) {
			error = String::utf8("Архив сжат способом, который Shellbit не умеет. Перепакуйте его в .zip или обычный .7z.");
			break;
		}
		if (res != SZ_OK) {
			error = String::utf8("Не удалось распаковать ") + name + " (" + String::num_int64(res) + ")";
			break;
		}
		DirAccess::make_dir_recursive_absolute(target.get_base_dir());
		Ref<FileAccess> out = FileAccess::open(target, FileAccess::WRITE);
		if (out.is_null()) {
			error = String::utf8("Не удалось записать ") + target;
			break;
		}
		if (size > 0) {
			PackedByteArray bytes;
			bytes.resize((int64_t)size);
			memcpy(bytes.ptrw(), out_buffer + offset, size);
			out->store_buffer(bytes);
		}
		out->close();
	}
	ISzAlloc_Free(&g_alloc, out_buffer);
	return error;
}
