#+feature dynamic-literals
package root

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:os"
import "core:os/os2"
import "core:time"
import "libs"

logger: log.Logger
arena: virtual.Arena
buildCmd: [dynamic]string = {
	"odin",
	"build",
	"./src",
	"-strict-style",
	"-vet",
	"-warnings-as-errors",
	"-debug",
	"-vet-cast",
	"-vet-style",
	"-out:./build/app",
}
loadOls :: proc() {
	data, ok := os.read_entire_file_from_filename("./ols.json")
	if !ok {
		log.error("Failed to load ols.json")
		return
	}
	defer delete(data)

	jsonData, err := json.parse(data)
	if err != .None {
		log.error("Failed to parse old.json")
		fmt.eprintln(err)
		return
	}
	defer json.destroy_value(jsonData)
	ols := jsonData.(json.Object)
	collectionsJson := ols["collections"].(json.Array)
	for i, idx in collectionsJson {
		collectionItem := i.(json.Object)
		append(
			&buildCmd,
			fmt.aprintf(
				"-collection:%s=%s",
				collectionItem["name"].(json.String),
				collectionItem["path"].(json.String),
			),
		)
	}
}

build :: proc() {
	state, stdout, stderr, err := os2.process_exec({command = buildCmd[:]}, context.allocator)
	defer {
		delete(stdout)
		delete(stderr)
	}

	if err == nil && state.exit_code == 0 {
		log.info("Build succeeded")
	} else {
		if len(stderr) > 0 {
			fmt.eprintf("%s", string(stderr))
		}
		if len(stdout) > 0 {
			fmt.eprintf("%s", string(stdout))
		}
		log.errorf("Build failed (exit code: %d)", state.exit_code)
	}
}
main :: proc() {
	arena_err := virtual.arena_init_growing(&arena)
	assert(arena_err == nil)
	arena_alloc := virtual.arena_allocator(&arena)
	context.allocator = arena_alloc

	logger = log.create_console_logger()
	context.logger = logger

	loadOls()
	when #config(watch, false) {
		lastCheck := time.now()
		log.info("Watching for changes")
		for {
			defer free_all(context.temp_allocator)

			if libs.watchDirectory("./src", &lastCheck, {".odin"}, context.temp_allocator) {
				log.info("Rebuilding...")
				build()
			}
			time.sleep(500 * time.Millisecond)
		}
		return
	}

	build()
}
