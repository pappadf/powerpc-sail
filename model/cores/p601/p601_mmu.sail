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
        result = BAT_Hit(pa_bpi @ ea[16 .. 0], batu[WIM])
      } else
        result = BAT_Violation()
    }
  };
  result
}

$endif
