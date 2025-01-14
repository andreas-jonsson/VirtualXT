newoption {
    trigger = "sdl-config",
    value = "PATH",
    description = "Path to SDL config script"
}

newoption {
    trigger = "test",
    description = "Generate makefiles for libvxt tests"
}

newoption {
    trigger = "modules",
    description = "Only generate makefiles for listed modules"
}

newoption {
    trigger = "no-modules",
    description = "Don't generate makefiles for modules"
}

newoption {
    trigger = "dynamic",
    description = "Use dynamic modules"
}

newoption {
    trigger = "memclear",
    description = "Clear main memory when initializing"
}

newoption {
    trigger = "validator",
    description = "Enable the PI8088 hardware validator"
}

newoption {
    trigger = "circle",
    value = "PATH",
    description = "Path to the Circle library"
}

newaction {
    trigger = "check",
    description = "Run CppCheck on libvxt",
    execute = function ()
        return os.execute("cppcheck --force --enable=style -I lib/vxt/include lib/vxt")
    end
}

newaction {
    trigger = "doc",
    description = "Generate libvxt API documentation",
    execute = function ()
        return os.execute("cd lib/vxt/include && doxygen .doxygen")
    end
}

workspace "virtualxt"
    configurations { "release", "debug" }
    platforms { "native", "web" }
    language "C"
    cdialect "C11"

    local handle = io.popen("git branch --show-current")
    if handle then
        local branch = handle:read("l") or "?"
        print("Branch: " .. branch)
        if branch == "release" then
            defines "VXT_VERSION_RELEASE"
        end
        handle:close()
    end

    filter "configurations:debug"
        symbols "On"
        optimize "Off"
        defines "VXT_DEBUG_PREFETCH"

    filter "configurations:release"
        defines "NDEBUG"
        optimize "On"

    filter "platforms:web"
        toolset "clang"
        defines "VXT_NO_LIBC"
        includedirs "lib/libc"
        buildoptions { "--target=wasm32", "-mbulk-memory", "-flto" }

    filter "options:memclear"
        defines "VXTU_MEMCLEAR"

    filter "options:validator"
        defines "PI8088"
        links "gpiod"

    filter "system:windows"
        defines "_CRT_SECURE_NO_WARNINGS"
        
    filter "action:vs*"
        architecture "x86_64"

    filter { "toolset:clang or gcc", "not action:vs*" }
        buildoptions { "-pedantic", "-Wall", "-Wextra", "-Werror", "-Wno-implicit-fallthrough", "-Wno-unused-result" }

    filter { "toolset:clang or gcc", "configurations:debug" }
        buildoptions "-Wno-error"

    local modules = {}
    local modules_link_callback = {}

    if not _OPTIONS["no-modules"] then
        filter {}

        defines "VXTU_MODULES"
        if not _OPTIONS["dynamic"] then
            defines "VXTU_STATIC_MODULES"
        end

        local mod_list = {}
        for _,f in ipairs(os.matchfiles("modules/**/premake5.lua")) do
            local enable = true
            local name = path.getname(path.getdirectory(f))

			if _OPTIONS["modules"] then
				enable = false
	            for mod in string.gmatch(_OPTIONS["modules"], "[%w_]+") do
	                if mod == name then
	                    enable = true
	                    break
	                end
	            end
            end
            
            if enable then
                table.insert(mod_list, name)
                defines { "VXTU_MODULE_" .. string.upper(name) }
            end
        end
        
		module_link_callback = function(f)
			if _OPTIONS["dynamic"] then
				filter {}
				f()
				filter {}
			else
				table.insert(modules_link_callback, f)
			end
		end

        for _,name in ipairs(mod_list) do
            project(name)
                if _OPTIONS["dynamic"] then
					kind "SharedLib"
					targetdir "modules"
					targetprefix ""
					targetextension ".vxt"
					basedir "."
					links "vxt"
					pic "On"
                else
					kind "StaticLib"
					basedir "."
				end

                includedirs { "lib/vxt/include", "front/common" }
                defines { "VXTU_MODULE_NAME=" .. name }

                cleancommands {
                    "{RMFILE} modules/" .. name .. ".*",
                    "${MAKE} clean %{cfg.buildcfg}"
                }

                filter {}

    		dofile("modules/" .. name .. "/premake5.lua")
			table.insert(modules, name)
        end

        module_link_callback = nil
    end

    -- This is just a dummy project.
    project "modules"
        kind "StaticLib"
        files "modules/dummy.c"
        links(modules)
        io.writefile("modules/dummy.c", "int dummy;\n")

    project "inih"
        kind "StaticLib"
        files { "lib/inih/ini.h", "lib/inih/ini.c" }

    project "microui"
        kind "StaticLib"
        files { "lib/microui/src/microui.h", "lib/microui/src/microui.c" }

    project "miniz"
        kind "StaticLib"
        pic "On"
        files { "lib/miniz/miniz.h", "lib/miniz/miniz.c" }
        
        filter "toolset:clang or gcc"
            buildoptions "-Wno-error=type-limits"

    project "fat16"
        kind "StaticLib"
        pic "On"
        files {
            "lib/fat16/fat16.h",
            "lib/fat16/blockdev.h",
            "lib/fat16/fat16_internal.h",
            "lib/fat16/fat16.c"
        }

    project "vxt"
        if not _OPTIONS["no-modules"] and _OPTIONS["dynamic"] then
            kind "SharedLib"
            targetdir "build/sdl2"
            pic "On"
        else
            kind "StaticLib"
        end

        files { "lib/vxt/**.h", "lib/vxt/*.c" }
        includedirs "lib/vxt/include"
        defines "VXT_EXPORT"
        removefiles { "lib/vxt/testing.h", "lib/vxt/testsuit.c" }

	project "ebridge-tool"
		kind "ConsoleApp"
		targetname "ebridge"
		targetdir "build/ebridge"
		
		defines { "LIBPCAP", "_DEFAULT_SOURCE=1" }
		files "tools/ebridge/ebridge.c"

		filter "system:windows"
			includedirs "tools/npcap/sdk/Include"
			defines "_WINSOCK_DEPRECATED_NO_WARNINGS"
			links { "Ws2_32", "tools/npcap/sdk/Lib/x64/wpcap" }
			
		filter "not system:windows"
			links "pcap"

    project "libretro-frontend"
        kind "SharedLib"
        targetname "virtualxt_libretro"
        targetprefix ""
        targetdir "build/libretro"
        pic "On"

        includedirs { "lib/libretro", "front/common" }
        files { "front/libretro/*.h", "front/libretro/*.c" }
        
        defines { "FRONTEND_VIDEO_RED=2", "FRONTEND_VIDEO_GREEN=1", "FRONTEND_VIDEO_BLUE=0", "FRONTEND_VIDEO_ALPHA=3" }
        includedirs "lib/vxt/include"
        files { "lib/vxt/**.h", "lib/vxt/*.c" }
        removefiles { "lib/vxt/testing.h", "lib/vxt/testsuit.c" }

        links { "miniz", "fat16" }
        includedirs { "lib/miniz", "lib/fat16" }
        defines "ZIP2IMG"

        cleancommands {
            "{RMDIR} build/libretro",
            "${MAKE} clean %{cfg.buildcfg}"
        }

        filter "toolset:clang or gcc"
            buildoptions { "-Wno-atomic-alignment", "-Wno-deprecated-declarations" }

        -- TODO: Remove this filter! This is here to fix an issue with the GitHub builder.
        filter "not system:windows"
            postbuildcommands "{COPYFILE} front/libretro/virtualxt_libretro.info build/libretro/"

    project "web-frontend"
        kind "ConsoleApp"
        targetname "virtualxt"
        targetprefix ""
        targetextension ".wasm"
        targetdir "build/web"

        includedirs "front/common"
        files { "front/web/*.h", "front/web/*.c" }

        includedirs "lib/vxt/include"
        files { "lib/vxt/**.h", "lib/vxt/*.c" }
        removefiles { "lib/vxt/testing.h", "lib/vxt/testsuit.c" }

        includedirs "lib/libc"
        defines { "SCANF_FREESTANDING", "SCANF_DISABLE_SUPPORT_FLOAT" }
        files { "lib/libc/*.h", "lib/libc/*.c", "lib/scanf/scanf.c", "lib/printf/printf.h", "lib/printf/printf.c" }

        files "modules/modules.h"
        includedirs "modules"

        if not _OPTIONS["no-modules"] and not _OPTIONS["dynamic"] then
            links(modules)
            for _,f in ipairs(modules_link_callback) do
				f()
				filter {}
            end
        end

        -- Perhaps move this to options?
        local page_size = 0x10000
        local memory = {
            initial = 350 * page_size,   -- Initial size of the linear memory (1 page = 64kB)
            max = 350 * page_size,       -- Maximum size of the linear memory
            base = 6560                  -- Offset in linear memory to place global data
        }

        linkoptions { "--target=wasm32", "-nostdlib", "-Wl,--allow-undefined", "-Wl,--lto-O3", "-Wl,--no-entry", "-Wl,--export-all", "-Wl,--import-memory" }
        linkoptions { "-Wl,--initial-memory=" .. tostring(memory.initial), "-Wl,--max-memory=" .. tostring(memory.max), "-Wl,--global-base=" .. tostring(memory.base) }

        postbuildcommands {
            "{COPYFILE} front/web/index.html build/web/",
            "{COPYFILE} front/web/script.js build/web/",
            "{COPYFILE} front/web/favicon.ico build/web/",
            "{COPYFILE} front/web/disk.png build/web/",
            "{COPYFILE} boot/freedos_web_hd.img build/web/",
            "{COPYFILE} boot/elks_hd.img build/web/",
            "{COPYDIR} lib/simple-keyboard/build/ build/web/kb/"
        }

        cleancommands {
            "{RMDIR} build/web",
            "${MAKE} clean %{cfg.buildcfg}"
        }

    project "sdl2-frontend"
        kind "ConsoleApp"
        targetname "virtualxt"
        targetdir "build/sdl2"
        
        files "modules/modules.h"
        includedirs "modules"

        if not _OPTIONS["no-modules"] then
            if _OPTIONS["dynamic"] then
				dependson "modules"
			else
                links(modules)
                for _,f in ipairs(modules_link_callback) do
					f()
					filter {}
                end
            end
        end

        files { "front/sdl2/*.h", "front/sdl2/*.c" }
        includedirs { "lib/vxt/include", "lib/inih", "lib/microui/src", "front/common" }
        links { "vxt", "inih", "microui" }

        cleancommands {
            "{RMDIR} build/sdl2",
            "${MAKE} clean %{cfg.buildcfg}"
        }

        filter "action:vs*"
            libdirs { path.join(_OPTIONS["sdl-config"], "lib", "x64") }
            includedirs { path.join(_OPTIONS["sdl-config"], "include") }
            links { "SDL2", "SDL2main" }

        filter "not action:vs*"
            local sdl_cfg = path.join(_OPTIONS["sdl-config"], "sdl2-config")
            buildoptions { string.format("`%s --cflags`", sdl_cfg) }
            linkoptions { string.format("`%s --libs`", sdl_cfg) }

        filter "options:validator"
            files { "tools/validator/pi8088/pi8088.c", "tools/validator/pi8088/udmask.h" }

		filter "toolset:clang or gcc"
			links "m"
			buildoptions "-Wno-unused-parameter"
			linkoptions "-Wl,-rpath,'$$ORIGIN'/../lib"

		filter "toolset:clang"
            buildoptions { "-Wno-missing-field-initializers", "-Wno-missing-braces" }

        filter "toolset:gcc"
            buildoptions { "-Wno-uninitialized", "-Wno-missing-field-initializers", "-Wno-missing-braces" }
            
    project "sdl3-frontend"
        kind "ConsoleApp"
        targetname "virtualxt"
        targetdir "build/sdl3"
        
        files "modules/modules.h"
        includedirs "modules"

        if not _OPTIONS["no-modules"] then
            if _OPTIONS["dynamic"] then
				dependson "modules"
			else
                links(modules)
                for _,f in ipairs(modules_link_callback) do
					f()
					filter {}
                end
            end
        end

        files { "front/sdl3/*.h", "front/sdl3/*.c" }
        includedirs { "lib/vxt/include", "lib/inih", "lib/microui/src", "front/common" }
        links { "vxt", "inih", "microui" }

        cleancommands {
            "{RMDIR} build/sdl3",
            "${MAKE} clean %{cfg.buildcfg}"
        }

        filter "action:vs*"
            libdirs { path.join(_OPTIONS["sdl-config"], "lib", "x64") }
            includedirs { path.join(_OPTIONS["sdl-config"], "include") }
            links { "SDL3", "SDL3main" }

        filter "not action:vs*"
            local sdl_cfg = path.join(_OPTIONS["sdl-config"], "sdl3-config")
            buildoptions { string.format("`%s --cflags`", sdl_cfg) }
            linkoptions { string.format("`%s --libs`", sdl_cfg) }

		filter "toolset:clang or gcc"
			links "m"
			buildoptions "-Wno-unused-parameter"
			linkoptions "-Wl,-rpath,'$$ORIGIN'/../lib"

		filter "toolset:clang"
            buildoptions { "-Wno-missing-field-initializers", "-Wno-missing-braces" }

        filter "toolset:gcc"
            buildoptions { "-Wno-uninitialized", "-Wno-missing-field-initializers", "-Wno-missing-braces" }
            
    project "terminal-frontend"
        kind "ConsoleApp"
        targetname "vxterm"
        targetdir "build/terminal"
        
        files "modules/modules.h"
        includedirs "modules"

        if not _OPTIONS["no-modules"] then
            if _OPTIONS["dynamic"] then
                dependson "modules"
            else
                links(modules)
                for _,f in ipairs(modules_link_callback) do
					f()
					filter {}
                end
            end
        end

		files { "front/terminal/*.h", "front/terminal/*.c" }
		includedirs { "lib/vxt/include", "lib/inih", "lib/termbox2", "front/common" }
		links { "m", "vxt", "inih" }

        cleancommands {
            "{RMDIR} build/terminal",
            "${MAKE} clean %{cfg.buildcfg}"
        }

        filter "options:validator"
            files { "tools/validator/pi8088/pi8088.c", "tools/validator/pi8088/udmask.h" }

        filter "toolset:clang or gcc"
            buildoptions { "-Wno-unused-parameter", "-Wno-implicit-function-declaration", "-Wno-incompatible-pointer-types" }
            linkoptions "-Wl,-rpath,'$$ORIGIN'/../lib"

        filter "toolset:clang"
            buildoptions { "-Wno-missing-field-initializers", "-Wno-missing-braces" }

        filter "toolset:gcc"
            buildoptions "-Wno-maybe-uninitialized"

	local circle_path = _OPTIONS["circle"]
	if circle_path then
		project "rpi-frontend"
			kind "Makefile"
			buildcommands { "CIRCLEHOME=\"" .. circle_path .. "\" ${MAKE} -C front/rpi" }
			cleancommands { "CIRCLEHOME=\"" .. circle_path .. "\" ${MAKE} -C front/rpi clean" }
	end

if _OPTIONS["test"] then
    project "test"
        kind "ConsoleApp"
        targetdir "test"
        includedirs "lib/vxt/include"
        defines { "TESTING", "VXTU_MEMCLEAR" }
        files { "test/test.c", "lib/vxt/**.h", "lib/vxt/*.c" }

        optimize "Off"
        symbols "On"

        postbuildcommands "./test/test"
        cleancommands "{RMDIR} test"

        filter { "toolset:clang or gcc" }
            buildoptions { "-Wno-unused-function", "-Wno-unused-variable", "--coverage" }
            linkoptions "--coverage"
    
    io.writefile("test/test.c", (function()
        print("Searching for tests:")

        local pattern = _OPTIONS["test"]
        local externals = ""
        local calls = ""

        for _,file in pairs(os.matchfiles("lib/vxt/**.c")) do
            if not pattern or string.find(file, pattern, 1, true) then
                print(file)
                files { file } -- Ensure any files in recursive directories are added.
                for line in io.lines(file) do
                    if string.startswith(line, "TEST(") then
                        local name = string.sub(line, 6, -2)
                        externals = externals .. string.format("extern int test_%s(struct Test T);\n", name)
                        calls = calls .. string.format("\tRUN_TEST(test_%s);\n", name)
                    end
                end
            end
        end

        print("Generating test code:")

        -- Avoid using string.format here as the strings can be very large.

        local head = '#include <stdio.h>\n#include "../lib/vxt/testing.h"\n\n#define RUN_TEST(t) { ok += run_test(t) ? 1 : 0; num++; }\n\n' .. externals
        local body = "\t(void)argc; (void)argv;\n\tint ok = 0, num = 0;\n\n" .. calls

        body = body .. '\n\tprintf("%d/%d tests passed!\\n", ok, num);\n\treturn (num - ok) ? -1 : 0;\n'
        return head .. "\nint main(int argc, char *argv[]) {\n" .. body .. "}\n"
    end)())
end

io.writefile("modules/modules.h", (function()
    local is_dynamic = _OPTIONS["dynamic"]
    local str = "#include <vxt/vxtu.h>\n\nstruct vxtu_module_entry {\n\tconst char *name;\n\tvxtu_module_entry_func *(*entry)(int(*)(const char*, ...));\n};\n\n"
    if not is_dynamic then
        for _,mod in ipairs(modules) do
            str = string.format("%s#ifdef VXTU_MODULE_%s\n\textern vxtu_module_entry_func *_vxtu_module_%s_entry(int(*)(const char*, ...));\n#endif\n", str, string.upper(mod), mod)
        end
        str = str .. "\n"
    end
    str = string.format("%sconst struct vxtu_module_entry vxtu_module_table[] = {\n", str)
    for _,mod in ipairs(modules) do
        if is_dynamic then
            str = string.format('%s\t{ "%s", NULL },\n', str, mod)  
        else
            str = string.format('%s\t#ifdef VXTU_MODULE_%s\n\t\t{ "%s", _vxtu_module_%s_entry },\n\t#endif\n', str, string.upper(mod), mod, mod)
        end
    end
    return str .. "\t{ NULL, NULL }\n};\n"
end)())
