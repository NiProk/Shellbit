#include "gl_context.h"

#include <cstdio>
#include <cstring>
#include <vector>

// Числа из заголовков OpenGL. Свои, чтобы не зависеть от GL-заголовков,
// которых в Windows без отдельного SDK нет.
#define GL_FRAMEBUFFER 0x8D40
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_DEPTH_ATTACHMENT 0x8D00
#define GL_DEPTH_STENCIL_ATTACHMENT 0x821A
#define GL_RENDERBUFFER 0x8D41
#define GL_DEPTH24_STENCIL8 0x88F0
#define GL_DEPTH_COMPONENT24 0x81A6
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_TEXTURE_2D 0x0DE1
#define GL_RGBA 0x1908
#define GL_RGBA8 0x8058
#define GL_UNSIGNED_BYTE 0x1401
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_NEAREST 0x2600
#define GL_PACK_ALIGNMENT 0x0D05

// =====================================================================
// Windows: WGL
// =====================================================================
#ifdef _WIN32
#include <windows.h>

#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB 0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x0001
#define WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB 0x0002
#define WGL_CONTEXT_ES2_PROFILE_BIT_EXT 0x0004
typedef HGLRC(WINAPI *CreateContextAttribsFn)(HDC, HGLRC, const int *);

bool GLContext::create(Api api, int major, int minor) {
	destroy();
	opengl32 = LoadLibraryA("opengl32.dll");

	// WGL не умеет без окна — делаем окно, которое никогда не показываем.
	WNDCLASSA wc = {};
	wc.lpfnWndProc = DefWindowProcA;
	wc.hInstance = GetModuleHandleA(nullptr);
	wc.lpszClassName = "ShellbitGL";
	RegisterClassA(&wc); // второй раз вернёт ошибку «уже есть» — это нормально
	HWND hwnd = CreateWindowExA(0, "ShellbitGL", "", WS_OVERLAPPEDWINDOW, 0, 0, 16, 16, nullptr, nullptr, wc.hInstance, nullptr);
	if (!hwnd) {
		last_error = "не удалось создать скрытое окно";
		return false;
	}
	window = hwnd;
	HDC hdc = GetDC(hwnd);
	dc = hdc;

	PIXELFORMATDESCRIPTOR pfd = {};
	pfd.nSize = sizeof(pfd);
	pfd.nVersion = 1;
	pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
	pfd.iPixelType = PFD_TYPE_RGBA;
	pfd.cColorBits = 32;
	pfd.cDepthBits = 24;
	pfd.cStencilBits = 8;
	int format = ChoosePixelFormat(hdc, &pfd);
	if (format == 0 || !SetPixelFormat(hdc, format, &pfd)) {
		last_error = "видеокарта не дала подходящий формат пикселей";
		destroy();
		return false;
	}

	// Сначала «старый» контекст — только чтобы получить функцию
	// wglCreateContextAttribsARB, которая умеет создавать нужную версию.
	HGLRC legacy = wglCreateContext(hdc);
	if (!legacy || !wglMakeCurrent(hdc, legacy)) {
		last_error = "не удалось создать контекст OpenGL";
		if (legacy) {
			wglDeleteContext(legacy);
		}
		destroy();
		return false;
	}
	CreateContextAttribsFn create_attribs = (CreateContextAttribsFn)wglGetProcAddress("wglCreateContextAttribsARB");
	HGLRC modern = nullptr;
	if (create_attribs) {
		int profile = api == DESKTOP_GL_CORE ? WGL_CONTEXT_CORE_PROFILE_BIT_ARB
				: api == GLES ? WGL_CONTEXT_ES2_PROFILE_BIT_EXT
							  : WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB;
		int attribs[] = {
			WGL_CONTEXT_MAJOR_VERSION_ARB, major,
			WGL_CONTEXT_MINOR_VERSION_ARB, minor,
			WGL_CONTEXT_PROFILE_MASK_ARB, profile,
			0
		};
		modern = create_attribs(hdc, nullptr, attribs);
	}
	wglMakeCurrent(nullptr, nullptr);
	if (modern) {
		wglDeleteContext(legacy);
		context = modern;
	} else if (api == DESKTOP_GL && major <= 2) {
		context = legacy; // старому OpenGL хватит и старого контекста
	} else {
		wglDeleteContext(legacy);
		last_error = "видеокарта не поддерживает OpenGL " + std::to_string(major) + "." + std::to_string(minor);
		destroy();
		return false;
	}

	if (!make_current()) {
		last_error = "не удалось включить контекст OpenGL (ошибка Windows " + std::to_string(GetLastError()) + ")";
		destroy();
		return false;
	}
	if (!load_functions()) {
		destroy();
		return false;
	}
	release();
	valid = true;
	return true;
}

void GLContext::destroy() {
	if (context) {
		if (make_current()) {
			delete_framebuffer();
		}
		wglMakeCurrent(nullptr, nullptr);
		wglDeleteContext((HGLRC)context);
		context = nullptr;
	}
	if (dc) {
		ReleaseDC((HWND)window, (HDC)dc);
		dc = nullptr;
	}
	if (window) {
		DestroyWindow((HWND)window);
		window = nullptr;
	}
	valid = false;
}

bool GLContext::make_current() {
	if (!context) {
		return false;
	}
	// Запоминаем, что было текущим (например, OpenGL самого Godot).
	saved_dc = wglGetCurrentDC();
	saved_context = wglGetCurrentContext();
	return wglMakeCurrent((HDC)dc, (HGLRC)context);
}

void GLContext::release() {
	if (saved_context) {
		wglMakeCurrent((HDC)saved_dc, (HGLRC)saved_context); // вернуть как было
	} else {
		wglMakeCurrent(nullptr, nullptr);
	}
	saved_dc = saved_context = nullptr;
}

void *GLContext::get_proc(const char *name) const {
	// wglGetProcAddress знает только «новые» функции; старые (OpenGL 1.1)
	// лежат прямо в opengl32.dll. Неудача у него — не только NULL, но и 1, 2, 3, −1.
	void *proc = (void *)wglGetProcAddress(name);
	if (proc == nullptr || proc == (void *)1 || proc == (void *)2 || proc == (void *)3 || proc == (void *)-1) {
		proc = opengl32 ? (void *)GetProcAddress((HMODULE)opengl32, name) : nullptr;
	}
	return proc;
}

// =====================================================================
// Linux, Steam Deck: EGL (библиотеку загружаем сами — dlopen)
// =====================================================================
#else
#include <dlfcn.h>

#define EGL_NONE 0x3038
#define EGL_SURFACE_TYPE 0x3033
#define EGL_PBUFFER_BIT 0x0001
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_OPENGL_BIT 0x0008
#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_OPENGL_ES3_BIT 0x0040
#define EGL_RED_SIZE 0x3024
#define EGL_GREEN_SIZE 0x3023
#define EGL_BLUE_SIZE 0x3022
#define EGL_ALPHA_SIZE 0x3021
#define EGL_WIDTH 0x3057
#define EGL_HEIGHT 0x3056
#define EGL_OPENGL_API 0x30A2
#define EGL_OPENGL_ES_API 0x30A0
#define EGL_CONTEXT_MAJOR_VERSION 0x3098
#define EGL_CONTEXT_MINOR_VERSION 0x30FB
#define EGL_CONTEXT_OPENGL_PROFILE_MASK 0x30FD
#define EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT 0x0001
#define EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT 0x0002
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD

typedef void *(*EglGetProcAddress)(const char *);
typedef void *(*EglGetDisplay)(void *);
typedef void *(*EglGetPlatformDisplay)(unsigned, void *, const int *);
typedef unsigned (*EglInitialize)(void *, int *, int *);
typedef unsigned (*EglBindAPI)(unsigned);
typedef unsigned (*EglChooseConfig)(void *, const int *, void **, int, int *);
typedef void *(*EglCreateContext)(void *, void *, void *, const int *);
typedef void *(*EglCreatePbufferSurface)(void *, void *, const int *);
typedef unsigned (*EglMakeCurrent)(void *, void *, void *, void *);
typedef unsigned (*EglDestroyContext)(void *, void *);
typedef unsigned (*EglDestroySurface)(void *, void *);
typedef unsigned (*EglTerminate)(void *);
typedef int (*EglGetError)();

#define EGL_FN(type, name) ((type)dlsym(egl, name))

// Код последней ошибки EGL — пишем его в сообщение, чтобы было что искать.
static std::string egl_error(void *egl) {
	auto get_error = (EglGetError)dlsym(egl, "eglGetError");
	char text[32];
	snprintf(text, sizeof(text), " (EGL 0x%X)", get_error ? get_error() : 0);
	return text;
}

static unsigned egl_api_for(GLContext::Api api) {
	return api == GLContext::GLES ? EGL_OPENGL_ES_API : EGL_OPENGL_API;
}

bool GLContext::create(Api api, int major, int minor) {
	destroy();
	egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_LOCAL);
	if (!egl) {
		egl = dlopen("libEGL.so", RTLD_NOW | RTLD_LOCAL); // Android: без «.1» в имени
	}
	if (!egl) {
		last_error = "нет библиотеки libEGL.so.1 (пакет mesa или драйвер видеокарты)";
		return false;
	}
	egl_api = egl_api_for(api);
	auto get_proc_address = EGL_FN(EglGetProcAddress, "eglGetProcAddress");
	auto initialize = EGL_FN(EglInitialize, "eglInitialize");
	int egl_major = 0, egl_minor = 0;

	// Обычный «дисплей» (X11 или Wayland). Не вышло — «без экрана вообще»
	// (так бывает, например, в игровом режиме Steam Deck без X11).
	display = EGL_FN(EglGetDisplay, "eglGetDisplay")(nullptr);
	if (!display || !initialize(display, &egl_major, &egl_minor)) {
		auto get_platform = (EglGetPlatformDisplay)get_proc_address("eglGetPlatformDisplayEXT");
		display = get_platform ? get_platform(EGL_PLATFORM_SURFACELESS_MESA, nullptr, nullptr) : nullptr;
		if (!display || !initialize(display, &egl_major, &egl_minor)) {
			last_error = "EGL не запустился";
			destroy();
			return false;
		}
	}
	EGL_FN(EglBindAPI, "eglBindAPI")(egl_api);

	int renderable = api == GLES ? (major >= 3 ? EGL_OPENGL_ES3_BIT : EGL_OPENGL_ES2_BIT) : EGL_OPENGL_BIT;
	int config_attribs[] = {
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, renderable,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
		EGL_NONE
	};
	int count = 0;
	if (!EGL_FN(EglChooseConfig, "eglChooseConfig")(display, config_attribs, &config, 1, &count) || count == 0) {
		last_error = "видеокарта не дала подходящий формат для OpenGL";
		destroy();
		return false;
	}

	std::vector<int> attribs = { EGL_CONTEXT_MAJOR_VERSION, major, EGL_CONTEXT_MINOR_VERSION, minor };
	if (api != GLES) {
		attribs.push_back(EGL_CONTEXT_OPENGL_PROFILE_MASK);
		attribs.push_back(api == DESKTOP_GL_CORE ? EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT : EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT);
	}
	attribs.push_back(EGL_NONE);
	context = EGL_FN(EglCreateContext, "eglCreateContext")(display, config, nullptr, attribs.data());
	if (!context) {
		last_error = "видеокарта не поддерживает OpenGL " + std::to_string(major) + "." + std::to_string(minor) + egl_error(egl);
		destroy();
		return false;
	}
	// Крошечная невидимая «поверхность» 1×1: рисовать ядро будет не в неё,
	// а в наш framebuffer, но некоторым драйверам без поверхности не по себе.
	int pbuffer_attribs[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
	surface = EGL_FN(EglCreatePbufferSurface, "eglCreatePbufferSurface")(display, config, pbuffer_attribs);

	if (!make_current()) {
		last_error = "не удалось включить контекст OpenGL" + egl_error(egl);
		destroy();
		return false;
	}
	if (!load_functions()) {
		destroy();
		return false;
	}
	release();
	valid = true;
	return true;
}

void GLContext::destroy() {
	if (egl && display) {
		if (context) {
			if (make_current()) {
				delete_framebuffer();
			}
			release();
			EGL_FN(EglDestroyContext, "eglDestroyContext")(display, context);
		}
		if (surface) {
			EGL_FN(EglDestroySurface, "eglDestroySurface")(display, surface);
		}
		EGL_FN(EglTerminate, "eglTerminate")(display);
	}
	context = surface = display = config = nullptr;
	if (egl) {
		dlclose(egl);
		egl = nullptr;
	}
	if (glx) {
		dlclose(glx);
		glx = nullptr;
	}
	valid = false;
}

// Функции GLX (OpenGL под X11). Нужны только для одного: если в этом потоке
// текущий контекст GLX (так рисует Godot без Vulkan), его надо «отпустить»
// перед нашим EGL, а потом вернуть. Одновременно два API в одном потоке
// библиотека libglvnd не разрешает (eglMakeCurrent вернёт EGL_BAD_ACCESS).
typedef void *(*GlxGetCurrentContext)();
typedef void *(*GlxGetCurrentDisplay)();
typedef unsigned long (*GlxGetCurrentDrawable)();
typedef int (*GlxMakeContextCurrent)(void *, unsigned long, unsigned long, void *);
typedef void *(*EglGetCurrentContext)();
typedef void *(*EglGetCurrentDisplay)();
typedef void *(*EglGetCurrentSurface)(int);
typedef unsigned (*EglQueryAPI)();
#define EGL_DRAW 0x3059
#define EGL_READ 0x305A

bool GLContext::make_current() {
	if (!context) {
		return false;
	}
	// 1) Чужой GLX-контекст в этом потоке? Запоминаем и отпускаем.
	if (!glx) {
		glx = dlopen("libGLX.so.0", RTLD_NOW | RTLD_LOCAL);
		if (!glx) {
			glx = dlopen("libGL.so.1", RTLD_NOW | RTLD_LOCAL);
		}
	}
	saved_glx_context = nullptr;
	if (glx) {
		auto current = (GlxGetCurrentContext)dlsym(glx, "glXGetCurrentContext");
		saved_glx_context = current ? current() : nullptr;
		if (saved_glx_context) {
			saved_glx_display = ((GlxGetCurrentDisplay)dlsym(glx, "glXGetCurrentDisplay"))();
			saved_glx_draw = ((GlxGetCurrentDrawable)dlsym(glx, "glXGetCurrentDrawable"))();
			saved_glx_read = ((GlxGetCurrentDrawable)dlsym(glx, "glXGetCurrentReadDrawable"))();
			((GlxMakeContextCurrent)dlsym(glx, "glXMakeContextCurrent"))(saved_glx_display, 0, 0, nullptr);
		}
	}
	// 2) Чужой EGL-контекст (Godot под Wayland)? Запоминаем — eglMakeCurrent его заменит.
	saved_egl_context = EGL_FN(EglGetCurrentContext, "eglGetCurrentContext")();
	if (saved_egl_context) {
		saved_egl_display = EGL_FN(EglGetCurrentDisplay, "eglGetCurrentDisplay")();
		saved_egl_draw = EGL_FN(EglGetCurrentSurface, "eglGetCurrentSurface")(EGL_DRAW);
		saved_egl_read = EGL_FN(EglGetCurrentSurface, "eglGetCurrentSurface")(EGL_READ);
		saved_egl_api = EGL_FN(EglQueryAPI, "eglQueryAPI")();
	}
	// Какой API (OpenGL или OpenGL ES) — запоминается для каждого потока
	// отдельно, поэтому выбираем его заново в том потоке, где работаем.
	EGL_FN(EglBindAPI, "eglBindAPI")(egl_api);
	return EGL_FN(EglMakeCurrent, "eglMakeCurrent")(display, surface, surface, context) != 0;
}

void GLContext::release() {
	if (!egl || !display) {
		return;
	}
	EGL_FN(EglMakeCurrent, "eglMakeCurrent")(display, nullptr, nullptr, nullptr);
	// Вернуть то, что было текущим до нас.
	if (saved_egl_context) {
		EGL_FN(EglBindAPI, "eglBindAPI")(saved_egl_api);
		EGL_FN(EglMakeCurrent, "eglMakeCurrent")(saved_egl_display, saved_egl_draw, saved_egl_read, saved_egl_context);
		saved_egl_context = nullptr;
	}
	if (saved_glx_context && glx) {
		((GlxMakeContextCurrent)dlsym(glx, "glXMakeContextCurrent"))(saved_glx_display, saved_glx_draw, saved_glx_read, saved_glx_context);
		saved_glx_context = nullptr;
	}
}

void *GLContext::get_proc(const char *name) const {
	if (!egl) {
		return nullptr;
	}
	void *proc = ((EglGetProcAddress)dlsym(egl, "eglGetProcAddress"))(name);
#ifdef __ANDROID__
	// На Android eglGetProcAddress обязан отдавать только «расширения»;
	// обычные функции (glGenFramebuffers…) лежат в библиотеке OpenGL ES.
	if (!proc) {
		static void *gles = dlopen("libGLESv3.so", RTLD_NOW | RTLD_LOCAL);
		static void *gles2 = dlopen("libGLESv2.so", RTLD_NOW | RTLD_LOCAL);
		proc = gles ? dlsym(gles, name) : nullptr;
		if (!proc && gles2) {
			proc = dlsym(gles2, name);
		}
	}
#endif
	return proc;
}
#endif

// =====================================================================
// Общее для Windows и Linux
// =====================================================================
bool GLContext::load_functions() {
#define LOAD(field, name)                                         \
	gl.field = reinterpret_cast<decltype(gl.field)>(get_proc(name)); \
	if (!gl.field) {                                              \
		last_error = std::string("в драйвере нет функции ") + name; \
		return false;                                             \
	}
	LOAD(GenFramebuffers, "glGenFramebuffers");
	LOAD(DeleteFramebuffers, "glDeleteFramebuffers");
	LOAD(BindFramebuffer, "glBindFramebuffer");
	LOAD(FramebufferTexture2D, "glFramebufferTexture2D");
	LOAD(GenRenderbuffers, "glGenRenderbuffers");
	LOAD(DeleteRenderbuffers, "glDeleteRenderbuffers");
	LOAD(BindRenderbuffer, "glBindRenderbuffer");
	LOAD(RenderbufferStorage, "glRenderbufferStorage");
	LOAD(FramebufferRenderbuffer, "glFramebufferRenderbuffer");
	LOAD(CheckFramebufferStatus, "glCheckFramebufferStatus");
	LOAD(GenTextures, "glGenTextures");
	LOAD(DeleteTextures, "glDeleteTextures");
	LOAD(BindTexture, "glBindTexture");
	LOAD(TexImage2D, "glTexImage2D");
	LOAD(TexParameteri, "glTexParameteri");
	LOAD(ReadPixels, "glReadPixels");
	LOAD(PixelStorei, "glPixelStorei");
	LOAD(GetError, "glGetError");
#undef LOAD
	return true;
}

bool GLContext::create_framebuffer(int width, int height, bool depth, bool stencil) {
	delete_framebuffer();
	fb_width = width;
	fb_height = height;

	// Текстура-«холст»: сюда ядро рисует кадр.
	gl.GenTextures(1, &color_tex);
	gl.BindTexture(GL_TEXTURE_2D, color_tex);
	gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	gl.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
	gl.BindTexture(GL_TEXTURE_2D, 0);

	gl.GenFramebuffers(1, &fbo);
	gl.BindFramebuffer(GL_FRAMEBUFFER, fbo);
	gl.FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color_tex, 0);

	// Буфер глубины (что ближе, что дальше) — нужен для 3D.
	if (depth) {
		gl.GenRenderbuffers(1, &depth_rb);
		gl.BindRenderbuffer(GL_RENDERBUFFER, depth_rb);
		gl.RenderbufferStorage(GL_RENDERBUFFER, stencil ? GL_DEPTH24_STENCIL8 : GL_DEPTH_COMPONENT24, width, height);
		gl.FramebufferRenderbuffer(GL_FRAMEBUFFER, stencil ? GL_DEPTH_STENCIL_ATTACHMENT : GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth_rb);
		gl.BindRenderbuffer(GL_RENDERBUFFER, 0);
	}
	bool ok = gl.CheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
	gl.BindFramebuffer(GL_FRAMEBUFFER, 0);
	if (!ok) {
		last_error = "не удалось собрать framebuffer";
	}
	return ok;
}

void GLContext::delete_framebuffer() {
	if (fbo) {
		gl.DeleteFramebuffers(1, &fbo);
		fbo = 0;
	}
	if (depth_rb) {
		gl.DeleteRenderbuffers(1, &depth_rb);
		depth_rb = 0;
	}
	if (color_tex) {
		gl.DeleteTextures(1, &color_tex);
		color_tex = 0;
	}
}

bool GLContext::read_pixels(int width, int height, bool flip, uint8_t *out) {
	if (!fbo || width <= 0 || height <= 0 || width > fb_width || height > fb_height) {
		return false;
	}
	gl.BindFramebuffer(GL_FRAMEBUFFER, fbo);
	gl.PixelStorei(GL_PACK_ALIGNMENT, 1);
	gl.ReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, out);
	gl.BindFramebuffer(GL_FRAMEBUFFER, 0);
	if (flip) {
		// glReadPixels отдаёт строки снизу вверх — переворачиваем на месте.
		size_t row = (size_t)width * 4;
		std::vector<uint8_t> tmp(row);
		for (int y = 0; y < height / 2; y++) {
			uint8_t *a = out + (size_t)y * row;
			uint8_t *b = out + (size_t)(height - 1 - y) * row;
			memcpy(tmp.data(), a, row);
			memcpy(a, b, row);
			memcpy(b, tmp.data(), row);
		}
	}
	return true;
}
