package tools

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:thread"
import "core:time"

HotReloadData :: struct {
	version:     i32,
	frame:       i32,
	ctx:         runtime.Context,
	persistent:  mem.Allocator,
	reloadLocal: mem.Allocator,
}

HotSetupProc   :: proc(data: ^HotReloadData) -> i32
HotFrameProc   :: proc(data: ^HotReloadData) -> i32
HotShutdownProc:: proc(data: ^HotReloadData)

Error :: enum {
	None,
	ArenaAllocFail,
	WatcherSetupFail,
	ThreadStartFail,
	DllReadFail,
	DllWriteFail,
	DllLoadFail,
	SymbolNotFound,
	TickFail,
}

Result :: struct {
	ok:  bool,
	err: Error,
}

HotReloadOptions :: struct {
	dllPath:       string,
	persistentSize: uint,
	reloadSize:     uint,
	scratchSize:    uint,
}

ReloadEvent :: enum {
	Loaded,
	Reloaded,
	Failed,
}

ReloadCallback :: proc(event: ReloadEvent)

HotReloadManager :: struct {
	library:         dynlib.Library,
	setupProc:       HotSetupProc,
	updateProc:       HotFrameProc,
	shutdownProc:    HotShutdownProc,
	hasError:       bool,
	initialized:     bool,
	err:             Error,
}

setup :: proc() -> Result {
	return {true, Error.None}
}


reload :: proc() -> Result {
	return {true, Error.None}
}


frame :: proc() -> Result {
	return {ok = false, err = .TickFail}
}

shutdown :: proc() {
}
