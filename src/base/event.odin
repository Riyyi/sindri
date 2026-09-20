package base

import "base:intrinsics"
import "base:runtime"
import "core:fmt"

// -----------------------------------------
// Types

// event category, bitfield (?)

Event_Data :: union {
	Window_Close_Event,
	Window_Resize_Event,
	Joystick_Connect_Event,
	Joystick_Disconnect_Event,
	Key_Press_Event,
	Key_Release_Event,
	Key_Repeat_Event,
	Mouse_Button_Press_Event,
	Mouse_Button_Release_Event,
	Mouse_Position_Event,
	Mouse_Scroll_Event,
}

Event :: struct {
	data:    Event_Data,
	handled: bool,
}

Window_Close_Event :: struct {}

Window_Resize_Event :: struct {
	width:  i32,
	height: i32,
}

Key_Press_Event :: struct {
	key:  Key,
	mods: Mod_Set,
}

Key_Release_Event :: struct {
	key:  Key,
	mods: Mod_Set,
}

Key_Repeat_Event :: struct {
	key:  Key,
	mods: Mod_Set,
}

Mouse_Button_Press_Event :: struct {
	button: Mouse_Button,
	mods:   Mod_Set,
}

Mouse_Button_Release_Event :: struct {
	button: Mouse_Button,
	mods:   Mod_Set,
}

Mouse_Position_Event :: struct {
	x_pos: f32,
	y_pos: f32,
}

Mouse_Scroll_Event :: struct {
	x_offset: f32,
	y_offset: f32,
}

Joystick_Connect_Event :: struct {
	id: i32,
}

Joystick_Disconnect_Event :: struct {
	id: i32,
}

// Message Receiver
@(private)
Listener :: struct {
	callback: proc(event: ^Event_Data, user_ptr: rawptr) -> bool, // return true = don't propagate
	user_ptr: rawptr,
	// TODO: test if hot_reload keeps the same function pointers and the listeners remain working.
	//       if they dont add a flag "engine_listener: bool", which engine calls should set true,
	//       then clear all game listeners
}

// Transfers messages between Sender and Receiver
Event_Bus :: struct {
	queue:     [dynamic]Event,
	listeners: map[typeid][dynamic]Listener,
	allocator: runtime.Allocator,
}

// -----------------------------------------
// Variables

event_bus: Event_Bus

// -----------------------------------------
// Constructor/destructor

event_bus_init :: proc(allocator := context.allocator) {
	// make() doesnt allocate until there's capacity, so set it > 0
	queue := make([dynamic]Event, 0, 4, allocator)
	listeners := make(map[typeid][dynamic]Listener, 4, allocator)
	event_bus = {
		queue     = queue,
		listeners = listeners,
		allocator = allocator,
	}
}

event_bus_destroy :: proc() {
	assert(event_bus.queue != nil)
	assert(event_bus.listeners != nil)

	for _, ls in event_bus.listeners do delete(ls)

	delete(event_bus.queue)
	delete(event_bus.listeners)

	event_bus.queue = nil
	event_bus.listeners = nil
}

// -----------------------------------------
// Public functions

event_subscribe :: proc(
	$T: typeid,
	callback: proc(event: ^T, user_ptr: rawptr) -> bool,
	user_ptr: rawptr = nil,
) where intrinsics.type_is_variant_of(Event_Data, T) {
	cb := cast(proc(_: ^Event_Data, _: rawptr) -> bool)callback // upcast
	event_subscribe_raw(T, cb, user_ptr)
}

event_unsubscribe :: proc(
	$T: typeid,
	callback: proc(event: ^T, user_ptr: rawptr) -> bool,
	user_ptr: rawptr = nil,
) where intrinsics.type_is_variant_of(Event_Data, T) {
	cb := cast(proc(_: ^Event_Data, _: rawptr) -> bool)callback // upcast
	event_unsubscribe_raw(T, cb, user_ptr)
}

on_event :: proc(data: Event_Data) {
	assert(event_bus.queue != nil)

	append(&event_bus.queue, Event{data = data})
}

// Drain all the events that have been queued up, in enqueue order
drain_event_queue :: proc() {
	assert(event_bus.queue != nil)

	fmt.println("toby!")

	for &event in event_bus.queue {

		#partial switch e in event.data {
			case Window_Close_Event:
				event_dispatch(Window_Close_Event, &event)
				fmt.println("Close")
			case Window_Resize_Event:
				event_dispatch(Window_Resize_Event, &event)
				fmt.println("Resize:", e.width, e.height)

			case Key_Press_Event:
				event_dispatch(Key_Press_Event, &event)
				fmt.println("Key press", e.key, e.mods)
			case Key_Release_Event:
				event_dispatch(Key_Release_Event, &event)
				fmt.println("Key release", e.key, e.mods)
			case Key_Repeat_Event:
				event_dispatch(Key_Repeat_Event, &event)
				fmt.println("Key repeat", e.key, e.mods)

			case Mouse_Button_Press_Event:
				event_dispatch(Mouse_Button_Press_Event, &event)
				fmt.println("Mouse press", e.button, e.mods)
			case Mouse_Button_Release_Event:
				event_dispatch(Mouse_Button_Release_Event, &event)
				fmt.println("Mouse release", e.button, e.mods)
			case Mouse_Position_Event:
				event_dispatch(Mouse_Position_Event, &event)
				fmt.printfln("Mouse pos: {}x{}", e.x_pos, e.y_pos)
			case Mouse_Scroll_Event:
				event_dispatch(Mouse_Scroll_Event, &event)
				fmt.printfln("Mouse scroll: {}x{}", e.x_offset, e.y_offset)

			case Joystick_Connect_Event:
				event_dispatch(Joystick_Connect_Event, &event)
				fmt.println("Joy con:", e.id)
			case Joystick_Disconnect_Event:
				event_dispatch(Joystick_Disconnect_Event, &event)
				fmt.println("Joy dis:", e.id)

			case:
				panic("[event] unimplemented event")
		}
	}

	clear(&event_bus.queue)
}

// Dispatch to the listeners registered for T, in reverse subscription order.
// First listener to return true claims the event and stops propagation
event_dispatch :: proc(
	$T: typeid,
	event: ^Event,
) -> bool where intrinsics.type_is_variant_of(Event_Data, T) {
	assert(event_bus.listeners != nil)

	ls, ok := event_bus.listeners[T]
	if !ok do return false

	#reverse for &l in ls {
		callback := cast(proc(_: ^T, _: rawptr) -> bool)l.callback // downcast
		if callback(&event.data.(T), l.user_ptr) {
			event.handled = true
			return true
		}
	}

	return false
}

// -----------------------------------------
// Private functions

@(private)
event_subscribe_raw :: proc(
	$T: typeid,
	callback: proc(event: ^Event_Data, user_ptr: rawptr) -> bool,
	user_ptr: rawptr = nil,
) where intrinsics.type_is_variant_of(Event_Data, T) {
	assert(event_bus.listeners != nil)

	if _, ok := event_bus.listeners[T]; !ok {
		event_bus.listeners[T] = make([dynamic]Listener, event_bus.allocator)
	}

	append(&event_bus.listeners[T], Listener{callback, user_ptr})
}

@(private)
event_unsubscribe_raw :: proc(
	$T: typeid,
	callback: proc(event: ^Event_Data, user_ptr: rawptr) -> bool,
	user_ptr: rawptr = nil,
) where intrinsics.type_is_variant_of(Event_Data, T) {
	assert(event_bus.listeners != nil)

	ls, ok := event_bus.listeners[T]
	if !ok do return

	for l, i in ls {
		if l.callback == callback && l.user_ptr == user_ptr {
			ordered_remove(&event_bus.listeners[T], i) // preserve subscription order
			return
		}
	}
}
