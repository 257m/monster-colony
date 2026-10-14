#+build js
package main

// Browser build: there is no persistent filesystem, so saving is disabled. The
// panel shows "not available in the browser build".

save_supported :: proc() -> bool {
	return false
}

save_write_file :: proc(path: string, data: []u8) -> bool {
	return false
}

save_read_file :: proc(path: string) -> (data: []u8, ok: bool) {
	return nil, false
}
