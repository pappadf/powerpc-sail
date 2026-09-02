/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_insts_cache.sail — cache control and memory synchronization
 * instructions (MPC601UM §3.5.7, §3.8, ch. 4).
 *
 * IMPLEMENTED:
 *   sync isync eieio                           (Table 3-21)
 *   lwarx stwcx.                               (Table 3-21)
 *   dcbt dcbtst dcbz dcbst dcbf icbi           (Table 3-44)
 *   dcbi                                       (Table 3-43, supervisor)
 *   (clcs is 601-only -> cores/p601/p601_insts_power.sail.)
 *
 * NO CACHE IS MODELLED (601: 32 KB unified, 8-way, 32-byte sectors; ch. 4),
 * which decides most of this file: an instruction whose whole effect is on
 * cache state has no effect here.  What survives is everything ELSE those
 * instructions do — translate, check protection, fault — and the one that
 * changes memory rather than the cache, dcbz.  Each is commented with why
 * it is or is not a no-op, because "it does nothing" is otherwise
 * indistinguishable from "it is not implemented".
 *
 * sync/isync/eieio are architectural no-ops for a sequential single-hart
 * model; revisit if a weak-memory concurrency model is added (Sail's
 * concurrency_interface would then replace the flat read_ram/write_ram
 * memory in ppc_mem.sail).
 */

$ifndef _PPC_INSTS_CACHE
$define _PPC_INSTS_CACHE

/* --- Memory synchronization (Table 3-21) -------------------------------- */

union clause ast = SYNC : unit
mapping clause encdec =
  SYNC() <-> 0b011111 @ 0b00000 @ 0b00000 @ 0b00000 @ 0b1001010110 @ 0b0
function clause execute(SYNC()) = COMPLETED

union clause ast = ISYNC : unit
mapping clause encdec =
  ISYNC() <-> 0b010011 @ 0b00000 @ 0b00000 @ 0b00000 @ 0b0010010110 @ 0b0
function clause execute(ISYNC()) = COMPLETED

union clause ast = EIEIO : unit
mapping clause encdec =
  EIEIO() <-> 0b011111 @ 0b00000 @ 0b00000 @ 0b00000 @ 0b1101010110 @ 0b0
function clause execute(EIEIO()) = COMPLETED

/* --- lwarx / stwcx. (§3.5.7) -------------------------------------------- */

/* lwarx loads a word and takes out a reservation; stwcx. stores only if the
 * reservation still stands, and reports in CR0 whether it did.  The
 * reservation itself is a single flag in ppc_mem.sail — see there for why
 * the reserved address is not modelled.
 *
 * Both are ordinary loads and stores as far as translation and protection
 * go, with two exceptions.  On the 601 they may not be used in a
 * non-memory-forced I/O controller interface segment (§6.10.5), and the EA
 * "must be a multiple of 4" — what a violation does is per-core
 * (Align_atomic): the 601 faults it only when the operand crosses a
 * boundary its §5.4.6.1 rules cover and otherwise performs it as written
 * (INVALID-FORM, boundedly undefined), while the later cores fault any
 * misaligned EA outright (§4.5.6).
 *
 * THE ALIGNMENT RANGE CHECK COMES FIRST, before the reservation is even
 * consulted: §5.4.6.1 — "the appropriate range check is performed before
 * the instruction begins execution", so that a fault "is guaranteed that no
 * portion of the instruction has been executed".  §5.4.3's rule that an
 * stwcx. whose reservation is clear "cannot generate an exception,
 * regardless of whether the address translation would have failed, page
 * protection would have been violated, or the address matches one in the
 * DABR" is scoped, by its own lead-in, to the DATA ACCESS exception — its
 * three reasons are all §5.4.3 causes — and does not reach the
 * higher-priority alignment exception.  (Reported by an external 601 core:
 * a reservation-less stwcx. at 0xFFFFFFFE must take the 256 MB-crossing
 * alignment fault, not complete with CR0 = SO.) */

union clause ast = LWARX : (ridx, ridx, ridx)

mapping clause encdec =
  LWARX(rD, rA, rB) <->
    0b011111 @ rD : ridx @ rA : ridx @ rB : ridx @ 0b0000010100 @ 0b0

function clause execute(LWARX(rD, rA, rB)) = {
  let ea = ea_x(rA, rB);
  /* Alignment ahead of the I/O-segment data access exception: §2.4.3.2
   * puts alignment exceptions ahead of data access exceptions, and the
   * range check precedes execution (§5.4.6.1). */
  if align_check(ea, 4, Align_atomic) then EXCEPTION_TAKEN
  else if nonforced_io_segment(ea) then data_access_fault(Fault_IOSegUnsupported, ea, false)
  else match mem_read_raw(ea, 4) {
    Some(v) => {
      GPR(rD) = v;
      set_reservation();
      COMPLETED
    },
    None() => EXCEPTION_TAKEN
  }
}

union clause ast = STWCX : (ridx, ridx, ridx)

mapping clause encdec =
  STWCX(rS, rA, rB) <->
    0b011111 @ rS : ridx @ rA : ridx @ rB : ridx @ 0b0010010110 @ 0b1

function clause execute(STWCX(rS, rA, rB)) = {
  let ea = ea_x(rA, rB);
  if align_check(ea, 4, Align_atomic) then EXCEPTION_TAKEN
  else if not_bool(reservation_valid) then {
    /* The range check above is the ONE thing that precedes this: with the
     * reservation already gone the instruction takes no data access
     * exception of any kind (§5.4.3, quoted in the header) — the EA is
     * never translated at all and only CR0 is written. */
    CRfield(0, 0b00 @ 0b0 @ XER[SO]);
    COMPLETED
  } else if nonforced_io_segment(ea) then
    data_access_fault(Fault_IOSegUnsupported, ea, true)
  else if mem_write_raw(ea, 4, GPR(rS)) then {
    /* CR0 <- 0b00 || store_performed || XER[SO] */
    clear_reservation();
    CRfield(0, 0b00 @ 0b1 @ XER[SO]);
    COMPLETED
  } else
    /* The store faulted; take_exception has already dropped the
     * reservation, and CR0 is not written because the instruction did not
     * complete. */
    EXCEPTION_TAKEN
}

/* --- Cache control (Tables 3-43/3-44) ----------------------------------- */

/* Shared shape for the cache instructions that do nothing here but must
 * still behave like an access for translation and protection, and so can
 * still take a data access exception.
 *
 * The no-op case is a segment with T=1 that is NOT memory-forced: a cache
 * instruction addressing a memory-forced segment "translates the address
 * appropriately and performs the cache operation based on that address"
 * (§3.8.2) — see nonforced_io_segment for why that beats the flatter
 * statement on the ch. 10 pages. */
val cache_op : (word, MemoryAccess) -> Completion
function cache_op(ea, acc) =
  if nonforced_io_segment(ea) then COMPLETED
  else match translate_addr(ea, acc) {
    TR_Address(_, _) => COMPLETED,
    TR_Fault(cause)  => data_access_fault(cause, ea, is_store_access(acc))
  }

/* dcbt and dcbtst are PURE no-ops, not merely cache-less ones.  Everything
 * they could otherwise leave behind is ruled out in turn: "executing dcbt
 * does not cause any exceptions to be invoked" and a translation fault or
 * protection violation makes them a no-op instead (§4.8.2, ch. 10 page);
 * "this instruction never affects the reference or change bits" (§4.8.2);
 * they are exempt from the DABR (Table 2-26); and there is no cache to
 * prefetch into.  So they do not even compute an EA here.  dcbtst "behaves
 * exactly like the dcbt instruction as implemented on the 601" (§4.8.3). */
union clause ast = DCBT : (ridx, ridx)

mapping clause encdec =
  DCBT(rA, rB) <->
    0b011111 @ 0b00000 @ rA : ridx @ rB : ridx @ 0b0100010110 @ 0b0

function clause execute(DCBT(_rA, _rB)) = COMPLETED

union clause ast = DCBTST : (ridx, ridx)

mapping clause encdec =
  DCBTST(rA, rB) <->
    0b011111 @ 0b00000 @ rA : ridx @ rB : ridx @ 0b0011110110 @ 0b0

function clause execute(DCBTST(_rA, _rB)) = COMPLETED

/* icbi is a no-op on the 601 because the cache is unified, and the ch. 10
 * page goes further than §4.8.8 does: the 601 treats it as a no-op "even to
 * the extent of not validating the EA".  So unlike dcbst and dcbf it does
 * not translate and cannot fault. */
union clause ast = ICBI : (ridx, ridx)

mapping clause encdec =
  ICBI(rA, rB) <->
    0b011111 @ 0b00000 @ rA : ridx @ rB : ridx @ 0b1111010110 @ 0b0

function clause execute(ICBI(_rA, _rB)) = COMPLETED

/* dcbst and dcbf write back and/or invalidate a sector.  With no cache
 * there is nothing to write back, but both "operate as a load from the
 * addressed byte with respect to address translation and protection"
 * (ch. 10 pages), so a translation fault or protection violation is still
 * reported. */
union clause ast = DCBST : (ridx, ridx)

mapping clause encdec =
  DCBST(rA, rB) <->
    0b011111 @ 0b00000 @ rA : ridx @ rB : ridx @ 0b0000110110 @ 0b0

function clause execute(DCBST(rA, rB)) = cache_op(ea_x(rA, rB), Mem_load)

union clause ast = DCBF : (ridx, ridx)

mapping clause encdec =
  DCBF(rA, rB) <->
    0b011111 @ 0b00000 @ rA : ridx @ rB : ridx @ 0b0001010110 @ 0b0

function clause execute(DCBF(rA, rB)) = cache_op(ea_x(rA, rB), Mem_load)

/* dcbi is the same shape but supervisor-level and store-typed: it "operates
 * as a store to the addressed byte with respect to address translation and
 * protection.  The reference and change bits are modified appropriately"
 * (ch. 10 page) — which page_translate does for any Mem_store. */
union clause ast = DCBI : (ridx, ridx)

mapping clause encdec =
  DCBI(rA, rB) <->
    0b011111 @ 0b00000 @ rA : ridx @ rB : ridx @ 0b0111010110 @ 0b0

function clause execute(DCBI(rA, rB)) =
  if in_user_mode() then program_exception(Prog_Privileged)
  else cache_op(ea_x(rA, rB), Mem_store)

/* dcbz is the one cache instruction with an effect a cache-less model must
 * still produce: it sets a whole 32-byte sector to zero, and on hardware the
 * sector is established in the cache without being read from memory, so the
 * zeroes reach memory eventually either way.
 *
 * It is a store for translation and protection.  If the page is
 * caching-inhibited or write-through the 601 cannot do that trick and hands
 * the work to software instead, via the alignment exception (§4.8.4) — which
 * is the first and so far only reader of the WIMG mode that translation
 * returns.  The later cores state the same rule (MPC603EUM Table 4-2,
 * MPC750UM Table 1-5: "the operand of dcbz is in memory that is
 * write-through-required or caching-inhibited"), so it stays common.
 * Note the order: translation happens first, so its reference-bit update
 * lands before the alignment exception, as Figure 6-23 requires.
 *
 * No alignment check on the EA itself: the sector is derived by masking, so
 * it cannot cross a page or 256 MB boundary however misaligned the EA was.
 * The address is not munged in little-endian mode either — "addresses for
 * ... cache control operations are not modified" (§2.4.3.1). */
union clause ast = DCBZ : (ridx, ridx)

mapping clause encdec =
  DCBZ(rA, rB) <->
    0b011111 @ 0b00000 @ rA : ridx @ rB : ridx @ 0b1111110110 @ 0b0

function clause execute(DCBZ(rA, rB)) = {
  let ea = ea_x(rA, rB);
  if nonforced_io_segment(ea) then COMPLETED
  else match translate_addr(ea, Mem_store) {
    TR_Fault(cause) => data_access_fault(cause, ea, true),
    TR_Address(pa, wimg) =>
      if wimg_write_through(wimg) | wimg_cache_inhibited(wimg) then
        alignment_exception(ea)
      else {
        let base = pa & 0xFFFFFFE0;    /* the 32-byte sector holding pa */
        foreach (i from 0 to 7) {
          phys_write(base + (4 * i), 4, zeros(32))
        };
        COMPLETED
      }
  }
}

$endif
