package libs

import "core:fmt"
import "core:log"
import "core:os/os2"
import "core:path/filepath"

getSokolShdcPath :: proc() -> string {
	// Get the root directory (two levels up from libs/)
	file_dir := filepath.dir(#file)
	libs_dir := filepath.dir(file_dir)
	root_dir := filepath.dir(libs_dir)

	base_path := filepath.join({root_dir, "tools", "sokol"})
	platform_path: string

	when ODIN_OS == .Darwin {
		when ODIN_ARCH == .arm64 {
			platform_path = "osx_arm64/sokol-shdc"
		} else when ODIN_ARCH == .amd64 {
			platform_path = "osx/sokol-shdc"
		} else {
			panic("Unsupported architecture")
		}
	} else when ODIN_OS == .Linux {
		when ODIN_ARCH == .arm64 {
			platform_path = "linux_arm64/sokol-shdc"
		} else {
			platform_path = "linux/sokol-shdc"
		}
	} else when ODIN_OS == .Windows {
		platform_path = "win32/sokol-shdc.exe"
	} else {
		panic("Unsupported platform")
	}

	return filepath.join({base_path, platform_path})
}

buildShader :: proc(
	inputPath: string,
	outputPath: string,
	format := "sokol_odin",
	slang := "glsl430:hlsl5:metal_macos:wgsl",
	defines := []string{},
) -> bool {
	shdcPath := getSokolShdcPath()
	if !os2.exists(shdcPath) {
		fmt.eprintf("sokol-shdc not found at: %s\n", shdcPath)
		return false
	}

	command := make([dynamic]string, 0, len(defines) + 8)
	append(&command, shdcPath)
	append(&command, "-i", inputPath)
	append(&command, "-o", outputPath)
	append(&command, "--slang", slang)
	append(&command, "-f", format)
	for define in defines {
		append(&command, "-d", define)
	}

	desc := os2.Process_Desc {
		command = command[:],
	}
	state, stdout, stderr, err := os2.process_exec(desc, context.allocator)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil {
		fmt.eprintf("Failed to execute sokol-shdc: %v\n", err)
		return false
	}


	if state.success {
		log.info("Shader built successfully: %s -> %s", inputPath, outputPath)
		return true
	} else {
		fmt.eprintf("Failed to build shader (exit code %d)\n", state.exit_code)
		return false
	}
}
