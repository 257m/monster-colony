#+build !js
package main

import "core:os"

// Desktop file I/O for the save system (see save.odin). Kept in its own
// platform-gated file because `core:os` is unavailable on the web target.

save_supported :: proc() -> bool {
	return true
}

save_write_file :: proc(path: string, data: []u8) -> bool {
	return os.write_entire_file(path, data) == nil
}

save_read_file :: proc(path: string) -> (data: []u8, ok: bool) {
	d, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return nil, false
	}
	return d, true
}
