// Точка входа модуля: Godot вызывает shellbit_core_init при загрузке .dll
// и здесь мы регистрируем наш класс RetroCore.

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "retro_core.h"
#include "seven_zip.h"

using namespace godot;

static void initialize_module(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(RetroCore);
	GDREGISTER_CLASS(SevenZip); // распаковка .7z (seven_zip.cpp)
}

static void uninitialize_module(ModuleInitializationLevel level) {}

extern "C" {
GDExtensionBool GDE_EXPORT shellbit_core_init(GDExtensionInterfaceGetProcAddress get_proc_address,
		const GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init_obj(get_proc_address, library, initialization);
	init_obj.register_initializer(initialize_module);
	init_obj.register_terminator(uninitialize_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
