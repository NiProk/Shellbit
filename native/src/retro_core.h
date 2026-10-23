#pragma once
// RetroCore — узел Godot, который запускает ядро libretro.
//
// Из GDScript он выглядит как обычный узел:
//   var core = ClassDB.instantiate("RetroCore")
//   core.load_core("C:/.../fceumm_libretro.dll")
//   core.load_game("D:/Games/game.nes")
//   core.run_frame()                 # 60 раз в секунду
//   var image = core.get_frame()     # картинка последнего кадра
//   var sound = core.take_audio()    # звук, накопленный с прошлого раза

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "dynamic_library.h"
#include "libretro.h"

namespace godot {

class RetroCore : public Node {
	GDCLASS(RetroCore, Node)

public:
	// Номера кнопок RetroPad (так их нумерует libretro).
	// В GDScript доступны как RetroCore.BUTTON_A и т.д.
	enum {
		BUTTON_B = RETRO_DEVICE_ID_JOYPAD_B,
		BUTTON_Y = RETRO_DEVICE_ID_JOYPAD_Y,
		BUTTON_SELECT = RETRO_DEVICE_ID_JOYPAD_SELECT,
		BUTTON_START = RETRO_DEVICE_ID_JOYPAD_START,
		BUTTON_UP = RETRO_DEVICE_ID_JOYPAD_UP,
		BUTTON_DOWN = RETRO_DEVICE_ID_JOYPAD_DOWN,
		BUTTON_LEFT = RETRO_DEVICE_ID_JOYPAD_LEFT,
		BUTTON_RIGHT = RETRO_DEVICE_ID_JOYPAD_RIGHT,
		BUTTON_A = RETRO_DEVICE_ID_JOYPAD_A,
		BUTTON_X = RETRO_DEVICE_ID_JOYPAD_X,
		BUTTON_L = RETRO_DEVICE_ID_JOYPAD_L,
		BUTTON_R = RETRO_DEVICE_ID_JOYPAD_R,
		BUTTON_L2 = RETRO_DEVICE_ID_JOYPAD_L2,
		BUTTON_R2 = RETRO_DEVICE_ID_JOYPAD_R2,
		BUTTON_L3 = RETRO_DEVICE_ID_JOYPAD_L3,
		BUTTON_R3 = RETRO_DEVICE_ID_JOYPAD_R3,
	};

	RetroCore();
	~RetroCore();

	// --- Команды для GDScript ---
	void set_system_directory(const String &path); // где лежат BIOS
	void set_save_directory(const String &path); // куда ядро пишет сохранения
	bool load_core(const String &path);
	bool load_game(const String &path);
	void unload();
	bool is_running() const { return game_loaded; }

	void run_frame();
	void set_input(int port, int mask); // mask — по биту на каждую кнопку
	// Положение стика: stick 0 — левый, 1 — правый; x и y — от -1 до 1
	// (как Input.get_joy_axis в Godot: вправо и вниз — плюс).
	void set_analog(int port, int stick, float x, float y);
	// Какие контроллеры ядро умеет подключать к порту — ядро само
	// присылает этот список. [{"name": "DualShock", "id": 517}, ...]
	Array get_controller_types(int port) const;
	// «Вставить» в порт другой контроллер (например, DualShock вместо обычного).
	void set_controller_type(int port, int device);
	// Вибрация, которую сейчас хочет игра: x — слабый (быстрый) мотор,
	// y — сильный (тяжёлый), от 0 до 1. Ядро меняет их, когда захочет.
	Vector2 get_rumble(int port) const;

	bool has_new_frame() const { return new_frame; }
	Ref<Image> get_frame();
	PackedVector2Array take_audio();

	Dictionary get_av_info() const;
	Dictionary get_system_info() const;

	PackedByteArray save_state();
	bool load_state(const PackedByteArray &data);

	// Внутриигровые сохранения (батарейка картриджа, карта памяти PS1).
	// Загружаются сами в load_game(), записываются сами в unload().
	// save_sram() можно вызвать и вручную — «на всякий случай».
	bool save_sram();

	// Настройки ядра (core options). Ядро объявляет их и значения по умолчанию,
	// а фронтенд может поменять: set_option("pcsx_rearmed_memcard2", "enabled").
	void set_option(const String &key, const String &value);
	Dictionary get_options() const;

protected:
	static void _bind_methods();

private:
	// Указатели на функции внутри .dll ядра.
	struct Api {
		void (*init)();
		void (*deinit)();
		unsigned (*api_version)();
		void (*get_system_info)(retro_system_info *);
		void (*get_system_av_info)(retro_system_av_info *);
		void (*set_environment)(retro_environment_t);
		void (*set_video_refresh)(retro_video_refresh_t);
		void (*set_audio_sample)(retro_audio_sample_t);
		void (*set_audio_sample_batch)(retro_audio_sample_batch_t);
		void (*set_input_poll)(retro_input_poll_t);
		void (*set_input_state)(retro_input_state_t);
		void (*run)();
		bool (*load_game)(const retro_game_info *);
		void (*unload_game)();
		size_t (*serialize_size)();
		bool (*serialize)(void *, size_t);
		bool (*unserialize)(const void *, size_t);
		void *(*get_memory_data)(unsigned);
		size_t (*get_memory_size)(unsigned);
		void (*set_controller_port_device)(unsigned, unsigned); // может не быть
	};

	// libretro вызывает НАШИ функции (колбэки), когда ему что-то нужно:
	// «вот кадр», «вот звук», «какие кнопки нажаты?».
	// Это обычные функции без объекта, поэтому храним указатель
	// на текущий RetroCore в статической переменной.
	static RetroCore *current;
	static bool environment_cb(unsigned cmd, void *data);
	static void video_cb(const void *data, unsigned width, unsigned height, size_t pitch);
	static void audio_sample_cb(int16_t left, int16_t right);
	static size_t audio_batch_cb(const int16_t *data, size_t frames);
	static void input_poll_cb();
	static int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id);
	static void log_cb(enum retro_log_level level, const char *fmt, ...);
	static bool rumble_cb(unsigned port, enum retro_rumble_effect effect, uint16_t strength);

	bool on_environment(unsigned cmd, void *data);
	void on_video(const void *data, unsigned width, unsigned height, size_t pitch);
	void push_audio(const int16_t *data, size_t frames);
	void remember_default(const char *key, const char *value);
	void load_sram();

	DynamicLibrary library;
	Api api = {};
	bool core_loaded = false;
	bool game_loaded = false;

	std::string system_dir;
	std::string save_dir;
	std::string game_path;
	String sram_path; // <папка сохранений>/<имя игры>.srm
	// Настройки ядра: ключ → значение. std::map не перемещает строки
	// при добавлении новых, поэтому указатель value.c_str(), отданный ядру,
	// остаётся рабочим.
	std::map<std::string, std::string> options;
	std::vector<uint8_t> game_data; // ядру нужен файл игры в памяти, пока игра идёт

	retro_pixel_format pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
	retro_system_av_info av_info = {};

	PackedByteArray frame_pixels;
	Ref<Image> frame;
	bool new_frame = false;

	PackedVector2Array audio;
	uint16_t input_masks[4] = { 0, 0, 0, 0 };
	// analog[порт][стик][0 — X, 1 — Y], от -32767 до 32767, как просит libretro.
	int16_t analog[4][2][2] = {};
	Array controller_types; // по массиву типов на каждый порт
	float rumble[4][2] = {}; // rumble[порт][0 — сильный, 1 — слабый], от 0 до 1
};

} // namespace godot
