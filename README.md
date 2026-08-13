# powerpc-sail — a Sail specification of the PowerPC 601

[![ci](https://github.com/pappadf/powerpc-sail/actions/workflows/ci.yml/badge.svg)](https://github.com/pappadf/powerpc-sail/actions/workflows/ci.yml)

A formal, executable ISA specification of the **PowerPC 601** — the first
PowerPC processor, the bridge between POWER and PowerPC, and the CPU of the
original Power Macintosh — written in
[Sail](https://github.com/rems-project/sail), the ISA description language
used for the official RISC-V, CHERI and Arm specification models.

The specification is written from the primary source, Motorola's **MPC601
RISC Microprocessor User's Manual**, cited throughout the model by section
(`§6.8.3.2`), table (`Table 3-40`), figure and chapter-10 instruction page.
Where the manual is ambiguous or contradicts itself — and on the 601 it does
so more than once — the model states the conflict, argues which reading
governs, and says so in the source rather than picking silently.  The manual
is not redistributed here; you will need your own copy to follow the
citations.

The model is structured for more than one core: everything architecture-common
lives in `model/`, and each implementation supplies the hooks in
`model/ppc_core_iface.sail` from its own directory under `model/cores/`.  Only
the 601 exists today; the 603 and 604 are the reason the seam is there.

## A note on AI

**AI tools were used in the making of this project** — writing the
specification, drafting documentation, and checking it against the manual.
That is worth stating plainly up front, because a specification is offered as
a *reference* and you should know how it was produced before trusting it as
ground truth.

## Status

| Piece | State |
|---|---|
| Instruction AST, decoder and execute semantics — **187 instructions** | **done** |
| The 28 POWER holdovers the 601 keeps (`abs`, `doz`, `mul`/`div` with MQ, the `*q` shifts, `lscbx`, `clcs`) | **done** |
| Disassembler — a bidirectional `assembly` mapping, objdump-style syntax, every instruction covered | **done** |
| Floating point — IEEE 754 single/double from scratch, exact intermediates, full FPSCR and exception model | **done** |
| MMU — BATs, segment registers, hashed page table, I/O controller interface segments, protection, R/C bits | **done** |
| Exceptions — alignment, DSI/ISI, program, FP unavailable, decrementer, system call, trace, run mode, checkstop | **done** |
| RTC, DEC and the 601's dual SPR numbering | **done** |
| Debug facilities — IABR/DABR address compare | partial: IABR compare modes `111` and `100` unimplemented |
| Cores other than the 601 | interface scaffolded, only `p601` implemented |
| Cache model | out of scope — `dcbz` has its architectural effect, the rest are no-ops |
| TLB | deliberately not modelled; translation walks the page table afresh each access |
| Devices and platform | out of scope — the harness offers a halt call and a final state dump |

## Validation

> **This model has not been validated against real PowerPC 601 hardware.**
> Everything below is synthetic: it checks the model against the manual and
> against itself, not against silicon.

1. **Typecheck and coverage** (`make check`) — the model must typecheck with
   zero errors *and* zero warnings, and every `union clause ast` must have
   exactly one `mapping clause assembly`.  Sail does not require a scattered
   mapping to be total, so that second check is done by the build rather than
   the compiler; a missing disassembly clause would otherwise only surface as
   a match failure at runtime.
2. **Test programs** (`make test`) — 53 PowerPC assembly programs in
   [`test/`](test/), assembled and linked by a real PowerPC cross toolchain,
   run under the generated emulator to a halt, with the full architectural
   state diffed against a checked-in `.expected` file.  Two things are worth
   noting about them.  First, the assembler is itself a check: several tests
   record encodings GNU `as` refuses, which is how the model's encdec clauses
   get an independent opinion.  Second, the expected values are **derived by
   hand from the manual** — each program's header works out what the answer
   must be and why, before the code — so they are not merely a snapshot of
   what the model happened to print.
3. **Disassembler exercise** (`make test-disasm`) — every test program is
   re-run with tracing on, which puts the `assembly` mapping over every
   instruction actually executed.

What this does **not** cover: instruction timing, the cache and bus protocols,
the boundedly-undefined cases where the model necessarily picks one legal
answer, anything the manual gets wrong about the silicon, and every corner no
test happens to reach.  Measurements from a real 601 are the single most
valuable thing anyone could contribute — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Known divergences

Places where the model knowingly differs from the manual, all marked `TODO` in
the source:

- **Invalid instruction forms trap.**  §5.4.7 is explicit that "instructions
  using an invalid instruction form do not take a program exception, but
  instead cause results that are boundedly undefined".  Reserved-field
  violations currently decode to `ILLEGAL` and raise a program exception
  instead.  This is one decision affecting many instructions.
- **Undefined SPR bits read back.**  Table 2-14 requires SDR1, HID0 and
  HID15/PIR to return zero in their undefined bit positions; they currently
  keep whatever was written.  (FPSCR, which the same table covers, is masked
  correctly.)
- **IABR compare modes `111` and `100`** are not implemented.
- **HID0[LM] takes effect immediately.**  §2.4.3 requires software to bracket
  the `mtspr` with three `sync` instructions either side; that binds the
  program rather than the processor, and the pipeline behaviour it guards
  against cannot arise in a model that completes one instruction at a time.
- **No TLB**, so reference and change bits are written on every access rather
  than on a miss — the same values, differing only in bus traffic, which is
  not modelled either.

## Layout

- `model/prelude.sail` — stdlib imports, bit-numbering convention, helpers
- `model/ppc_types.sail` — common types, fault and access kinds
- `model/ppc_core_iface.sail` — the hooks an implementation must provide
- `model/ppc_regs.sail` — architected registers (GPR, CR, XER, MSR, FPSCR, SRs)
- `model/ppc_softfloat.sail` — IEEE 754 arithmetic built from scratch
- `model/ppc_mem.sail` — flat physical memory, endianness, address munging
- `model/ppc_mmu.sail` — translation: direct, BAT, segment + hashed page table
- `model/ppc_exceptions.sail` — the exception model and vector dispatch
- `model/ppc_sprs.sail` — architecture-common SPR read/write clauses
- `model/ppc_insts_*.sail` — semantics by family: integer, load/store, branch,
  floating point, system, cache
- `model/ppc_assembly.sail` — the `assembly` mapping (disassembler/assembler)
- `model/ppc_step.sail` — fetch/decode/execute and interrupt delivery
- `model/ppc_debug.sail` — the harness halt convention and state dump
- `model/main.sail` — emulator entry point
- `model/cores/p601/` — the 601: its registers, SPRs, MMU quirks, POWER
  instructions and core-interface implementation
- `test/` — assembly test programs and their expected final state

File order matters to the build: Sail requires declaration before use, and the
scattered instruction and SPR definitions are opened and closed by
`ppc_insts_begin.sail` / `ppc_insts_end.sail`.  The ordered list lives in the
[`Makefile`](Makefile).

## Building

Needs the `sail` compiler (developed against 0.20.2; the relocatable
[binary release](https://github.com/rems-project/sail/releases) works without
an OCaml toolchain), `z3`, a C compiler, `libgmp-dev` and `zlib`.  The test
programs additionally need a PowerPC cross toolchain — on Debian/Ubuntu,
`apt install gcc-powerpc-linux-gnu`.

```sh
make check         # typecheck + assembly-clause coverage
make emulator      # build the C emulator -> build/ppc_p601
make run           # build and run the embedded smoke test
make test          # assemble test/*.S and diff against test/*.expected
make test-disasm   # re-run those programs with tracing, exercising the disassembler
make clean
```

Core selection is a variable, `make CORE=p601` (the default, and currently the
only one).

## Design notes

- **Bit numbering.**  PowerPC numbers bits big-endian — bit 0 is the most
  significant — while Sail works best with `dec` indexing.  The model uses
  `dec` throughout and every bitfield carries the manual's numbers in a
  comment, so the two can be checked against each other.  The conversion is
  `sail index = 31 - manual index`.
- **The manual's vocabulary, and no width parameter.**  Names in the model
  are the ones the manual uses: `word` for 32 bits, `ridx`/`fridx` for the
  `rA`/`frA` operand fields, `Completion`/`COMPLETED` because the manual
  describes instructions as *completing* and never once says "retire",
  `MemoryAccess` because it says "memory access" rather than the later
  architecture's "storage access".  There is deliberately **no** register-width
  parameter.  PowerPC fixes its data lengths — a byte, half word, word and
  double word are 8, 16, 32 and 64 bits on every implementation — and only
  some registers follow the implementation width: the manual says the LR is
  "32 bits wide in 32-bit implementations" (§1.3.2.1.8) but that the CR is
  flatly "a 32-bit register" (§2.2.4), and that the segment registers are
  "present only in 32-bit implementations" (§6.1.11).  One alias standing for
  all of those would be wrong for most of them, so the model spells 32 bits
  `word` and leaves the distinction to be drawn properly if a 64-bit core is
  ever added.  The 601, 603 and 604 are all 32-bit implementations.
- **Floating point from scratch.**  Sail's bundled float library declares its
  operations as external primitives the C backend cannot implement, and the
  pure-Sail one has no multiply, divide or fused multiply-add.  Binding
  Berkeley SoftFloat through C glue would add a build dependency and tie the
  model to the C backend, so the prover backends could not run floating point
  at all.  Instead a finite value is carried as an exact
  `(sign, significand, exponent)` triple over arbitrary-precision Sail
  integers, so every operation but division is computed *exactly* and the
  "infinitely precise intermediate result" of §2.5.1 is literal rather than
  emulated with guard and sticky bits.  Rounding happens once.  PowerPC's
  habit of delivering an enabled overflow or underflow with the exponent
  adjusted by a constant then falls out as one addition.
- **No TLB, on purpose.**  Walking the page table on every access is
  observationally equivalent to a TLB that is always coherent with memory,
  which is what `tlbie` exists to arrange.
- **"Undefined" means unchanged.**  Where the architecture leaves a register
  undefined the model leaves it alone rather than inventing a value, which is
  what lets a test observe that an instruction did *not* write it.
- **Flat binaries, not ELF.**  The Sail C runtime's ELF loader accepts only
  ARM, RISC-V and x86 objects, so test programs are loaded as flat binaries
  with the entry point supplied separately until that is fixed upstream.

## License

MIT — see [LICENSE](LICENSE).

---

*PowerPC is a trademark of International Business Machines Corporation.  All
trademarks referenced in this project are the property of their respective
owners and are used for identification purposes only; no endorsement by or
affiliation with the trademark holders is claimed.*
