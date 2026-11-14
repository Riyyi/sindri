// Large Array of Things
// - Fixed size arrays and handles
// - ZII (Zero Is Initialization) and NIL over null
// - Intrusive lists and trees
// - Fat structs (SoA, AoS, byte soup)

package core

import "sindri:base"

THING_NIL :: 0
THINGS_MAX :: 1024

// -----------------------------------------
// Types

Thing_Idx :: u16

Thing_Ref :: struct {
	// TODO: 22 bits index, 10 bits generation, so we can store it in one 32bit number
	idx: Thing_Idx,
	gen: u16,
}

Thing_Kind :: enum {
	Camera,
	Player,
}

// Fixed size fat struct
Thing :: struct {
	kind:  Thing_Kind,
	pos:   base.Vec3,
	rot:   base.Vec3,
	scale: base.Vec3,

	// TODO: intrusive list
	// parent: Thing_Ref
	// first_kid: Thing_Ref
	// prev_sib: Thing_Ref
	// next_sib: Thing_Ref
}

Things :: struct {
	things:      [THINGS_MAX]Thing,
	// TODO: Collapse used and gen into 1 array
	used:        [THINGS_MAX]bool,
	gen:         [THINGS_MAX]u16,
	free_list:   [THINGS_MAX]Thing_Idx,
	next_free:   Thing_Idx, // first free'd slot
	next_unused: Thing_Idx, // never previously used slot
}

// -----------------------------------------
// Public functions

add :: proc(t: ^Things) -> Thing_Ref {
	slot: Thing_Idx
	gen: u16

	// Two-tiered searching of slots:
	// - first search the free-list, that contains freed up slots
	// - fallback to the index that has never been allocated before
	if t.next_free != THING_NIL {
		slot = t.next_free
		t.next_free = t.free_list[t.next_free]
		t.free_list[slot] = THING_NIL // clean up the pop'ed free-slot
	} else if (t.next_unused < THINGS_MAX) {
		if t.next_unused == THING_NIL do t.next_unused = 1 // first ever add()
		slot = t.next_unused
		t.next_unused += 1
	}

	if slot != THING_NIL {
		t.things[slot] = {} // reset data
		t.used[slot] = true
		t.gen[slot] += 1
		gen = t.gen[slot]
	}

	return {idx = slot, gen = gen}
}

rem :: proc(t: ^Things, ref: Thing_Ref) {
	idx := deref(t, ref)
	if idx == THING_NIL do return

	t.used[idx] = false
	t.free_list[idx] = t.next_free
	t.next_free = idx
}

get :: proc(t: ^Things, ref: Thing_Ref) -> ^Thing {
	return &t.things[deref(t, ref)]
}

deref :: proc(t: ^Things, ref: Thing_Ref) -> Thing_Idx {
	if ref.idx > THING_NIL &&
	   ref.idx < THINGS_MAX &&
	   t.used[ref.idx] &&
	   ref.gen == t.gen[ref.idx] {
		return ref.idx
	}

	return THING_NIL
}
