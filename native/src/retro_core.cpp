#include "retro_core.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdarg>
#include <cstdio>

using namespace godot;

RetroCore *RetroCore::current = nullptr;

// Сколько звука храним максимум, если GDScript его не забирает (~0,5 с).
static const int64_t MAX_AUDIO_FRAMES = 24000;

RetroCore::RetroCore() {}

RetroCore::~RetroCore() {
	unload();
}

// =====================================================================
// Регистрация методов: только то, что перечислено здесь, видно из GDScript.
// =====================================================================
void RetroCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_system_directory", "path"), &RetroCore::set_system_directory);
	ClassDB::bind_method(D_METHOD("set_save_directory", "path"), &RetroCore::set_save_directory);
	ClassDB::bind_method(D_METHOD("load_core", "path"), &RetroCore::load_core);
	ClassDB::bind_method(D_METHOD("load_game", "path"), &RetroCore::load_game);
	ClassDB::bind_method(D_METHOD("unload"), &RetroCore::unload);
	ClassDB::bind_method(D_METHOD("is_running"), &RetroCore::is_running);
	ClassDB::bind_method(D_METHOD("run_frame"), &RetroCore::run_frame);
	ClassDB::bind_method(D_METHOD("set_input", "port", "mask"), &RetroCore::set_input);
	ClassDB::bind_method(D_METHOD("has_new_frame"), &RetroCore::has_new_frame);
	ClassDB::bind_method(D_METHOD("get_frame"), &RetroCore::get_frame);
	ClassDB::bind_method(D_METHOD("take_audio"), &RetroCore::take_audio);
	ClassDB::bind_method(D_METHOD("get_av_info"), &RetroCore::get_av_info);
	ClassDB::bind_method(D_METHOD("get_system_info"), &RetroCore::get_system_info);
	ClassDB::bind_method(D_METHOD("save_state"), &RetroCore::save_state);
	ClassDB::bind_method(D_METHOD("load_state", "data"), &RetroCore::load_state);

	BIND_CONSTANT(BUTTON_B);
	BIND_CONSTANT(BUTTON_Y);
	BIND_CONSTANT(BUTTON_SELECT);
	BIND_CONSTANT(BUTTON_START);
	BIND_CONSTANT(BUTTON_UP);
	BIND_CONSTANT(BUTTON_DOWN);
	BIND_CONSTANT(BUTTON_LEFT);
	BIND_CONSTANT(BUTTON_RIGHT);
	BIND_CONSTANT(BUTTON_A);
	BIND_CONSTANT(BUTTON_X);
	BIND_CONSTANT(BUTTON_L);
	BIND_CONSTANT(BUTTON_R);
	BIND_CONSTANT(BUTTON_L2);
	BIND_CONSTANT(BUTTON_R2);
	BIND_CONSTANT(BUTTON_L3);
	BIND_CONSTANT(BUTTON_R3);
}

// =====================================================================
// Папки
// =====================================================================
void RetroCore::set_system_directory(const String &path) {
	system_dir = path.utf8().get_data();
}

void RetroCore::set_save_directory(const String &path) {
	save_dir = path.utf8().get_data();
}

// =====================================================================
// Загрузка ядра (.dll)
// =====================================================================
bool RetroCore::load_core(const String &path) {
	unload();

	// libretro устроен так, что одновременно может работать только одно ядро.
	if (current != nullptr && current != this) {
		UtilityFunctions::push_error("RetroCore: другое ядро уже запущено");
		return false;
	}

	if (!library.open(path.utf8().get_data())) {
		UtilityFunctions::push_error("RetroCore: не удалось открыть ядро ", path, " (", String(library.last_error().c_str()), ")");
		return false;
	}

	// Находим каждую функцию по имени. Если чего-то нет — это не ядро libretro.
	bool ok = true;
#define LOAD_SYMBOL(field, name)                                                     \
	api.field = reinterpret_cast<decltype(api.field)>(library.symbol(name));          \
	if (!api.field) {                                                                \
		UtilityFunctions::push_error("RetroCore: в ядре нет функции ", String(name)); \
		ok = false;                                                                  \
	}

	LOAD_SYMBOL(init, "retro_init");
	LOAD_SYMBOL(deinit, "retro_deinit");
	LOAD_SYMBOL(api_version, "retro_api_version");
	LOAD_SYMBOL(get_system_info, "retro_get_system_info");
	LOAD_SYMBOL(get_system_av_info, "retro_get_system_av_info");
	LOAD_SYMBOL(set_environment, "retro_set_environment");
	LOAD_SYMBOL(set_video_refresh, "retro_set_video_refresh");
	LOAD_SYMBOL(set_audio_sample, "retro_set_audio_sample");
	LOAD_SYMBOL(set_audio_sample_batch, "retro_set_audio_sample_batch");
	LOAD_SYMBOL(set_input_poll, "retro_set_input_poll");
	LOAD_SYMBOL(set_input_state, "retro_set_input_state");
	LOAD_SYMBOL(run, "retro_run");
	LOAD_SYMBOL(load_game, "retro_load_game");
	LOAD_SYMBOL(unload_game, "retro_unload_game");
	LOAD_SYMBOL(serialize_size, "retro_serialize_size");
	LOAD_SYMBOL(serialize, "retro_serialize");
	LOAD_SYMBOL(unserialize, "retro_unserialize");
#undef LOAD_SYMBOL

	if (!ok) {
		library.close();
		return false;
	}

	current = this;
	pixel_format = RETRO_PIXEL_FORMAT_0RGB1555; // формат по умолчанию по стандарту libretro

	// Отдаём ядру наши колбэки и запускаем его.
	api.set_environment(&RetroCore::environment_cb);
	api.set_video_refresh(&RetroCore::video_cb);
	api.set_audio_sample(&RetroCore::audio_sample_cb);
	api.set_audio_sample_batch(&RetroCore::audio_batch_cb);
	api.set_input_poll(&RetroCore::input_poll_cb);
	api.set_input_state(&RetroCore::input_state_cb);
	api.init();
	core_loaded = true;
	return true;
}

// =====================================================================
// Загрузка игры (ROM)
// =====================================================================
bool RetroCore::load_game(const String &path) {
	if (!core_loaded) {
		UtilityFunctions::push_error("RetroCore: сначала вызовите load_core()");
		return false;
	}

	retro_system_info info = {};
	api.get_system_info(&info);

	game_path = path.utf8().get_data();
	retro_game_info game = {};
	game.path = game_path.c_str();

	// Одним ядрам достаточно пути к файлу (need_fullpath = true),
	// другим нужно содержимое файла в памяти.
	if (!info.need_fullpath) {
		PackedByteArray bytes = FileAccess::get_file_as_bytes(path);
		if (bytes.is_empty()) {
			UtilityFunctions::push_error("RetroCore: не удалось прочитать файл игры ", path);
			return false;
		}
		game_data.assign(bytes.ptr(), bytes.ptr() + bytes.size());
		game.data = game_data.data();
		game.size = game_data.size();
	}

	if (!api.load_game(&game)) {
		UtilityFunctions::push_error("RetroCore: ядро не смогло загрузить игру ", path);
		game_data.clear();
		return false;
	}

	api.get_system_av_info(&av_info);
	game_loaded = true;
	new_frame = false;
	audio.clear();
	return true;
}

void RetroCore::unload() {
	if (game_loaded) {
		api.unload_game();
		game_loaded = false;
	}
	if (core_loaded) {
		api.deinit();
		core_loaded = false;
	}
	library.close();
	game_data.clear();
	frame.unref();
	audio.clear();
	if (current == this) {
		current = nullptr;
	}
}

// =====================================================================
// Один кадр
// =====================================================================
void RetroCore::run_frame() {
	if (game_loaded) {
		api.run(); // внутри ядро вызовет video_cb, audio_*_cb и input_state_cb
	}
}

void RetroCore::set_input(int port, int mask) {
	if (port >= 0 && port < 4) {
		input_masks[port] = (uint16_t)mask;
	}
}

Ref<Image> RetroCore::get_frame() {
	new_frame = false;
	return frame;
}

PackedVector2Array RetroCore::take_audio() {
	PackedVector2Array result = audio;
	audio.clear();
	return result;
}

// =====================================================================
// Сведения о ядре и картинке
// =====================================================================
Dictionary RetroCore::get_av_info() const {
	Dictionary result;
	const retro_game_geometry &geometry = av_info.geometry;
	float aspect = geometry.aspect_ratio;
	if (aspect <= 0.0f && geometry.base_height > 0) {
		aspect = (float)geometry.base_width / (float)geometry.base_height;
	}
	result["width"] = geometry.base_width;
	result["height"] = geometry.base_height;
	result["aspect"] = aspect;
	result["fps"] = av_info.timing.fps;
	result["sample_rate"] = av_info.timing.sample_rate;
	return result;
}

Dictionary RetroCore::get_system_info() const {
	Dictionary result;
	if (!core_loaded) {
		return result;
	}
	retro_system_info info = {};
	api.get_system_info(&info);
	result["name"] = String(info.library_name ? info.library_name : "");
	result["version"] = String(info.library_version ? info.library_version : "");
	result["extensions"] = String(info.valid_extensions ? info.valid_extensions : "");
	result["need_fullpath"] = info.need_fullpath;
	return result;
}

// =====================================================================
// Снимки состояния (save states)
// =====================================================================
PackedByteArray RetroCore::save_state() {
	PackedByteArray data;
	if (!game_loaded) {
		return data;
	}
	size_t size = api.serialize_size();
	if (size == 0) {
		return data;
	}
	data.resize((int64_t)size);
	if (!api.serialize(data.ptrw(), size)) {
		data.clear();
	}
	return data;
}

bool RetroCore::load_state(const PackedByteArray &data) {
	if (!game_loaded || data.is_empty()) {
		return false;
	}
	return api.unserialize(data.ptr(), (size_t)data.size());
}

// =====================================================================
// Колбэки. Статические функции просто передают вызов текущему объекту.
// =====================================================================
bool RetroCore::environment_cb(unsigned cmd, void *data) {
	return current ? current->on_environment(cmd, data) : false;
}

void RetroCore::video_cb(const void *data, unsigned width, unsigned height, size_t pitch) {
	if (current) {
		current->on_video(data, width, height, pitch);
	}
}

void RetroCore::audio_sample_cb(int16_t left, int16_t right) {
	if (current) {
		int16_t pair[2] = { left, right };
		current->push_audio(pair, 1);
	}
}

size_t RetroCore::audio_batch_cb(const int16_t *data, size_t frames) {
	if (current) {
		current->push_audio(data, frames);
	}
	return frames;
}

void RetroCore::input_poll_cb() {
	// Кнопки мы получаем заранее через set_input(), здесь делать нечего.
}

int16_t RetroCore::input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
	if (!current || port >= 4 || (device & RETRO_DEVICE_MASK) != RETRO_DEVICE_JOYPAD) {
		return 0;
	}
	uint16_t mask = current->input_masks[port];
	if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
		return (int16_t)mask; // ядро просит сразу все кнопки
	}
	return (id < 16) ? (int16_t)((mask >> id) & 1) : 0;
}

void RetroCore::log_cb(enum retro_log_level level, const char *fmt, ...) {
	char buffer[1024];
	va_list args;
	va_start(args, fmt);
	vsnprintf(buffer, sizeof(buffer), fmt, args);
	va_end(args);

	String text = String::utf8(buffer).strip_edges();
	if (level >= RETRO_LOG_ERROR) {
		UtilityFunctions::push_error("[core] ", text);
	} else if (level == RETRO_LOG_WARN) {
		UtilityFunctions::push_warning("[core] ", text);
	} else if (level == RETRO_LOG_INFO) {
		UtilityFunctions::print("[core] ", text);
	}
}

// =====================================================================
// Environment — ядро задаёт вопросы фронтенду.
// Отвечаем на самые нужные; на остальные — false («не умею»).
// =====================================================================
bool RetroCore::on_environment(unsigned cmd, void *data) {
	switch (cmd & ~RETRO_ENVIRONMENT_EXPERIMENTAL) {
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
			retro_pixel_format format = *(const retro_pixel_format *)data;
			if (format == RETRO_PIXEL_FORMAT_0RGB1555 || format == RETRO_PIXEL_FORMAT_XRGB8888 || format == RETRO_PIXEL_FORMAT_RGB565) {
				pixel_format = format;
				return true;
			}
			return false;
		}
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
			*(const char **)data = system_dir.empty() ? nullptr : system_dir.c_str();
			return !system_dir.empty();
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
			*(const char **)data = save_dir.empty() ? nullptr : save_dir.c_str();
			return !save_dir.empty();
		case RETRO_ENVIRONMENT_GET_CAN_DUPE:
			// «Можно ли прислать тот же кадр ещё раз (data = NULL)?» — да.
			*(bool *)data = true;
			return true;
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
			((retro_log_callback *)data)->log = &RetroCore::log_cb;
			return true;
		case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
			return true; // умеем отдавать все кнопки одним числом
		case RETRO_ENVIRONMENT_SET_GEOMETRY:
			av_info.geometry = *(const retro_game_geometry *)data;
			return true;
		case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
			av_info = *(const retro_system_av_info *)data;
			return true;
		case RETRO_ENVIRONMENT_SET_MESSAGE: {
			const retro_message *message = (const retro_message *)data;
			UtilityFunctions::print("[core message] ", String::utf8(message->msg));
			return true;
		}
		case RETRO_ENVIRONMENT_SHUTDOWN:
			return true;
		default:
			return false;
	}
}

// =====================================================================
// Видео: переводим пиксели ядра в формат RGBA8, который понимает Godot.
// =====================================================================
void RetroCore::on_video(const void *data, unsigned width, unsigned height, size_t pitch) {
	if (data == nullptr || data == RETRO_HW_FRAME_BUFFER_VALID || width == 0 || height == 0) {
		return; // повтор прошлого кадра — картинка не меняется
	}

	frame_pixels.resize((int64_t)width * height * 4);
	uint8_t *out = frame_pixels.ptrw();
	const uint8_t *row = (const uint8_t *)data;

	for (unsigned y = 0; y < height; y++, row += pitch) {
		for (unsigned x = 0; x < width; x++, out += 4) {
			uint8_t r, g, b;
			if (pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
				uint32_t pixel = ((const uint32_t *)row)[x];
				r = (pixel >> 16) & 0xFF;
				g = (pixel >> 8) & 0xFF;
				b = pixel & 0xFF;
			} else if (pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
				uint16_t pixel = ((const uint16_t *)row)[x];
				uint8_t r5 = (pixel >> 11) & 0x1F, g6 = (pixel >> 5) & 0x3F, b5 = pixel & 0x1F;
				r = (r5 << 3) | (r5 >> 2);
				g = (g6 << 2) | (g6 >> 4);
				b = (b5 << 3) | (b5 >> 2);
			} else { // 0RGB1555
				uint16_t pixel = ((const uint16_t *)row)[x];
				uint8_t r5 = (pixel >> 10) & 0x1F, g5 = (pixel >> 5) & 0x1F, b5 = pixel & 0x1F;
				r = (r5 << 3) | (r5 >> 2);
				g = (g5 << 3) | (g5 >> 2);
				b = (b5 << 3) | (b5 >> 2);
			}
			out[0] = r;
			out[1] = g;
			out[2] = b;
			out[3] = 255;
		}
	}

	frame = Image::create_from_data((int32_t)width, (int32_t)height, false, Image::FORMAT_RGBA8, frame_pixels);
	new_frame = true;
}

// =====================================================================
// Звук: 16-битные пары (левый, правый) → числа от -1 до 1 для Godot.
// =====================================================================
void RetroCore::push_audio(const int16_t *data, size_t frames) {
	int64_t start = audio.size();
	if (start + (int64_t)frames > MAX_AUDIO_FRAMES) {
		audio.clear(); // никто не забирает звук — не копим бесконечно
		start = 0;
	}
	audio.resize(start + (int64_t)frames);
	Vector2 *out = audio.ptrw() + start;
	for (size_t i = 0; i < frames; i++) {
		out[i] = Vector2(data[i * 2] / 32768.0f, data[i * 2 + 1] / 32768.0f);
	}
}
