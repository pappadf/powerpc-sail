# Contributing

Thanks for your interest.  This is a specification of five 32-bit PowerPC
parts — the 601, 603, 604, 604e and 750 — and contributions that make it more
faithful to the silicon are very welcome.  The 601 is the strange one: a
POWER/PowerPC hybrid with instructions no later chip kept and a manual that
contradicts itself in places.  The other four are closer to one another than
any of them is to it, which is why they share `model/cores/common/`.

## Building and testing

Needs the `sail` compiler (developed against 0.20.2 — the relocatable binary
release from the [Sail repository](https://github.com/rems-project/sail/releases)
works without an OCaml toolchain), `z3`, a C compiler, `libgmp-dev` and
`zlib`.  The test programs also need a PowerPC cross toolchain
(`apt install gcc-powerpc-linux-gnu` on Debian/Ubuntu).

```sh
make check         # typecheck + assembly-clause coverage
make test          # the programs this core's manifest lists, against their
                   # expected final state
make test-disasm   # the same programs with tracing, exercising the disassembler
make harness-test  # the single-step harness protocol
```

Each takes `CORE=`, one of `p601` (the default), `p603`, `p604`, `p604e` and
`p750`.  **A change is only done when `make check`, `make test` and
`make harness-test` pass for EVERY core**, not only the one you were working
on — the common model is shared, and CI runs the whole matrix:

```sh
for c in p601 p603 p604 p604e p750; do make check CORE=$c && make test CORE=$c; done
```

CI additionally requires the model to typecheck with **zero warnings**, not
merely zero errors.

If you change behaviour deliberately, update the affected expected files by
reading the diff `make test` prints and concluding the new output is correct —
then `make test-accept CORE=<core>` rewrites them.  Do not run `test-accept`
before reading the diff; it will happily bless a regression.  The 601's
expected files sit beside the programs in `test/`; every later core keeps its
own in `test/<core>/`, and `test/<core>.tests` says which programs apply to it
and why the rest do not.

## Ground rules for the specification itself

1. **The user's manuals are the source of truth.**  MPC601UM, MPC603EUM,
   MPC604UM, MPC604EUM and MPC750UM for the five cores, and MPCFPE32B (the
   Programming Environments Manual) for the architecture the four later ones
   share.  Every semantic statement in `model/` carries a citation — section,
   table, figure, or the instruction page.  Do not base changes on the
   behaviour of other emulators or toolchains: that would defeat the point of
   an *independent* transcription, which is to be able to validate, and be
   validated by, other implementations.
2. **Ambiguities are documented, not smoothed over.**  Every one of these
   manuals states something twice and differently.  Where one does, say so in
   the source, argue which statement governs, and why — the existing notes on
   FI after a disabled exponent overflow, on what an invalid `fctiw` delivers,
   on the 603's two different PVR values and on whether the 604 executes the
   instruction its breakpoint matched are the pattern to follow.
3. **Deliberate divergences are marked.**  If the model knowingly does
   something the manual does not describe, it gets a `TODO` and a place in the
   README's *Known divergences* list.  A `TODO` should describe the work in
   full on its own terms — it must not point at a document that is not in this
   repository.
4. **Core-specific behaviour goes behind the core interface.**  Anything true
   of one core but not of PowerPC generally belongs in `model/cores/<core>/`,
   via the hooks in `model/ppc_core_iface.sail`.  The 601 has plenty: the POWER
   holdover instructions, the RTC, unified BATs, I/O controller interface
   segments, HID-based debug.  Anything true of the 603, 604, 604e and 750
   *alike* — the architected facilities the 601 predates — belongs in
   `model/cores/common/` instead, which is not part of the interface but is
   shared by those four.  Prefer that to repeating a thing four times.

## Tests

Test programs live in `test/` as `<name>.S`.  The 601's expected output is
`test/<name>.expected` and every later core's is `test/<core>/<name>.expected`;
`test/<core>.tests` lists the programs that apply to that core, with a comment
saying why each excluded one does not.  A program written for one core must be
added to that core's manifest and to no other.  Three conventions matter:

- **Derive the expected values from the manual, in the header, before the
  code.**  Every existing test does this — see [`test/fpmadd.S`](test/fpmadd.S),
  which works out an exact product by hand to show that the multiply-add does
  not round in the middle, or [`test/pagetable.S`](test/pagetable.S), which
  derives both PTEG addresses from the hash.  An expected file that is only a
  snapshot of current behaviour cannot catch the model being wrong.
- **Use `HALT(status)` from [`test/testlib.h`](test/testlib.h)** to end the
  program.  Output is captured from the `[halt]` or `[checkstop]` line onwards,
  so the banner and instruction trace never leak into expected files.
- **Say in the header which cores the program is for, and why.**  A program
  that uses a facility one core lacks is not a failure of that core, and the
  manifest comment plus the header is where a reader finds out which it is —
  see [`test/timebase.S`](test/timebase.S), which opens by saying it is not a
  601 test and that the 601 has no time base at all.

## What contributions are most valuable

1. **Measurements from real silicon.**  This model has never been run against
   hardware, for any of the five cores.  Anything with one in it — a Power
   Macintosh 6100/7100/8100 for the 601, a 7300/8600/9600 for the 604e, a Beige
   G3 or a PowerBook G3 for the 750, a PowerPC RS/6000 or an IBM or Bull
   machine of the era — could settle questions the manuals leave open.  The open ones are marked `TODO-VERIFY`
   in the source; the current one is whether `mtmsr` suppresses the trace
   exception the way `sc` and `rfi` do, which §5.4.12.2 neither states nor
   denies.
2. **Closing the known divergences** listed in the README — the invalid-form
   policy is the largest and touches many instructions; the SPR undefined-bit
   masks are small, self-contained, and each directly observable through
   `mfspr`, so each can carry a test.
3. **More test programs**, especially around the exception model, the MMU
   corners, and floating-point rounding and exception delivery.
4. **Filling the post-601 gaps.**  The four later cores landed after the 601
   and are less exercised: `frsqrte` is not implemented at all, the per-core
   alignment rules are the 601's, and the performance monitor, thermal unit and
   the 603's software TLB reload are modelled as registers with no behaviour
   behind them.  Each is listed under *Known divergences* in the README with
   what it would take.  Test programs for the facilities those cores added —
   `test/timebase.S`, `test/ppc32bat.S` and `test/fpopt.S` are the pattern —
   are the most direct way in.
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
