#include "dynamic_library.h"

// windows.h подключаем ТОЛЬКО в этом файле: он объявляет много макросов
// (min, max, ERROR...), которые мешают остальному коду.
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#ifdef _WIN32
// UTF-8 → UTF-16: Windows понимает русские буквы в путях только в UTF-16.
static std::wstring to_wide(const std::string &text) {
	int length = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
	std::wstring result(length, L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, result.data(), length);
	return result;
}
#endif

bool DynamicLibrary::open(const std::string &path) {
	close();
#ifdef _WIN32
	// LOAD_WITH_ALTERED_SEARCH_PATH: если ядру нужны другие .dll,
	// Windows будет искать их рядом с ядром.
	handle = (void *)LoadLibraryExW(to_wide(path).c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
	if (!handle) {
		error = "LoadLibrary error code " + std::to_string(GetLastError());
	}
#else
	handle = dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL);
	if (!handle) {
		const char *message = dlerror();
		error = message ? message : "dlopen failed";
	}
#endif
	return handle != nullptr;
}

void DynamicLibrary::close() {
	if (!handle) {
		return;
	}
#ifdef _WIN32
	FreeLibrary((HMODULE)handle);
#else
	dlclose(handle);
#endif
	handle = nullptr;
}

void *DynamicLibrary::symbol(const char *name) const {
	if (!handle) {
		return nullptr;
	}
#ifdef _WIN32
	return (void *)GetProcAddress((HMODULE)handle, name);
#else
	return dlsym(handle, name);
#endif
}
