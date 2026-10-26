#include "retro_core.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cstdarg>
#include <cstdlib>
#include <cstring>
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
	ClassDB::bind_method(D_METHOD("set_analog", "port", "stick", "x", "y"), &RetroCore::set_analog);
	ClassDB::bind_method(D_METHOD("get_controller_types", "port"), &RetroCore::get_controller_types);
	ClassDB::bind_method(D_METHOD("set_controller_type", "port", "device"), &RetroCore::set_controller_type);
	ClassDB::bind_method(D_METHOD("get_rumble", "port"), &RetroCore::get_rumble);
	ClassDB::bind_method(D_METHOD("get_disk_count"), &RetroCore::get_disk_count);
	ClassDB::bind_method(D_METHOD("get_disk_index"), &RetroCore::get_disk_index);
	ClassDB::bind_method(D_METHOD("get_disk_label", "index"), &RetroCore::get_disk_label);
	ClassDB::bind_method(D_METHOD("get_disk_path", "index"), &RetroCore::get_disk_path);
	ClassDB::bind_method(D_METHOD("set_disk", "index"), &RetroCore::set_disk);
	ClassDB::bind_method(D_METHOD("set_initial_disk", "index", "path"), &RetroCore::set_initial_disk);
	ClassDB::bind_method(D_METHOD("has_new_frame"), &RetroCore::has_new_frame);
	ClassDB::bind_method(D_METHOD("get_frame"), &RetroCore::get_frame);
	ClassDB::bind_method(D_METHOD("take_audio"), &RetroCore::take_audio);
	ClassDB::bind_method(D_METHOD("get_av_info"), &RetroCore::get_av_info);
	ClassDB::bind_method(D_METHOD("get_system_info"), &RetroCore::get_system_info);
	ClassDB::bind_method(D_METHOD("save_state"), &RetroCore::save_state);
	ClassDB::bind_method(D_METHOD("load_state", "data"), &RetroCore::load_state);
	ClassDB::bind_method(D_METHOD("save_sram"), &RetroCore::save_sram);
	ClassDB::bind_method(D_METHOD("set_option", "key", "value"), &RetroCore::set_option);
	ClassDB::bind_method(D_METHOD("get_options"), &RetroCore::get_options);
	ClassDB::bind_method(D_METHOD("get_option_list"), &RetroCore::get_option_list);
	ClassDB::bind_method(D_METHOD("refresh_option_display"), &RetroCore::refresh_option_display);
	ClassDB::bind_method(D_METHOD("set_language", "language"), &RetroCore::set_language);
	ClassDB::bind_method(D_METHOD("is_hw_render"), &RetroCore::is_hw_render);
	ClassDB::bind_method(D_METHOD("get_hw_error"), &RetroCore::get_hw_error);

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
		UtilityFunctions::push_error(String::utf8("RetroCore: другое ядро уже запущено"));
		return false;
	}

	if (!library.open(path.utf8().get_data())) {
		UtilityFunctions::push_error(String::utf8("RetroCore: не удалось открыть ядро "), path, " (", String(library.last_error().c_str()), ")");
		return false;
	}

	// Находим каждую функцию по имени. Если чего-то нет — это не ядро libretro.
	bool ok = true;
#define LOAD_SYMBOL(field, name)                                                     \
	api.field = reinterpret_cast<decltype(api.field)>(library.symbol(name));          \
	if (!api.field) {                                                                \
		UtilityFunctions::push_error(String::utf8("RetroCore: в ядре нет функции "), String(name)); \
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
	LOAD_SYMBOL(get_memory_data, "retro_get_memory_data");
	LOAD_SYMBOL(get_memory_size, "retro_get_memory_size");
#undef LOAD_SYMBOL
	// Эта функция у ядра необязательная: без неё просто нельзя сменить контроллер.
	api.set_controller_port_device = reinterpret_cast<decltype(api.set_controller_port_device)>(
			library.symbol("retro_set_controller_port_device"));

	if (!ok) {
		library.close();
		return false;
	}

	current = this;
	pixel_format = RETRO_PIXEL_FORMAT_0RGB1555; // формат по умолчанию по стандарту libretro

	// Ядро сообщит свои контроллеры прямо внутри set_environment —
	// поэтому прошлый список очищаем заранее.
	controller_types.clear();
	memset(analog, 0, sizeof(analog));
	memset(rumble, 0, sizeof(rumble));
	memset(&disk, 0, sizeof(disk));
	initial_disk = -1;
	hw_render = false;
	hw = {};
	hw_error.clear();
	option_defs.clear();
	option_categories.clear();
	hidden_options.clear();
	update_display = nullptr;
	options_updated = false;

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
		UtilityFunctions::push_error(String::utf8("RetroCore: сначала вызовите load_core()"));
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
			UtilityFunctions::push_error(String::utf8("RetroCore: не удалось прочитать файл игры "), path);
			return false;
		}
		game_data.assign(bytes.ptr(), bytes.ptr() + bytes.size());
		game.data = game_data.data();
		game.size = game_data.size();
	}

	// «Начни со второго диска» — ядро должно узнать об этом до загрузки игры.
	if (initial_disk >= 0 && disk.set_initial_image) {
		disk.set_initial_image((unsigned)initial_disk, initial_disk_path.c_str());
	}
	initial_disk = -1;

	if (!api.load_game(&game)) {
		UtilityFunctions::push_error(String::utf8("RetroCore: ядро не смогло загрузить игру "), path);
		game_data.clear();
		return false;
	}

	api.get_system_av_info(&av_info);
	game_loaded = true;
	if (hw_render && (getenv("SHELLBIT_TEST_NO_HW") != nullptr || !setup_hw_context())) {
		// Видеокарта не смогла дать то, что просит ядро, — играть не выйдет.
		if (hw_error.empty()) {
			hw_error = "проверка: аппаратная отрисовка отключена (SHELLBIT_TEST_NO_HW)";
		}
		UtilityFunctions::push_error(String::utf8("RetroCore: аппаратная отрисовка не запустилась: "), String::utf8(hw_error.c_str()));
		// Выгружать игру и ядро нельзя: ядро при выгрузке освобождает свои
		// текстуры через OpenGL, а OpenGL-то у него и нет — программа упала бы.
		// Поэтому оставляем ядро в памяти «как есть» (немного памяти —
		// не страшно) и больше его не трогаем.
		game_loaded = false;
		core_loaded = false;
		broken = true;
		return false;
	}
	load_sram();
	new_frame = false;
	audio.clear();
	return true;
}

void RetroCore::unload() {
	{
		// Ядру с OpenGL контекст нужен и при выгрузке: оно освобождает
		// свои текстуры и шейдеры.
		GlScope scope(this);
		if (game_loaded) {
			save_sram(); // пока игра ещё в памяти — записываем её сохранения
			api.unload_game();
			game_loaded = false;
		}
		if (hw_render && gl.is_valid() && hw.context_destroy) {
			hw.context_destroy(); // «контекст сейчас исчезнет — забудь про него»
		}
		if (core_loaded) {
			api.deinit();
			core_loaded = false;
		}
	}
	gl.destroy();
	hw_render = false;
	if (broken) {
		// См. load_game: ядро без OpenGL не выгружаем — просто забываем о нём.
		library.leak();
		if (current == this) {
			current = nullptr;
		}
		return;
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
	if (!game_loaded) {
		return;
	}
	GlScope scope(this); // ядро с OpenGL рисует в нашем контексте — делаем его текущим
	if (fb_resize && hw_render) {
		fb_resize = false;
		gl.create_framebuffer(av_info.geometry.max_width, av_info.geometry.max_height, hw.depth, hw.stencil);
	}
	api.run(); // внутри ядро вызовет video_cb, audio_*_cb и input_state_cb
}

// =====================================================================
// Аппаратная отрисовка (OpenGL)
// =====================================================================
// Ядро сказало SET_HW_RENDER: «мне нужен OpenGL такой-то версии».
// После load_game создаём свой контекст (gl_context.cpp) и «холст» —
// framebuffer размером с самый большой кадр, — и говорим ядру
// context_reset: «контекст готов, загружай свои шейдеры и текстуры».
// Каждый кадр ядро рисует в холст и вызывает video_cb с особым значением
// RETRO_HW_FRAME_BUFFER_VALID вместо пикселей — пиксели мы читаем сами.
bool RetroCore::setup_hw_context() {
	GLContext::Api api_type = GLContext::DESKTOP_GL;
	int major = (int)hw.version_major, minor = (int)hw.version_minor;
	switch (hw.context_type) {
		case RETRO_HW_CONTEXT_OPENGL:
			api_type = GLContext::DESKTOP_GL;
			if (major == 0) {
				major = 2;
				minor = 1;
			}
			break;
		case RETRO_HW_CONTEXT_OPENGL_CORE:
			api_type = GLContext::DESKTOP_GL_CORE;
			if (major < 3) {
				major = 3;
				minor = 2;
			}
			break;
		case RETRO_HW_CONTEXT_OPENGLES2:
			api_type = GLContext::GLES;
			major = 2;
			minor = 0;
			break;
		case RETRO_HW_CONTEXT_OPENGLES3:
			api_type = GLContext::GLES;
			major = 3;
			minor = 0;
			break;
		case RETRO_HW_CONTEXT_OPENGLES_VERSION:
			api_type = GLContext::GLES;
			break;
		default:
			hw_error = "ядро просит Vulkan или Direct3D — Shellbit пока умеет только OpenGL";
			return false;
	}
	if (!gl.create(api_type, major, minor)) {
		hw_error = gl.error();
		return false;
	}
	GlScope scope(this);
	if (!gl.create_framebuffer(av_info.geometry.max_width, av_info.geometry.max_height, hw.depth, hw.stencil)) {
		hw_error = gl.error();
		return false;
	}
	if (hw.context_reset) {
		hw.context_reset(); // «контекст готов» — ядро загружает шейдеры и текстуры
	}
	return true;
}

uintptr_t RetroCore::hw_get_framebuffer_cb() {
	return current ? (uintptr_t)current->gl.framebuffer() : 0;
}

retro_proc_address_t RetroCore::hw_get_proc_cb(const char *sym) {
	return current ? (retro_proc_address_t)current->gl.get_proc(sym) : nullptr;
}

void RetroCore::set_input(int port, int mask) {
	if (port >= 0 && port < 4) {
		input_masks[port] = (uint16_t)mask;
	}
}

void RetroCore::set_analog(int port, int stick, float x, float y) {
	if (port < 0 || port >= 4 || stick < 0 || stick > 1) {
		return;
	}
	// -1..1 → -32767..32767. CLAMP — на случай, если пришло чуть больше 1.
	analog[port][stick][0] = (int16_t)(std::clamp(x, -1.0f, 1.0f) * 32767.0f);
	analog[port][stick][1] = (int16_t)(std::clamp(y, -1.0f, 1.0f) * 32767.0f);
}

Array RetroCore::get_controller_types(int port) const {
	if (port < 0 || port >= controller_types.size()) {
		return Array();
	}
	return controller_types[port];
}

void RetroCore::set_controller_type(int port, int device) {
	if (core_loaded && api.set_controller_port_device && port >= 0 && port < 4 && device >= 0) {
		api.set_controller_port_device((unsigned)port, (unsigned)device);
	}
}

Vector2 RetroCore::get_rumble(int port) const {
	if (port < 0 || port >= 4) {
		return Vector2();
	}
	// В libretro моторы: STRONG = 0, WEAK = 1. В Godot — наоборот по порядку:
	// start_joy_vibration(device, weak, strong). Поэтому x — слабый, y — сильный.
	return Vector2(rumble[port][RETRO_RUMBLE_WEAK], rumble[port][RETRO_RUMBLE_STRONG]);
}

// =====================================================================
// Диски
// =====================================================================
// Настоящая PlayStation меняет диск так: открыть крышку, вынуть диск,
// вставить другой, закрыть крышку. Ядро libretro просит то же самое:
// set_eject_state(true) → set_image_index(n) → set_eject_state(false).

int RetroCore::get_disk_count() const {
	return (game_loaded && disk.get_num_images) ? (int)disk.get_num_images() : 0;
}

int RetroCore::get_disk_index() const {
	return (game_loaded && disk.get_image_index) ? (int)disk.get_image_index() : 0;
}

String RetroCore::get_disk_label(int index) const {
	char label[512] = {};
	if (game_loaded && disk.get_image_label && index >= 0 &&
			disk.get_image_label((unsigned)index, label, sizeof(label))) {
		return String::utf8(label);
	}
	return String();
}

String RetroCore::get_disk_path(int index) const {
	char path[4096] = {};
	if (game_loaded && disk.get_image_path && index >= 0 &&
			disk.get_image_path((unsigned)index, path, sizeof(path))) {
		return String::utf8(path);
	}
	return String();
}

bool RetroCore::set_disk(int index) {
	if (index < 0 || index >= get_disk_count() || !disk.set_eject_state || !disk.set_image_index) {
		return false;
	}
	if (!disk.set_eject_state(true)) { // открыть крышку
		return false;
	}
	bool ok = disk.set_image_index((unsigned)index); // сменить диск
	disk.set_eject_state(false); // закрыть крышку (даже если сменить не вышло)
	return ok;
}

void RetroCore::set_initial_disk(int index, const String &path) {
	initial_disk = index;
	initial_disk_path = path.utf8().get_data();
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
	GlScope scope(this); // некоторым ядрам с OpenGL контекст нужен и для снимка
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
	GlScope scope(this);
	return api.unserialize(data.ptr(), (size_t)data.size());
}

// =====================================================================
// Внутриигровые сохранения (SRAM).
// Ядро держит их у себя в памяти (retro_get_memory_data), а записать
// на диск должен фронтенд. Файл: <папка сохранений>/<имя игры>.srm
// Для файлов используем FileAccess из Godot: он понимает русские буквы
// в путях Windows, а обычный fopen — нет.
// =====================================================================
void RetroCore::load_sram() {
	sram_path = "";
	if (save_dir.empty()) {
		return;
	}
	String base = String::utf8(game_path.c_str()).get_file().get_basename();
	sram_path = String::utf8(save_dir.c_str()).path_join(base + ".srm");

	uint8_t *memory = (uint8_t *)api.get_memory_data(RETRO_MEMORY_SAVE_RAM);
	size_t size = api.get_memory_size(RETRO_MEMORY_SAVE_RAM);
	if (memory == nullptr || size == 0 || !FileAccess::file_exists(sram_path)) {
		return; // у игры нет сохранений или файла ещё нет
	}
	PackedByteArray data = FileAccess::get_file_as_bytes(sram_path);
	size_t count = std::min(size, (size_t)data.size());
	memcpy(memory, data.ptr(), count);
	UtilityFunctions::print(String::utf8("Загружено сохранение игры: "), sram_path);
}

bool RetroCore::save_sram() {
	if (!game_loaded || sram_path.is_empty()) {
		return false;
	}
	const uint8_t *memory = (const uint8_t *)api.get_memory_data(RETRO_MEMORY_SAVE_RAM);
	size_t size = api.get_memory_size(RETRO_MEMORY_SAVE_RAM);
	if (memory == nullptr || size == 0) {
		return false;
	}
	PackedByteArray data;
	data.resize((int64_t)size);
	memcpy(data.ptrw(), memory, size);
	Ref<FileAccess> file = FileAccess::open(sram_path, FileAccess::WRITE);
	if (file.is_null()) {
		UtilityFunctions::push_error(String::utf8("RetroCore: не удалось записать "), sram_path);
		return false;
	}
	file->store_buffer(data);
	return true;
}

// =====================================================================
// Настройки ядра (core options).
// Ядро при запуске сообщает список своих настроек и значения по
// умолчанию, а потом спрашивает «какое сейчас значение у X?».
// Если не ответить, ядро может отключить нужное — например, PCSX ReARMed
// без ответа отключает карты памяти.
// =====================================================================
void RetroCore::remember_default(const char *key, const char *value) {
	if (key && value) {
		options.emplace(key, value); // emplace НЕ перезаписывает то, что задал пользователь
	}
}

void RetroCore::set_option(const String &key, const String &value) {
	options[key.utf8().get_data()] = value.utf8().get_data();
	options_updated = true; // ядро спросит «что-то поменялось?» и перечитает
}

void RetroCore::set_language(int new_language) {
	language = (unsigned)new_language;
}

bool RetroCore::refresh_option_display() {
	return update_display != nullptr && update_display();
}

Array RetroCore::get_option_list() const {
	Array result;
	for (const OptionDef &def : option_defs) {
		Dictionary item;
		item["key"] = String::utf8(def.key.c_str());
		item["label"] = String::utf8(def.label.c_str());
		item["info"] = String::utf8(def.info.c_str());
		item["category"] = String::utf8(def.category.c_str());
		auto category = option_categories.find(def.category);
		item["category_label"] = category != option_categories.end() ? String::utf8(category->second.c_str()) : String();
		Array values;
		for (const OptionValue &value : def.values) {
			Array pair;
			pair.push_back(String::utf8(value.value.c_str()));
			pair.push_back(String::utf8(value.label.c_str()));
			values.push_back(pair);
		}
		item["values"] = values;
		item["default"] = String::utf8(def.default_value.c_str());
		auto current = options.find(def.key);
		item["value"] = String::utf8((current != options.end() ? current->second : def.default_value).c_str());
		item["visible"] = hidden_options.count(def.key) == 0;
		result.push_back(item);
	}
	return result;
}

// Строка из ядра (может быть NULL) → std::string.
static std::string text_or(const char *text, const char *fallback = "") {
	return text ? text : (fallback ? fallback : "");
}

// Формат v1: key, desc, info, values[], default_value.
// local — те же настройки на языке интерфейса (может быть NULL или неполным):
// берём из него надписи, где они есть, остальное — из английского us.
void RetroCore::read_options_v1(const retro_core_option_definition *us, const retro_core_option_definition *local) {
	option_defs.clear();
	option_categories.clear();
	for (; us && us->key; us++) {
		const retro_core_option_definition *loc = nullptr;
		for (const retro_core_option_definition *l = local; l && l->key; l++) {
			if (strcmp(l->key, us->key) == 0) {
				loc = l;
				break;
			}
		}
		OptionDef def;
		def.key = us->key;
		def.label = text_or(loc && loc->desc ? loc->desc : us->desc, us->key);
		def.info = text_or(loc && loc->info ? loc->info : us->info);
		def.default_value = text_or(us->default_value, us->values[0].value);
		for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX && us->values[i].value; i++) {
			const char *label = us->values[i].label;
			if (loc) { // у перевода ищем то же значение и берём его надпись
				for (int j = 0; j < RETRO_NUM_CORE_OPTION_VALUES_MAX && loc->values[j].value; j++) {
					if (strcmp(loc->values[j].value, us->values[i].value) == 0 && loc->values[j].label) {
						label = loc->values[j].label;
					}
				}
			}
			def.values.push_back({ us->values[i].value, text_or(label, us->values[i].value) });
		}
		remember_default(def.key.c_str(), def.default_value.c_str());
		option_defs.push_back(def);
	}
}

// Формат v2: то же самое плюс категории («Видео», «Звук», «Управление»…).
void RetroCore::read_options_v2(const retro_core_options_v2 *us, const retro_core_options_v2 *local) {
	option_defs.clear();
	option_categories.clear();
	if (us == nullptr) {
		return;
	}
	for (const retro_core_option_v2_category *c = us->categories; c && c->key; c++) {
		std::string label = text_or(c->desc, c->key);
		for (const retro_core_option_v2_category *l = local ? local->categories : nullptr; l && l->key; l++) {
			if (strcmp(l->key, c->key) == 0 && l->desc) {
				label = l->desc;
			}
		}
		option_categories[c->key] = label;
	}
	for (const retro_core_option_v2_definition *d = us->definitions; d && d->key; d++) {
		const retro_core_option_v2_definition *loc = nullptr;
		for (const retro_core_option_v2_definition *l = local ? local->definitions : nullptr; l && l->key; l++) {
			if (strcmp(l->key, d->key) == 0) {
				loc = l;
				break;
			}
		}
		OptionDef def;
		def.key = d->key;
		def.category = text_or(d->category_key);
		// Внутри категории у настройки бывает название короче (desc_categorized):
		// «Разрешение» вместо «Видео > Разрешение».
		const char *desc = d->desc_categorized && d->category_key ? d->desc_categorized : d->desc;
		const char *info = d->info_categorized && d->category_key ? d->info_categorized : d->info;
		if (loc) {
			const char *loc_desc = loc->desc_categorized && d->category_key ? loc->desc_categorized : loc->desc;
			const char *loc_info = loc->info_categorized && d->category_key ? loc->info_categorized : loc->info;
			if (loc_desc) desc = loc_desc;
			if (loc_info) info = loc_info;
		}
		def.label = text_or(desc, d->key);
		def.info = text_or(info);
		def.default_value = text_or(d->default_value, d->values[0].value);
		for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX && d->values[i].value; i++) {
			const char *label = d->values[i].label;
			if (loc) {
				for (int j = 0; j < RETRO_NUM_CORE_OPTION_VALUES_MAX && loc->values[j].value; j++) {
					if (strcmp(loc->values[j].value, d->values[i].value) == 0 && loc->values[j].label) {
						label = loc->values[j].label;
					}
				}
			}
			def.values.push_back({ d->values[i].value, text_or(label, d->values[i].value) });
		}
		remember_default(def.key.c_str(), def.default_value.c_str());
		option_defs.push_back(def);
	}
}

Dictionary RetroCore::get_options() const {
	Dictionary result;
	for (const auto &pair : options) {
		result[String::utf8(pair.first.c_str())] = String::utf8(pair.second.c_str());
	}
	return result;
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
	if (!current || port >= 4) {
		return 0;
	}
	uint16_t mask = current->input_masks[port];

	// Стики. Ядро спрашивает: «где левый стик по X?» —
	// index = RETRO_DEVICE_INDEX_ANALOG_LEFT, id = RETRO_DEVICE_ID_ANALOG_X.
	if ((device & RETRO_DEVICE_MASK) == RETRO_DEVICE_ANALOG) {
		if (index <= RETRO_DEVICE_INDEX_ANALOG_RIGHT && id <= RETRO_DEVICE_ID_ANALOG_Y) {
			return current->analog[port][index][id];
		}
		// «Насколько сильно нажата кнопка?» (курки у некоторых ядер).
		// Аналоговых кнопок у нас нет: нажата — значит до упора.
		if (index == RETRO_DEVICE_INDEX_ANALOG_BUTTON && id < 16) {
			return ((mask >> id) & 1) ? 0x7fff : 0;
		}
		return 0;
	}

	if ((device & RETRO_DEVICE_MASK) != RETRO_DEVICE_JOYPAD) {
		return 0;
	}
	if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
		return (int16_t)mask; // ядро просит сразу все кнопки
	}
	return (id < 16) ? (int16_t)((mask >> id) & 1) : 0;
}

// Ядро: «включи мотор effect на порту port с силой strength (0…65535)».
bool RetroCore::rumble_cb(unsigned port, enum retro_rumble_effect effect, uint16_t strength) {
	if (!current || port >= 4 || (effect != RETRO_RUMBLE_STRONG && effect != RETRO_RUMBLE_WEAK)) {
		return false;
	}
	current->rumble[port][effect] = strength / 65535.0f;
	return true;
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
			fb_resize = true; // кадр мог стать больше — холст пересоздадим перед следующим кадром
			return true;
		case RETRO_ENVIRONMENT_SET_MESSAGE: {
			const retro_message *message = (const retro_message *)data;
			UtilityFunctions::print("[core message] ", String::utf8(message->msg));
			return true;
		}
		case RETRO_ENVIRONMENT_SHUTDOWN:
			return true;

		// --- Аппаратная отрисовка ---
		case RETRO_ENVIRONMENT_SET_HW_RENDER: {
			retro_hw_render_callback *cb = (retro_hw_render_callback *)data;
			switch (cb->context_type) {
				case RETRO_HW_CONTEXT_OPENGL:
				case RETRO_HW_CONTEXT_OPENGL_CORE:
				case RETRO_HW_CONTEXT_OPENGLES2:
				case RETRO_HW_CONTEXT_OPENGLES3:
				case RETRO_HW_CONTEXT_OPENGLES_VERSION:
					break;
				default:
					return false; // Vulkan, Direct3D — не умеем; ядро может выбрать другое
			}
			// Отдаём ядру две наши функции: «куда рисовать» и «где функции OpenGL».
			cb->get_current_framebuffer = &RetroCore::hw_get_framebuffer_cb;
			cb->get_proc_address = &RetroCore::hw_get_proc_cb;
			hw = *cb;
			hw_render = true;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
			*(unsigned *)data = RETRO_HW_CONTEXT_OPENGL_CORE; // «мне удобнее всего OpenGL»
			return true;
		case RETRO_ENVIRONMENT_SET_HW_SHARED_CONTEXT & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
			return true; // контекст у ядра и так свой, ни с кем не общий

		// --- Смена дисков ---
		case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
			*(unsigned *)data = 1; // понимаем новую («ext») версию
			return true;
		case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
			// Старая версия: только первые поля. Остальные (названия, пути) — пустые.
			memset(&disk, 0, sizeof(disk));
			memcpy(&disk, data, sizeof(retro_disk_control_callback));
			return true;
		case RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE:
			disk = *(const retro_disk_control_ext_callback *)data;
			return true;

		// --- Вибрация ---
		case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE:
			// Отдаём ядру нашу функцию: через неё оно будет включать моторы.
			((retro_rumble_interface *)data)->set_rumble_state = &RetroCore::rumble_cb;
			return true;

		// --- Контроллеры ---
		case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO: {
			// Массив по портам; каждый — список типов {описание, номер}.
			// Конец массива — элемент с types == NULL.
			controller_types.clear();
			for (const retro_controller_info *port = (const retro_controller_info *)data; port && port->types; port++) {
				Array types;
				for (unsigned i = 0; i < port->num_types; i++) {
					Dictionary type;
					type["name"] = String::utf8(port->types[i].desc ? port->types[i].desc : "");
					type["id"] = (int64_t)port->types[i].id;
					types.push_back(type);
				}
				controller_types.push_back(types);
			}
			return true;
		}

		// --- Настройки ядра ---
		case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
			*(unsigned *)data = 2; // понимаем самый новый формат
			return true;
		case RETRO_ENVIRONMENT_GET_LANGUAGE:
			*(unsigned *)data = language; // на каком языке описывать настройки
			return true;
		case RETRO_ENVIRONMENT_SET_VARIABLES: {
			// Старый формат: value = "Описание; по_умолчанию|вариант2|вариант3"
			option_defs.clear();
			option_categories.clear();
			for (const retro_variable *v = (const retro_variable *)data; v && v->key; v++) {
				std::string text = v->value ? v->value : "";
				size_t start = text.find("; ");
				OptionDef def;
				def.key = v->key;
				def.label = (start == std::string::npos) ? v->key : text.substr(0, start);
				std::string values = (start == std::string::npos) ? text : text.substr(start + 2);
				size_t from = 0;
				while (from <= values.size()) {
					size_t bar = values.find('|', from);
					std::string value = values.substr(from, bar == std::string::npos ? std::string::npos : bar - from);
					def.values.push_back({ value, value });
					if (bar == std::string::npos) {
						break;
					}
					from = bar + 1;
				}
				def.default_value = def.values.empty() ? "" : def.values[0].value;
				remember_default(v->key, def.default_value.c_str());
				option_defs.push_back(def);
			}
			return true;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
			read_options_v1((const retro_core_option_definition *)data, nullptr);
			return true;
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
			const retro_core_options_intl *intl = (const retro_core_options_intl *)data;
			read_options_v1(intl->us, intl->local);
			return true;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
			read_options_v2((const retro_core_options_v2 *)data, nullptr);
			return data != nullptr;
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
			const retro_core_options_v2_intl *intl = (const retro_core_options_v2_intl *)data;
			read_options_v2(intl->us, intl->local);
			return intl->us != nullptr;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY: {
			// Ядро просит показать или спрятать настройку в меню.
			const retro_core_option_display *display = (const retro_core_option_display *)data;
			if (display && display->key) {
				if (display->visible) {
					hidden_options.erase(display->key);
				} else {
					hidden_options.insert(display->key);
				}
			}
			return true;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK: {
			const retro_core_options_update_display_callback *cb = (const retro_core_options_update_display_callback *)data;
			update_display = cb ? cb->callback : nullptr;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE: {
			retro_variable *v = (retro_variable *)data;
			auto it = v->key ? options.find(v->key) : options.end();
			v->value = (it != options.end()) ? it->second.c_str() : nullptr;
			return v->value != nullptr;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
			// «Поменялись ли настройки?» — да, если с прошлого вопроса вызывали set_option.
			*(bool *)data = options_updated;
			options_updated = false;
			return true;
		default:
			return false;
	}
}

// =====================================================================
// Видео: переводим пиксели ядра в формат RGBA8, который понимает Godot.
// =====================================================================
void RetroCore::on_video(const void *data, unsigned width, unsigned height, size_t pitch) {
	if (data == nullptr || width == 0 || height == 0) {
		return; // повтор прошлого кадра — картинка не меняется
	}

	// Ядро нарисовало кадр через OpenGL в наш холст — читаем его оттуда.
	if (data == RETRO_HW_FRAME_BUFFER_VALID) {
		frame_pixels.resize((int64_t)width * height * 4);
		uint8_t *out = frame_pixels.ptrw();
		// bottom_left_origin = true: ядро рисует «как обычно в OpenGL»,
		// снизу вверх, — тогда кадр нужно перевернуть.
		if (!gl.read_pixels((int)width, (int)height, hw.bottom_left_origin, out)) {
			return;
		}
		for (int64_t i = 3; i < frame_pixels.size(); i += 4) {
			out[i] = 255; // прозрачность ядру не нужна, а нам — мешает
		}
		frame = Image::create_from_data((int32_t)width, (int32_t)height, false, Image::FORMAT_RGBA8, frame_pixels);
		new_frame = true;
		return;
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
