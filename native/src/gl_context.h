#pragma once
// GLContext — свой, невидимый OpenGL-контекст для ядер с «аппаратной отрисовкой».
//
// Зачем. Некоторые ядра (Nintendo 64 — mupen64plus-next, в будущем PS2)
// рисуют картинку не сами, а просят видеокарту: «дай мне OpenGL, я нарисую».
// OpenGL работает только внутри «контекста» — это как открытый «разговор»
// с видеокартой. У Godot свой контекст (или вообще Vulkan), и делить его
// с ядром нельзя: ядро сломало бы Godot настройки, и наоборот.
// Поэтому создаём ОТДЕЛЬНЫЙ контекст только для ядра — без окна на экране:
//   • Windows — WGL (через невидимое окно, без окна WGL не умеет);
//   • Linux / Steam Deck — EGL (умеет вообще без окна).
//
// Ядро рисует в наш «холст» (framebuffer), а мы читаем готовые пиксели
// обратно в память (glReadPixels) и показываем их как обычную картинку.
//
// Этот файл не зависит от Godot: только Windows API / EGL и OpenGL.

#include <cstdint>
#include <string>

class GLContext {
public:
	// Что просит ядро.
	enum Api { DESKTOP_GL, DESKTOP_GL_CORE, GLES };

	GLContext() = default;
	~GLContext() { destroy(); }

	// Создать контекст. major/minor — версия OpenGL (например, 3.3).
	// Возвращает false и пишет причину в error().
	bool create(Api api, int major, int minor);
	void destroy();
	bool is_valid() const { return valid; }
	const std::string &error() const { return last_error; }

	// Сделать контекст «текущим» в ЭТОМ потоке (OpenGL работает только
	// с текущим контекстом) и отпустить его, чтобы им мог пользоваться
	// другой поток. Один контекст может быть текущим только в одном потоке.
	//
	// Если в этом потоке уже был текущим чужой контекст (так бывает, когда
	// сам Godot рисует через OpenGL, а не Vulkan), make_current его запоминает,
	// а release возвращает на место — иначе Godot перестал бы рисовать.
	bool make_current();
	void release();

	// Адрес функции OpenGL по имени — ядро загружает через это всё, что ему нужно.
	void *get_proc(const char *name) const;

	// --- «Холст», в который рисует ядро (framebuffer object) ---
	// width × height — максимальный размер кадра, depth/stencil — нужны ли
	// ядру буфер глубины и трафарета (для 3D — нужны).
	bool create_framebuffer(int width, int height, bool depth, bool stencil);
	void delete_framebuffer();
	uint32_t framebuffer() const { return fbo; }
	// Прочитать кадр width × height из холста в out (RGBA, 4 байта на пиксель).
	// flip = true — перевернуть по вертикали (у OpenGL строки идут снизу вверх).
	bool read_pixels(int width, int height, bool flip, uint8_t *out);

private:
	bool load_functions();
	bool valid = false;
	std::string last_error;

	uint32_t fbo = 0, color_tex = 0, depth_rb = 0;
	int fb_width = 0, fb_height = 0;

#ifdef _WIN32
	void *saved_dc = nullptr;      // чужой контекст, который был текущим до нас
	void *saved_context = nullptr;
	void *window = nullptr; // HWND
	void *dc = nullptr;     // HDC
	void *context = nullptr; // HGLRC
	void *opengl32 = nullptr; // HMODULE opengl32.dll
#else
	void *egl = nullptr;      // libEGL.so.1
	void *display = nullptr;  // EGLDisplay
	void *config = nullptr;   // EGLConfig
	void *context = nullptr;  // EGLContext
	void *surface = nullptr;  // EGLSurface (маленький pbuffer 1×1)
	unsigned egl_api = 0;     // EGL_OPENGL_API или EGL_OPENGL_ES_API
	// Чужой контекст, который был текущим до нас (Godot на OpenGL):
	void *glx = nullptr;                // libGLX — если Godot рисует через GLX (X11)
	void *saved_glx_display = nullptr, *saved_glx_context = nullptr;
	unsigned long saved_glx_draw = 0, saved_glx_read = 0;
	void *saved_egl_display = nullptr, *saved_egl_context = nullptr;
	void *saved_egl_draw = nullptr, *saved_egl_read = nullptr;
	unsigned saved_egl_api = 0;
#endif

	// Функции OpenGL, которые нужны нам самим (ядро загружает свои сам).
	struct Gl {
		void (*GenFramebuffers)(int, uint32_t *);
		void (*DeleteFramebuffers)(int, const uint32_t *);
		void (*BindFramebuffer)(uint32_t, uint32_t);
		void (*FramebufferTexture2D)(uint32_t, uint32_t, uint32_t, uint32_t, int);
		void (*GenRenderbuffers)(int, uint32_t *);
		void (*DeleteRenderbuffers)(int, const uint32_t *);
		void (*BindRenderbuffer)(uint32_t, uint32_t);
		void (*RenderbufferStorage)(uint32_t, uint32_t, int, int);
		void (*FramebufferRenderbuffer)(uint32_t, uint32_t, uint32_t, uint32_t);
		uint32_t (*CheckFramebufferStatus)(uint32_t);
		void (*GenTextures)(int, uint32_t *);
		void (*DeleteTextures)(int, const uint32_t *);
		void (*BindTexture)(uint32_t, uint32_t);
		void (*TexImage2D)(uint32_t, int, int, int, int, int, uint32_t, uint32_t, const void *);
		void (*TexParameteri)(uint32_t, uint32_t, int);
		void (*ReadPixels)(int, int, int, int, uint32_t, uint32_t, void *);
		void (*PixelStorei)(uint32_t, int);
		uint32_t (*GetError)();
	} gl = {};
};
