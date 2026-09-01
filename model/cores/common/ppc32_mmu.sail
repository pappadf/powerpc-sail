/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc32_mmu.sail — architected block address translation, shared by the 603e,
 * 604, 604e and 750.  Reference: MPCFPE32B §7.5, Figures 7-6..7-9,
 * Tables 7-10/7-11/7-12.
 *
 * Differences from the 601's unified array (cores/p601/p601_mmu.sail), which
 * are why the two cannot share an implementation:
 *  - SPLIT arrays: four entries for instruction accesses and four for data,
 *    selected by the access type rather than one set serving both (§7.5.1);
 *  - validity by Vs/Vp against MSR[PR], where the 601 uses the Ks/Ku key of
 *    the segment protection mechanism;
 *  - an entry that matches BEPI but whose valid bit for the current privilege
 *    is clear is IGNORED, not a violation — see the note in the body;
 *  - protection from PP ALONE, with no key bit (§7.5.4, Table 7-11), where
 *    the 601 feeds a key into the same rules the segments use;
 *  - the valid bits are in the upper register, not the lower;
 *  - block sizes reach 256 MB via an eleven-bit BL, against the 601's 8 MB
 *    (Table 7-10 against MPC601UM Table 6-12);
 *  - the mode reported is WIMG, including the guarded bit the 601 lacks.
 */

$ifndef _PPC32_MMU
$define _PPC32_MMU

/* The BL field masks the block effective page index, which is the top 15 bits
 * of an address (manual bits 0-14).  Its eleven bits align with the LOW end
 * of that field — "the rightmost bit of the BL field is aligned with bit 14
 * of the effective address" (§7.5.3) — so widening it to a 15-bit mask means
 * padding on the left.  Ones mark the bits that vary within the block: they
 * are excluded from the match and pass through to the physical address. */
val ppc32_bl_mask : bits(11) -> bits(15)
function ppc32_bl_mask(bl) = zeros(4) @ bl

/* Block protection (§7.5.4, Table 7-11): PP alone, with NO key bit.
 *   00 no access, x1 read only, 10 read/write.
 * This is deliberately not protection_ok (ppc_mmu.sail), which is the
 * segment/page mechanism and takes a key: passing a zero key to it would make
 * PP = 00 permit everything, the exact opposite of the rule here.
 * An instruction fetch is a read. */
val ppc32_block_protection_ok : (bits(2), MemoryAccess) -> bool
function ppc32_block_protection_ok(pp, acc) = {
  let store = is_store_access(acc);
  match pp {
    0b00 => false,
    0b10 => true,
    _    => not_bool(store)     /* x1: read only */
  }
}

/* Is this BAT entry in use for the current privilege level (§7.5.2)?
 *   BAT_entry_valid = (Vs & ~MSR[PR]) | (Vp & MSR[PR]) */
val ppc32_bat_valid : Ppc32_BatU -> bool
function ppc32_bat_valid(batu) =
  if MSR[PR] == 0b1 then batu[Vp] == 0b1 else batu[Vs] == 0b1

function core_bat_translate(ea, acc) = {
  let ea_bepi : bits(15) = ea[31 .. 17];
  /* Instruction accesses use the IBAT array and data accesses the DBAT array;
   * "if a memory area is to be mapped by the BAT mechanism for both
   * instruction and data accesses, the mapping must be set up in both an IBAT
   * and DBAT entry" (§7.5.2). */
  let fetch = is_fetch_access(acc);
  var result : BatResult = BAT_Miss();
  var matched : bool = false;
  foreach (i from 0 to 3) {
    let batu = Mk_Ppc32_BatU(if fetch then IBATU[i] else DBATU[i]);
    let batl = Mk_Ppc32_BatL(if fetch then IBATL[i] else DBATL[i]);
    let mask = ppc32_bl_mask(batu[BL]);
    /* §7.5.3: "bits of the effective address corresponding to ones in the BL
     * field are then cleared for the comparison".  BEPI is compared as
     * written — software is required to leave its low bits zero, and §7.5.3
     * says the result is undefined otherwise.
     *
     * The valid test is part of the MATCH criteria, not of protection:
     * "the valid bits (Vs and Vp) are used as part of the match criteria for
     * a BAT array entry and are not explicitly part of the protection
     * mechanism" (§7.5.4).  So a user-mode access to a block marked valid for
     * supervisor only is a MISS that falls through to page translation, not a
     * violation — §7.5.2 spells that case out, because it is how a supervisor
     * shares part of its address space with a paged user mapping.  This is
     * the opposite of what a matching-but-forbidden PP does two lines below,
     * and the difference is deliberate.
     *
     * UNDEF: the architecture does not say what happens when two entries
     * cover one address.  Policy: the lowest-numbered entry wins, the same
     * choice the 601 code makes for the same reason. */
    if ppc32_bat_valid(batu) & not_bool(matched)
       & ((ea_bepi & not_vec(mask)) == batu[BEPI]) then {
      matched = true;
      if ppc32_block_protection_ok(batl[PP], acc) then {
        /* Physical address (§7.5.5, Figure 7-9): the address bits the mask
         * lets through are the offset within the block and are OR-ed into the
         * block physical page number; the low 17 bits pass through
         * untranslated. */
        let pa_bepi = batl[BRPN] | (ea_bepi & mask);
        result = BAT_Hit(pa_bepi @ ea[16 .. 0], batl[WIMG])
      } else
        result = BAT_Violation()
    }
  };
  result
}

$endif
