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
 * They exist because two parts of an instruction's *footprint* cannot be
 * recovered from the architected state after the fact:
 *
 *   - which physical addresses it touched, at what width.  A store's target
 *     is derivable from the state diff only when the stored value differs
 *     from what was already there, and a load leaves no trace at all.
 *   - whether it took an exception, and to which vector.  Guessing from the
 *     state diff (SRR0/SRR1 written, NIA on a vector address) misreads a
 *     plain branch to a low address, and cannot see an exception that
 *     happened to write SRR0/SRR1 with the values they already held.
 *
 * Register writes are NOT hooked, because they need no hook: `sail -c` emits
 * every register as a plain C global, so a C driver can snapshot the whole
 * architected state around step() and diff it, exactly and for free.
 *
 * Placement: each hook sits at a choke point that all traffic of its kind
 * already funnels through, so the whole diff against the uninstrumented model
 * is four call sites — three in ppc_mem.sail (phys_read, phys_write,
 * phys_fetch) and one in ppc_exceptions.sail (take_exception).
 *
 * Consumer: the single-step test-vector harness of the powerpc-test project
 * (see its generator/HARNESS.md for the wire protocol built on top of these).
 */

$ifndef _PPC_HARNESS
$define _PPC_HARNESS

/* Access kinds passed to harness_note_mem.  Fetch is separated from read
 * because a test vector's memory footprint is about the data the instruction
 * touched, not the instruction word itself, and the consumer wants to drop
 * the latter. */
let harness_mem_read  : bits(8) = 0x00
let harness_mem_write : bits(8) = 0x01
let harness_mem_fetch : bits(8) = 0x02

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

/* Note that an exception was taken, giving the address NIA was redirected to.
 * That is exception_base() | core_exception_vector(e), so it already accounts
 * for MSR[EP] and for the core's own vector table, and it identifies the
 * exception uniquely except where a core deliberately shares a vector (on the
 * 601, run-mode and trace both use 0x2000 — see core_exception_vector). */
val harness_note_exception = impure "harness_note_exception" : bits(32) -> unit

$endif
