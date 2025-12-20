import subprocess
from os import path
import os
import shutil
from glob import glob
import typing
import sys
import platform
import random

# TODO:
# - Make this file never show it's call stack. Call stacks should mean that a child script failed.
# - Add self-documenting build.ini or similar, as to not require anyone to look
#       at this file unless they want to add a new backend.
# - It could be nice to be able to generate into another folder, or just say --copy-into../../my_cool_folder

# @CONFIGURE: Must be key into below table
# Note that the backend files and examples may also have to be updated, if you use these.
git_heads = {
    "imgui": "v1.91.7-docking",
    "dear_bindings": "81c906b",
}

# Note - tested with Odin version `dev-2025-07`

# @CONFIGURE: Elements must be keys into below table
wanted_backends = ["vulkan", "sdl2", "opengl3", "sdlrenderer2", "glfw", "dx11", "dx12", "osx", "metal", "wgpu", "webgl"]
# Supported means that an impl bindings file exists, and that it has been tested.
# Some backends (like dx12, win32) have bindings but not been tested.
backends = {
    "allegro5":     { "supported": False },
    "android":      { "supported": False },
    "dx9":          { "supported": False, "enabled_on": ["windows"] },
    "dx10":         { "supported": False, "enabled_on": ["windows"] },
    "dx11":         { "supported": True,  "enabled_on": ["windows"] },
    # Bindings exist for DX12, but they are untested
    "dx12":         { "supported": False, "enabled_on": ["windows"] },
    "glfw":         { "supported": True,  "deps": ["glfw"] },
    "glut":         { "supported": False },
    "metal":        { "supported": True,  "enabled_on": ["darwin"] },
    "opengl2":      { "supported": False },
    "opengl3":      { "supported": True  },
    "osx":          { "supported": False, "enabled_on": ["darwin"] },
    "sdl2":         { "supported": True,  "deps": ["sdl2"] },
    "sdl3":         { "supported": False },
    "sdlrenderer2": { "supported": True,  "deps": ["sdl2"] },
    "sdlrenderer3": { "supported": False },
    "vulkan":       { "supported": True,  "defines": ["VK_NO_PROTOTYPES"], "deps": ["vulkan"] },
    "webgl":        { "supported": True,  "odin": True },
    "wgpu":         { "supported": True,  "odin": True },
    # Bindings exist for win32, but they are untested
    "win32":        { "supported": False, "enabled_on": ["windows"] },
}

# Indirection for backend dependencies, as some might have the same dependency, and their commits can't get out of sync.
backend_deps = {
    "sdl2":   { "repo": "https://github.com/libsdl-org/SDL.git",               "commit": "release-2.28.3", "path": "SDL2" },
    "glfw":   { "repo": "https://github.com/glfw/glfw.git",                    "commit": "3eaf125",        "path": "glfw" },
    "vulkan": { "repo": "https://github.com/KhronosGroup/Vulkan-Headers.git",  "commit": "4f51aac",        "path": "Vulkan-Headers" },
}

# @CONFIGURE:
compile_debug = False

# @CONFIGURE:
build_wasm = False

# @CONFIGURE:
build_imgui_internal = True

platform_win32_like = platform.system() == "Windows"
platform_unix_like = platform.system() == "Linux" or platform.system() == "Darwin"

# Assert which doesn't clutter the output
def assertx(cond: bool, msg: str):
    if not cond:
        print(msg)
        exit(1)

def hashes_are_same_ish(first: str, second: str) -> bool:
    smallest_hash_size = min(len(first), len(second))
    assertx(smallest_hash_size >= 7, "Hashes not long enough to be sure")
    return first[:smallest_hash_size] == second[:smallest_hash_size]

def exec(cmd: typing.List[str], what: str) -> str:
    max_what_len = 40
    if len(what) > max_what_len:
        what = what[:max_what_len - 2] + ".."
    print(what + (" " * (max_what_len - len(what))) + "> " + " ".join(cmd))
    try: return subprocess.check_output(cmd).decode('utf-8')
    except subprocess.CalledProcessError as uh_oh:
        print("=" * 80)
        print("FAILED")
        print("=" * 80)
        print(uh_oh.output.decode())
        exit(1)

def exec_vcvars(cmd: typing.List[str], what):
    max_what_len = 40
    if len(what) > max_what_len:
        what = what[:max_what_len - 2] + ".."
    print(what + (" " * (max_what_len - len(what))) + "> " + " ".join(cmd))
    assertx(subprocess.run(f"vcvarsall.bat x64 && {' '.join(cmd)}", shell=True).returncode == 0, f"Failed to run command '{cmd}'")

def copy(from_path: str, files: typing.List[str], to_path: str):
    for file in files:
        shutil.copy(path.join(from_path, file), to_path)

# glob copy backported for python 3.9
def glob_copy_39(root_dir: str, glob_pattern: str, dest_dir: str):
    real_pattern = os.path.join(root_dir, glob_pattern)
    the_files = glob(real_pattern)

    # strip root_dir
    results = []
    for item in the_files:
        results.append(item[len(root_dir)+1:])

    copy(root_dir, results, dest_dir)
    return results

def glob_copy(root_dir: str, glob_pattern: str, dest_dir: str):
    version_info = sys.version_info
    if version_info.major == 3 and version_info.minor == 9:
        return glob_copy_39(root_dir, glob_pattern, dest_dir)

    the_files = glob(root_dir=root_dir, pathname=glob_pattern)
    copy(root_dir, the_files, dest_dir)
    return the_files

def platform_select(the_options):
    """ Given a dict like eg. { "windows": "/DCOOL_DEFINE", "linux, darwin": "-DCOOL_DEFINE" }
    Returns the correct value for the active platform. """
    our_platform = platform.system().lower()
    for platforms_string in the_options:
        if platforms_string.lower().find(our_platform) != -1:
            return the_options[platforms_string]

    print(the_options)
    assertx(False, f"Couldn't find active platform ({our_platform}) in the above options!")

def pp(the_path: str) -> str:
    """ Get Platform Path. Given a path with '/' as a delimiter, returns an appropriate sys.platform path """
    return path.join(*the_path.split("/"))

def map_to_folder(files: typing.List[str], folder: str) -> typing.List[str]:
    return list(map(lambda file: path.join(folder, file), files))

def has_tool(tool: str) -> bool:
    try: subprocess.check_output([tool], stderr=subprocess.DEVNULL)
    except FileNotFoundError: return False
    except: return True
    else: return True

def ensure_checked_out_with_commit(dir: str, repo: str, wanted_commit: str):
    if not path.exists(dir):
        exec(["git", "clone", repo, dir], f"Cloning {dir}")

    exec(["git", "-C", dir, "fetch"], f"Fetching latest commits for {dir}")
    exec(["git", "-c", "advice.detachedHead=false", "-C", dir, "checkout", "--force", wanted_commit], f"Checking out {dir}")

def get_platform_imgui_lib_name(shared: bool = False, system=None, processor=None) -> str:
    """ Returns imgui binary name for system/processor """

    if system is None:
        system = platform.system()
    if processor is None:
        if platform.machine() in ["AMD64", "x86_64"]: processor = "x64"
        if platform.machine() in ["arm64"]:           processor = "arm64"

    binary_ext = ""
    if shared:
        if system == "Windows": binary_ext = "dll"
        elif system == "Darwin": binary_ext = "dylib"
        elif system == "Linux": binary_ext = "so"
        else: assertx(False, f"Shared libs not supported for {system}")
    else:
        binary_ext = "lib" if system == "Windows" else "a"

    assertx(system != "", "System could not be determined")
    assertx(processor != None, f"Unexpected processor: {processor}")

    return f'imgui_{system.lower()}_{processor}.{binary_ext}'

# TODO[TS]: This works, but there's a bug in Python, which makes cl.exe return with
# exit code 2 for no god damn reason at all, if not run with run_vcvars.
# If we're on windows, we can check for cl.exe, and re execute after calling vcvarsall, if available.
def did_re_execute() -> bool:
    if platform.system() != "Windows": return False
    if has_tool("cl"): return False
    if "-no_reexecute" in sys.argv: return False
    print("Re-executing with vcvarsall..")
    os.system("".join(["vcvarsall.bat x64 && ", sys.executable, " build.py -no_reexecute"]))
    return True

def compile(backend_deps_names: typing.Set[str], all_sources: typing.List[str], wasm: bool, target="", system=None, processor=None, sysroot=""):
    # Basic flags
    if wasm:
        compile_flags = ['-DIMGUI_IMPL_API=extern\"C\"', "-DIMGUI_DISABLE_DEFAULT_SHELL_FUNCTIONS", "-DIMGUI_DISABLE_FILE_FUNCTIONS", "--target=wasm32", "-mbulk-memory", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", "-nostdlib++", "-fno-use-cxa-atexit"]

        assertx(has_tool("odin"), "odin not found!")
        root = exec(["odin", "root"], "Get odin root")
        compile_flags += ["--sysroot=" + root + "vendor/libc"]
    else:
        compile_flags = ['-DIMGUI_IMPL_API=extern\"C\"', "-fPIC", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", "-std=c++11"]

    # Optimization flags
    if compile_debug: compile_flags += ["-g", "-O0"]
    else: compile_flags += ["-O3"]

    all_objects = []
    for file in all_sources:
        if file.endswith(".cpp"): all_objects.append(file.removesuffix(".cpp") + ".o")
        elif file.endswith(".mm"): all_objects.append(file.removesuffix(".mm") + ".o")

    os.chdir("temp")

    # Compile objects
    if target == "aarch64-macos-gnu":
        exec(["clang"] + compile_flags + ["-c"] + all_sources, "Compiling sources")
    else:
        target_flag = ["--target=" + target] if target else []
        exec(["zig", "cc"] + target_flag + compile_flags + ["-c"] + all_sources, "Compiling sources")

    os.chdir("..")

    dest_binary = get_platform_imgui_lib_name(shared=False, system=system, processor=processor)

    if wasm:
        shutil.rmtree(path="wasm", ignore_errors=True)
        os.mkdir("wasm")
        copy("temp", all_objects, "wasm")
    else:
        if target == "aarch64-macos-gnu":
            exec(["ar", "rcs", dest_binary] + map_to_folder(all_objects, "temp"), "Making library from objects")
        else:
            exec(["zig", "ar", "rcs", dest_binary] + map_to_folder(all_objects, "temp"), "Making library from objects")

def compile_shared(backend_deps_names: typing.Set[str], all_sources: typing.List[str], wasm: bool, target="", system=None, processor=None, sysroot=""):
    if wasm:
        print("Skipping shared build for WASM")
        return

    # Compile flags for shared
    compile_flags = ['-DIMGUI_IMPL_API=extern\"C\"', "-fPIC", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", "-std=c++11"]

    # Optimization flags
    if compile_debug: compile_flags += ["-g", "-O0"]
    else: compile_flags += ["-O3"]

    # For shared, only compile core ImGui sources
    all_sources = ["imgui_widgets.cpp", "imgui.cpp", "imgui_tables.cpp", "imgui_demo.cpp", "imgui_draw.cpp", "c_imgui.cpp"]
    if build_imgui_internal:
        all_sources.append("c_imgui_internal.cpp")

    all_objects = []
    for file in all_sources:
        if file.endswith(".cpp"): all_objects.append(file.removesuffix(".cpp") + ".o")
        elif file.endswith(".mm"): all_objects.append(file.removesuffix(".mm") + ".o")

    os.chdir("temp")

    # Compile objects
    if target == "aarch64-macos-gnu":
        exec(["clang"] + compile_flags + ["-c"] + all_sources, "Compiling sources for shared")
    else:
        target_flag = ["--target=" + target] if target else []
        exec(["zig", "cc"] + target_flag + compile_flags + ["-c"] + all_sources, "Compiling sources for shared")

    os.chdir("..")

    dest_binary = get_platform_imgui_lib_name(shared=True, system=system, processor=processor)

    # Create dylib dir for macOS shared
    if system == "Darwin":
        if not path.isdir("dylib"): os.mkdir("dylib")
        os.chdir("dylib")
        # dest_binary stays
        os.chdir("..")

    # Link to shared lib
    if target == "aarch64-macos-gnu":
        exec(["clang"] + ["-shared"] + ["-o", dest_binary] + map_to_folder(all_objects, "temp"), "Making shared library")
    else:
        target_flag = ["--target=" + target] if target else []
        exec(["zig", "cc"] + target_flag + ["-shared"] + ["-o", dest_binary] + map_to_folder(all_objects, "temp"), "Making shared library")

def main():
    assertx(path.isfile("build.py"), "You have to run the script from within the repository for now!")

    if did_re_execute(): return

    # Check that CLI tools are available
    assertx(has_tool("git"), "Git not available!")

    if platform.system() == "Windows":
        pass
        # Fun times! We can't check for this, for the reasons described above did_re_execute()
        # assertx(has_tool("cl") and has_tool("lib"), "cl.exe or lib.exe not in path - did you run vcvarsall.bat?")
    else:
        assertx(has_tool("clang"), "clang not found!")
        assertx(has_tool("ar"), "ar not found!")

    # Check out bindings generator tools
    ensure_checked_out_with_commit("imgui", "https://github.com/ocornut/imgui.git", git_heads["imgui"])
    ensure_checked_out_with_commit("dear_bindings", "https://github.com/dearimgui/dear_bindings.git", git_heads["dear_bindings"])

    # Check out backend dependencies
    if not path.isdir("backend_deps"): os.mkdir("backend_deps")
    backend_deps_names = set()
    for backend_name in wanted_backends:
        backend = backends[backend_name]

        for dep in backend.get("deps", []):
            backend_deps_names.add(dep)

    for backend_dep in backend_deps_names:
        full_dep = backend_deps[backend_dep]
        ensure_checked_out_with_commit(path.join("backend_deps", full_dep["path"]), full_dep["repo"], full_dep["commit"])

    # Clear the temp folder
    shutil.rmtree(path="temp", ignore_errors=True)
    os.mkdir("temp")

    # Generate Odin bindings
    exec([sys.executable, pp("dear_bindings/dear_bindings.py"), "-o", pp("temp/c_imgui"), "--nogeneratedefaultargfunctions", "--imconfig-path", pp("imconfig.h"), pp("imgui/imgui.h")], "Running dear_bindings: ImGui")
    if build_imgui_internal:
        exec([sys.executable, pp("dear_bindings/dear_bindings.py"), "-o", pp("temp/c_imgui_internal"), "--include", pp("imgui/imgui.h"), "--nogeneratedefaultargfunctions", "--imconfig-path", pp("imconfig.h"), pp("imgui/imgui_internal.h")], "Running dear_bindings: ImGui Internal")

    # Generate odin bindings from dear_bindings json file
    if build_imgui_internal:
        exec([sys.executable, pp("gen_odin.py"), "--imgui", pp("temp/c_imgui.json"), "--imconfig", pp("temp/c_imgui_imconfig.json"), "--imgui_internal", pp("temp/c_imgui_internal.json")], "Running odin-imgui")
    else:
        exec([sys.executable, pp("gen_odin.py"), "--imgui", pp("temp/c_imgui.json"), "--imconfig", pp("temp/c_imgui_imconfig.json")], "Running odin-imgui")

    # Find and copy imgui sources to temp folder
    _imgui_headers = glob_copy("imgui", "*.h", "temp")
    imgui_sources = glob_copy("imgui", "*.cpp", "temp")

    # We copied `imconfig.h` from imgui, but we have our own. Overwrite the previous one.
    shutil.copy(pp("imconfig.h"), pp("temp/imconfig.h"))

    # Write file describing the build configuration.
    f = open("enabled.odin", "w+")
    f.writelines([
        "package imgui\n",
        "\n",
        "// This is a generated helper file which you can use to know about the build configuration.\n",
        "\n",
    ])

    f.writelines([f"DEBUG_ENABLED :: {'true' if compile_debug else 'false'}", "\n"])
    f.writelines([f"WASM_ENABLED :: {'true' if build_wasm else 'false'}", "\n", "\n"])

    for backend_name in backends:
        f.writelines([f"BACKEND_{backend_name.upper()}_ENABLED :: {'true' if backend_name in wanted_backends else 'false'}\n"])

    if build_wasm:
        # Gather sources for WASM
        all_sources = imgui_sources + ["c_imgui.cpp"]
        if build_imgui_internal:
            all_sources.append("c_imgui_internal.cpp")
        compile(backend_deps_names, all_sources, True, "", None, None, "")



    targets = ["aarch64-macos-gnu", "x86_64-linux-gnu"]
    for target in targets:
        if "macos" in target:
            sys_name = "Darwin"
        elif "linux" in target:
            sys_name = "Linux"
        elif "windows" in target:
            sys_name = "Windows"
        proc_name = "arm64" if "aarch64" in target else "x64"
        print(f"Building for {target}")
        # Gather sources for this target
        all_sources = ["imgui_widgets.cpp", "imgui.cpp", "imgui_tables.cpp", "imgui_demo.cpp", "imgui_draw.cpp", "c_imgui.cpp"]
        if build_imgui_internal:
            all_sources.append("c_imgui_internal.cpp")
        compile(backend_deps_names, all_sources, False, target, sys_name, proc_name)
        if target in ["aarch64-macos-gnu", "x86_64-linux-gnu"]:
            compile_shared(backend_deps_names, all_sources, False, target, sys_name, proc_name)

    print("Build completed for all platforms!")

    print("Looks like everything went ok!")
    if random.random() < 0.01: print("But looks may deceive..")

if __name__ == "__main__":
    main()
