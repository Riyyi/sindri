# Odin

This document contains specifics about the workings of the Odin programming
language, dynamic linking and state management design patterns. These are
tested and validated findings, for continued reference by me.

## Dynamic Library Memory

When a program loads in a dynamic library, what happens with package globals?

Findings (macOS):
- The package globals are shared between the host and the lib
- After hot reloading the lib, the memory of the packge is not refreshed,
  it keeps pointing to the package global of the host

The clanker states this is due to "flat-namespace symbol interposition".

Linux "ELF has symbol preemption: when resolving references, ld.so searches
globals scope in order — executable first, then loaded shared objects".

Windows PE has no interposition at all, every module (exe and each DLL) has its
own symbol table.
