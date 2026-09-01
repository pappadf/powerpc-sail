/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p601_mmu.sail — 601 block address translation (unified BAT array).
 * Reference: MPC601UM §6.7, Figures 6-6..6-10, Tables 6-11/6-12.
 *
 * 601 BAT specifics vs. later 32-bit PowerPC:
 *  - 4 unified entries (used for both instruction and data accesses);
 *  - protection via Ks/Ku key + PP (like segments), not Vs/Vp;
 *  - V bit in the lower register;
 *  - block sizes 128 KB..8 MB via BSM mask;
 *  - BAT ignored entirely when the segment register has T=1 (Table 6-10)
 *    — that check happens in the common translate_addr;
 *  - BAT entries unaffected by tlbie.
 */

$ifndef _P601_MMU
$define _P601_MMU

/* --- Direct-store: the I/O controller interface (§6.10) ------------------ */

/* The 601 consults SR[T] before MSR[DT] and ignores the BAT array for a
 * segment with T=1 (§6.5.2.2, §6.7.2) — the architected order, which every
 * later core follows, is the other way round. */
function core_direct_store_first() = true

/* BUID x'07F' is the memory-forced encoding (§6.10.4): the access is an
 * ordinary memory access described by the segment register rather than by a
 * page table.  No later core has the notion. */
function core_memory_forced_segment(ea) = {
  let sr = rSR(ea[31 .. 28]);
  (sr[T] == 0b1) & (sr[BUID] == 0b001111111)
}

/* The 601's T=0 segment register has no no-execute bit; manual bits 3-7 are
 * reserved (§6.10, Figure 6-24). */
function core_segment_no_execute() = false

/* I/O controller interface segment access, T=1 (§6.10).  601/POWER only:
 * later cores call this the direct-store facility (604) or drop it (603e,
 * 750).
 *
 * The memory-forced case above becomes an ordinary memory access whose
 * physical address is the segment register's low four bits followed by
 * EA[4:31], bypassing every protection mechanism, with WIMG = 0b0110
 * (cache-inhibited and global; the 601's WIM = 0b011 plus G = 0, which the
 * 601 does not implement).  This maps a whole 256 MB segment through one
 * register and no page tables.
 *
 * Every other BUID names a device on the I/O controller interface, reached
 * with a two-packet bus protocol (§6.10.2, §9.6) that has nothing behind it
 * in this model — hence the throw.  A fetch from such a segment is an
 * instruction access exception instead (§6.8.2.2), and the 601 sets no SRR1
 * bits for it where the architecture sets bit 3 (Table 6-3, §5.4.4) — which
 * is what Fault_IOSegFetch means, as against the Fault_DirectStore the later
 * cores raise.  Protection is not enforced here at all: the key bit is passed
 * to the device, which may or may not act on it (§6.10.3).
 *
 * The cache instructions are no-ops in these segments (§6.10.6); cache_op and
 * dcbz check for that themselves (ppc_insts_cache.sail). */
function core_direct_store(ea, acc) = {
  let sr = rSR(ea[31 .. 28]);
  if sr[BUID] == 0b001111111 then
    TR_Address(sr[P1] @ ea[27 .. 0], 0b0110)
  else match acc {
    Mem_fetch => TR_Fault(Fault_IOSegFetch),
    _ => throw(Model_unimplemented("I/O controller interface transaction"))
  }
}

/* The BSM field masks the block logical page index, which is the top 15 bits
 * of an address (manual bits 0-14).  Its six bits align with the LOW end of
 * that field — the rightmost BSM bit against manual address bit 14 (§6.7.3)
 * — so widening it to a 15-bit mask means padding on the left.  Ones mark
 * the bits that vary within the block: they are excluded from the match and
 * pass through to the physical address. */
val p601_bsm_mask : bits(6) -> bits(15)
function p601_bsm_mask(bsm) = zeros(9) @ bsm

function core_bat_translate(ea, acc) = {
  let ea_bpi : bits(15) = ea[31 .. 17];
  var result : BatResult = BAT_Miss();
  var matched : bool = false;
  foreach (i from 0 to 3) {
    let batu = Mk_P601_BatU(BATU[i]);
    let batl = Mk_P601_BatL(BATL[i]);
    let mask = p601_bsm_mask(batl[BSM]);
    /* §6.7.3: "bits of the logical address corresponding to ones in the BSM
     * field are then forced to zero for the comparison".  BLPI is compared
     * as written — software is required to leave its low bits zero.
     * UNDEF: it is an error for two entries to cover one address, and the
     * result is undefined "and may include a spurious violation of the
     * memory protection mechanism, a machine check exception, or a check
     * stop condition" (§6.7.1).  Policy: the lowest-numbered entry wins. */
    if (batl[V] == 0b1) & not_bool(matched)
       & ((ea_bpi & not_vec(mask)) == batu[BLPI]) then {
      matched = true;
      /* Block protection (§6.7.4): same key/PP mechanism as segments, with
       * the keys in the upper BAT register rather than a segment register. */
      let key = if MSR[PR] == 0b1 then batu[Ku] else batu[Ks];
      if protection_ok(key, batu[PP], acc) then {
        /* Physical address (§6.7.5, Figure 6-8): the address bits the mask
         * lets through are the offset within the block and are OR-ed into
         * the physical block number; the low 17 bits pass through
         * untranslated. */
        let pa_bpi = batl[PBN] | (ea_bpi & mask);
        /* The 601 has no G bit (§6.3 defines W, I and M only), so the mode
         * this core reports is always unguarded — see TranslationResult in
         * ppc_types.sail for why the field is four bits wide regardless. */
        result = BAT_Hit(pa_bpi @ ea[16 .. 0], batu[WIM] @ 0b0)
      } else
        result = BAT_Violation()
    }
  };
  result
}

$endif
