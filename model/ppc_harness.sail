/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_harness.sail — observation hooks for external test harnesses.
 *
 * NOTHING IN THIS FILE IS ARCHITECTURAL, and no hook in it changes what the
 * model computes: each one is a call out to the C driver saying what the
 * model just did.  The default implementations (c/harness_hooks_noop.c) do
 * nothing and compile away, which is what the ordinary emulator links
 * against; a harness supplies its own.
 *
 * They exist because three parts of an instruction's *footprint* cannot be
 * recovered from the architected state after the fact:
 *
 *   - which physical addresses it touched, at what width.  A store's target
 *     is derivable from the state diff only when the stored value differs
 *     from what was already there, and a load leaves no trace at all.
 *   - whether it took an exception, and to which vector.  Guessing from the
 *     state diff (SRR0/SRR1 written, NIA on a vector address) misreads a
 *     plain branch to a low address, and cannot see an exception that
 *     happened to write SRR0/SRR1 with the values they already held.
 *   - WHICH REGISTERS IT WROTE.  `sail -c` emits every register as a plain C
 *     global, so a driver can snapshot the architected state around step()
 *     and diff it — but a diff is a *change*-set, not a write-set, and the
 *     two differ exactly when an instruction stores the value already there.
 *     That is not a corner case: `crand 0x1c,0x1d,0x1c` writes a CR bit
 *     inside the field it reads, so all-zeros and all-ones are both fixed
 *     points and no choice of input makes the write visible.  A test vector
 *     that says "this location is unchanged" about a location the
 *     instruction rewrites is wrong in the dangerous direction, so the model
 *     has to say what it wrote rather than let a driver infer it.
 *
 * Placement: each hook sits where the traffic of its kind actually happens.
 * The memory and exception hooks get one choke point each; register writes
 * have no choke point, because the instruction semantics assign registers
 * directly (`NIA = ...`, `XER[CA] = ...`) as well as through accessors, so
 * harness_note_write is called at every write site.  Hooking only the
 * accessors would under-report, which is worse than not hooking at all.
 *
 * Consumer: the single-step test-vector harness of the powerpc-test project
 * (see its generator/HARNESS.md for the wire protocol built on top of these).
 */

$ifndef _PPC_HARNESS
$define _PPC_HARNESS

/* --- Memory accesses ---------------------------------------------------- */

/* Access kinds passed to harness_note_mem.
 *
 * Fetch is separated from read because a test vector's memory footprint is
 * about the data the instruction touched, not the instruction word itself,
 * and the consumer wants to drop the latter.
 *
 * The page-table walk is separated from both for the same reason from the
 * other end: with translation on, every access drags the walk's PTE reads
 * and its R/C-bit writeback along with it (ppc_mmu.sail), and those belong
 * to the MMU, not to the instruction.  A consumer that cannot tell them
 * apart has to over-report the instruction's own footprint. */
let harness_mem_read       : bits(8) = 0x00
let harness_mem_write      : bits(8) = 0x01
let harness_mem_fetch      : bits(8) = 0x02
let harness_mem_walk_read  : bits(8) = 0x03
let harness_mem_walk_write : bits(8) = 0x04

/* Note one physical memory access: (kind, physical address, width in bytes).
 *
 * Called BEFORE the access is performed, which is what lets a harness read
 * the bytes a write is about to replace and so report a byte-exact memory
 * diff.  The address is the physical one actually presented to memory, after
 * translation and after the little-endian munge (ppc_mem.sail, le_munge) —
 * i.e. the address the bus would see, not the effective address.
 *
 * Bit vectors rather than `int` for kind and width deliberately: `int` is
 * arbitrary precision and the C backend passes it as an mpz_t, which would
 * put an allocation on the path of every memory access in every build,
 * including builds whose hook does nothing. */
val harness_note_mem = impure "harness_note_mem" : (bits(8), bits(32), bits(8)) -> unit

/* --- Exceptions --------------------------------------------------------- */

/* Note that an exception was taken, giving the address NIA was redirected to.
 * That is exception_base() | core_exception_vector(e), so it already accounts
 * for MSR[EP] and for the core's own vector table, and it identifies the
 * exception uniquely except where a core deliberately shares a vector (on the
 * 601, run-mode and trace both use 0x2000 — see core_exception_vector). */
val harness_note_exception = impure "harness_note_exception" : bits(32) -> unit

/* --- Register writes ---------------------------------------------------- */

/* Register ids.  The low half is the architected common state, the high half
 * (0x80 and up) is the core's own — see the core's register file for those,
 * so that adding a 603 or a 604 does not touch this file.
 *
 * The register files get one id per register rather than an id plus an index
 * argument: the id is what a consumer names its state element by, and a flat
 * id keeps the hook to two arguments and the C side to one array lookup. */
let hw_gpr0  : bits(8) = 0x00   /* .. 0x1F, GPR0 .. GPR31   */
let hw_fpr0  : bits(8) = 0x20   /* .. 0x3F, FPR0 .. FPR31   */
let hw_sr0   : bits(8) = 0x40   /* .. 0x4F, SR0 .. SR15     */
let hw_cr    : bits(8) = 0x50
let hw_xer   : bits(8) = 0x51
let hw_fpscr : bits(8) = 0x52
let hw_cia   : bits(8) = 0x53
let hw_nia   : bits(8) = 0x54
let hw_lr    : bits(8) = 0x55
let hw_ctr   : bits(8) = 0x56
let hw_msr   : bits(8) = 0x57
let hw_srr0  : bits(8) = 0x58
let hw_srr1  : bits(8) = 0x59
let hw_dar   : bits(8) = 0x5A
let hw_dsisr : bits(8) = 0x5B
let hw_sprg0 : bits(8) = 0x5C   /* .. 0x5F, SPRG0 .. SPRG3  */
let hw_sprg1 : bits(8) = 0x5D
let hw_sprg2 : bits(8) = 0x5E
let hw_sprg3 : bits(8) = 0x5F
let hw_dec   : bits(8) = 0x60
let hw_sdr1  : bits(8) = 0x61
let hw_ear   : bits(8) = 0x62
let hw_reservation : bits(8) = 0x63

/* Note that a register was written, whether or not the value changed.
 *
 * `mask` says WHICH BITS of the register the write covered, so that a
 * consumer naming sub-fields (CR0..CR7, XER[CA], the FPSCR flags) learns
 * which of them the write reached.  For a register with no named sub-fields
 * it is all ones — harness_wrote below is the spelling for that, and is what
 * nearly every call site uses.  The masks for the fields that are written
 * piecemeal are derived from the bitfield definitions themselves (see
 * ppc_regs.sail), so they cannot drift from the layout they describe.
 *
 * The hook says nothing about the value: a consumer that wants it reads the
 * register afterwards, and one that only wants the write-set — which is the
 * point of the hook — does not pay for marshalling it. */
val harness_note_write = impure "harness_note_write" : (bits(8), bits(32)) -> unit

val harness_wrote : bits(8) -> unit
function harness_wrote(reg) = harness_note_write(reg, 0xFFFFFFFF)

$endif
