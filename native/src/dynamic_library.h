#pragma once
// Загрузка .dll (Windows) или .so (Linux) во время работы программы.
//
// Ядро libretro — это отдельный файл-библиотека. Мы открываем его
// и по имени находим внутри функции: retro_init, retro_run и т.д.
// В Windows для этого есть LoadLibrary/GetProcAddress, в Linux — dlopen/dlsym.
// Этот маленький класс прячет разницу между системами.

#include <string>

class DynamicLibrary {
public:
	~DynamicLibrary() { close(); }

	// path — путь в UTF-8. Возвращает false, если файл не открылся.
	bool open(const std::string &path);
	void close();
	bool is_open() const { return handle != nullptr; }

	// Найти функцию по имени. nullptr — если такой нет.
	void *symbol(const char *name) const;

	// Текст последней ошибки системы (для сообщений пользователю).
	std::string last_error() const { return error; }

private:
	void *handle = nullptr;
	std::string error;
};
