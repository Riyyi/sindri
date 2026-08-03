package tests

import "core:testing"

@(test)
foo :: proc(t: ^testing.T) {
    testing.expect(t, 1 + 1 == 2, "pass")
}
