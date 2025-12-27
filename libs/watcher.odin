package libs
import "base:runtime"
import "core:log"
import "core:os/os2"
import "core:strings"
import "core:time"


watchDirectory :: proc(
	dir: string,
	lastCheck: ^time.Time,
	extensions: []string,
	ignore: []string = {},
	allocator: runtime.Allocator = context.temp_allocator,
) -> bool {
	handle, err := os2.open(dir)
	if err != nil do return false
	defer os2.close(handle)

	files, _ := os2.read_dir(handle, -1, allocator)
	defer delete(files)

	changed := false
	mostRecentChange := lastCheck^

	for fi in files {
		if fi.type == .Directory {
			// Skip ignored directories
			shouldIgnore := false
			for pattern in ignore {
				if strings.has_suffix(fi.name, pattern) {
					shouldIgnore = true
					break
				}
			}
			if shouldIgnore do continue
			if watchDirectory(fi.fullpath, lastCheck, extensions, ignore, allocator) {
				changed = true
				if time.diff(mostRecentChange, lastCheck^) > 0 {
					mostRecentChange = lastCheck^
				}
			}
		} else {
			ext := strings.to_lower(getExtension(fi.name), allocator)
			if !hasExtension(ext, extensions) do continue

			if time.diff(lastCheck^, fi.modification_time) > 0 {
				changed = true
				log.infof("File changed: %s", fi.fullpath)
				if time.diff(mostRecentChange, fi.modification_time) > 0 {
					mostRecentChange = fi.modification_time
				}
			}
		}
	}

	if time.diff(lastCheck^, mostRecentChange) > 0 {
		lastCheck^ = mostRecentChange
	}

	return changed
}
getExtension :: proc(filename: string) -> string {
	for i := len(filename) - 1; i >= 0; i -= 1 {
		if filename[i] == '.' {
			return filename[i:]
		}
	}
	return ""
}

hasExtension :: proc(ext: string, extensions: []string) -> bool {
	for e in extensions {
		if ext == e do return true
	}
	return false
}
