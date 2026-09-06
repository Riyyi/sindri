package core

// -----------------------------------------

Settings :: struct {
	width:   u16,
	height:  u16,
	title:   string,
	mode:    WindowMode,
	refresh: u16,
	vsync:   bool,
	// TODO:
	// windowed resizable y/n
	// exit key (ex: escape)
}

WindowMode :: enum u8 {
	Windowed   = 0,
	Borderless = 1,
	Fullscreen = 2,
}
