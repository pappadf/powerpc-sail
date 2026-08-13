# Contributing

Thanks for your interest.  The 601 is a strange machine — a POWER/PowerPC
hybrid with instructions no later chip kept and a manual that contradicts
itself in places — and contributions that make this specification more
faithful to the silicon are very welcome.

## Building and testing

Needs the `sail` compiler (developed against 0.20.2 — the relocatable binary
release from the [Sail repository](https://github.com/rems-project/sail/releases)
works without an OCaml toolchain), `z3`, a C compiler, `libgmp-dev` and
`zlib`.  The test programs also need a PowerPC cross toolchain
(`apt install gcc-powerpc-linux-gnu` on Debian/Ubuntu).

```sh
make check         # typecheck + assembly-clause coverage
make test          # 53 assembly programs against their expected final state
make test-disasm   # the same programs with tracing, exercising the disassembler
```

A change is only done when `make check` and `make test` both pass from a clean
tree.  CI additionally requires the model to typecheck with **zero warnings**,
not merely zero errors.

If you change behaviour deliberately, update the affected `test/*.expected`
files by reading the diff `make test` prints and concluding the new output is
correct — then `make test-accept` rewrites them.  Do not run `test-accept`
before reading the diff; it will happily bless a regression.

## Ground rules for the specification itself

1. **The MPC601 User's Manual is the source of truth.**  Every semantic
   statement in `model/` carries a citation — section, table, figure, or the
   chapter-10 instruction page.  Do not base changes on the behaviour of other
   emulators or toolchains: that would defeat the point of an *independent*
   transcription, which is to be able to validate, and be validated by, other
   implementations.
2. **Ambiguities are documented, not smoothed over.**  The 601 manual states
   several things twice and differently.  Where it does, say so in the source,
   argue which statement governs, and why — the existing notes on FI after a
   disabled exponent overflow, and on what an invalid `fctiw` delivers, are the
   pattern to follow.
3. **Deliberate divergences are marked.**  If the model knowingly does
   something the manual does not describe, it gets a `TODO` and a place in the
   README's *Known divergences* list.  A `TODO` should describe the work in
   full on its own terms — it must not point at a document that is not in this
   repository.
4. **Core-specific behaviour goes behind the core interface.**  Anything true
   of the 601 but not of PowerPC generally belongs in `model/cores/p601/`, via
   the hooks in `model/ppc_core_iface.sail`.  The 601 has plenty: the POWER
   holdover instructions, the RTC, unified BATs, I/O controller interface
   segments, HID-based debug.

## Tests

Test programs live in `test/` as `<name>.S` with a matching
`<name>.expected`.  Two conventions matter:

- **Derive the expected values from the manual, in the header, before the
  code.**  Every existing test does this — see [`test/fpmadd.S`](test/fpmadd.S),
  which works out an exact product by hand to show that the multiply-add does
  not round in the middle, or [`test/pagetable.S`](test/pagetable.S), which
  derives both PTEG addresses from the hash.  An expected file that is only a
  snapshot of current behaviour cannot catch the model being wrong.
- **Use `HALT(status)` from [`test/testlib.h`](test/testlib.h)** to end the
  program.  Output is captured from the `[halt]` or `[checkstop]` line onwards,
  so the banner and instruction trace never leak into expected files.

## What contributions are most valuable

1. **Measurements from real 601 silicon.**  This model has never been run
   against hardware.  Anything with a 601 in it — a Power Macintosh 6100/7100/
   8100, a PowerPC RS/6000, an IBM or Bull machine of the era — could settle
   questions the manual leaves open.  The open ones are marked `TODO-VERIFY`
   in the source; the current one is whether `mtmsr` suppresses the trace
   exception the way `sc` and `rfi` do, which §5.4.12.2 neither states nor
   denies.
2. **Closing the known divergences** listed in the README — the invalid-form
   policy is the largest and touches many instructions; the SPR undefined-bit
   masks are small, self-contained, and each directly observable through
   `mfspr`, so each can carry a test.
3. **More test programs**, especially around the exception model, the MMU
   corners, and floating-point rounding and exception delivery.
4. **A second core.**  The 603 and 604 are why `model/ppc_core_iface.sail`
   exists.  Several places in the model note what has to move behind that
   interface when one lands.
5. **Prover-backend output.**  This is ordinary Sail, so Lem/Coq/Lean
   generation and SMT properties are natural extensions.  Note that the
   floating-point implementation is deliberately pure Sail with no C glue, so
   it works on those backends too.

## Style

- Comments explain *why*, and cite the manual for *what*.
- **Names come from the manual too.**  Operands are spelled as the manual
  spells them (`rA`, `frB`, `crfD`, `SIMM`), 32 bits is a `word`, an
  instruction *completes*, and an access is a *memory* access.  If you need a
  word the manual does not use, prefer a plain descriptive one over a term
  borrowed from another architecture's specification.
- Section headers in the model are `/* --- Name ------ */` padded to a
  consistent width.
- An [`.editorconfig`](.editorconfig) is provided: UTF-8, LF, two-space indent
  in `.sail` files, no trailing whitespace.
