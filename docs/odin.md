# Odin

This document contains specifics about the workings of the Odin programming
language, dynamic linking and state management design patterns. These are
tested and validated findings, for continued reference by me.

## Compiler

Odin's compiler is demand-driver: a procedure's body is only semantically
analyzed when the proc is actually referenced. They are syntactically checked
always.

## Dynamic Library Memory

When a program loads in a dynamic library, what happens with package globals?

Findings (macOS):
- Package globals are shared between modules, but only indirectly
  - This is due to the dynamic linker merging symbols into a (single) flat namespace
  - Practically this means the lib's unset package globals get shadowed by the hosts'
- After hot reloading the lib, the memory of the packge is not refreshed,
  it keeps pointing to the package global of the host

Findings (Windows):
- Package globals are not shared between modules, they have their own copy

Findings (Linux):
- Package globals are not shared between modules, they have their own copy

Conclusion: avoid package globals, or pass pointers to the dynamic library so
it can match its package globals with the host module.

## Dependency Patterns

1. Strict layering, only call downwards. If two modules need each other, one of
   the modules is in a wrong layer. Move it, or extract the shared part into a
   lower layer.
2. Dependency inversion: if required, define an interface in the lower layer,
   upper layer registers itself.
3. Dependency Injection: Prevent dependencies via data, over includes. Pass what
   a function needs as arguments instead of reaching another module's state.
4. Events instead of callbacks both ways If A and B would call each other,
   have A push events into a queue and B consume them. Neither module includes
   the other; they only share the event type (which lives in a lower layer).
5. Merge or split as a last resort, if two modules genuinely can't be untangled.

Sindri Engine:

```
+---------------------+                                       Game:
|        Game         |                                       - Game
+---------------------+
          |
          v
+---------------------+          +---------------------+      Core:
|        Core         |<----+----|        main         |      - Input
+---------------------+     |    +---------------------+
          |                 |
          v                 |
+---------------------+     |                                 Platform:
|      Platform       |<----+                                 - GLFW
+---------------------+     |                                 - wgpu
          |                 |
          v                 |
+---------------------+     |                                 Base:
|        Base         |<----+                                 - Hot Reload
+---------------------+                                       - Settings
                                                              - Event
                                                              - Keycodes
```

## Logging strategy

From the docs:

> While it is ok for simple apps to use the core:fmt package, libraries and
> complex apps should prefer the core:log package. By using the implicit logger
> library and application authors allow the caller to decide how to process log
> messages.

## Naming Conventions

From core.odin:

> In general, Ada_Case for types and snake_case for values
>
> - Package Name:       snake_case (but prefer single word)
> - Import Name:        snake_case (but prefer single word)
> - Types:              Ada_Case
> - Enum Values:        Ada_Case
> - Procedures:         snake_case
> - Local Variables:    snake_case
> - Constant Variables: SCREAMING_SNAKE_CASE
