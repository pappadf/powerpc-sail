/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p603_regs.sail — PowerPC 603-specific registers.
 * Reference: MPC603EUM §2.1.2 (implementation-specific registers).
 *
 * WHICH MANUAL, AND WHICH PART.  The only 603-family manual available to this
 * transcription is MPC603EUM, the 603e manual, and everything here is taken
 * from it.  See p603_core.sail for what that means for the PVR and for the
 * handful of places where the 603 and the two 603e variants differ.
 *
 * The shared post-601 registers — the time base, the split BAT arrays, HID0
 * and the IABR — are in cores/common/ppc32_regs.sail. */

$ifndef _P603_REGS
$define _P603_REGS

/* --- HID1 (SPR 1009, §2.1.2.1) ------------------------------------------- */

/* On the 603e HID1 holds the PLL configuration read back from the external
 * clock-select signals: no bit of it changes what the machine computes, so
 * like HID0 it is a plain word that reads back what was written rather than a
 * bitfield naming bits nothing reads. */
register HID1 : word

/* --- Software table search registers (§2.1.2.2 - §2.1.2.5, §5.5.2) ------- */

/* The 603 reloads its TLBs in SOFTWARE: a TLB miss raises one of the three
 * exceptions at 0x01000/0x01100/0x01200, and the handler walks the page table
 * and installs the entry with tlbld or tlbli.  These seven registers are the
 * interface between the hardware and that handler.
 *
 * THIS MODEL HAS NO TLB, and therefore never raises those exceptions and
 * never loads these registers itself — see the note on the miss vectors in
 * p603_core.sail, which is where that divergence is argued.  They are
 * modelled as plain read/write registers so that a handler which sets them up
 * and reads them back sees consistent state, and so that mfspr/mtspr behave
 * as the SPR map says they do.
 *
 * The manual makes DMISS/IMISS/DCMP/ICMP/RPA "read and write to the software"
 * and HASH1/HASH2 "read-only", which the SPR clauses in p603_sprs.sail
 * reflect.  Their formats (Tables 2-5, 2-6, 2-7) are not broken out into
 * bitfields, because nothing in this model constructs or consumes them:
 *
 *   DMISS/IMISS  effective page address of the missing access;
 *   DCMP/ICMP    manual bits 0 V | 1-24 VSID | 26-31 API — the first word of
 *                the PTE being looked for;
 *   HASH1/HASH2  manual bits 0-6 HTABORG[0:6] | 7-25 hashed PTEG address;
 *   RPA          the second word of the PTE, same layout as Pte1
 *                (ppc_mmu.sail). */
register DMISS : word
register IMISS : word
register DCMP : word
register ICMP : word
register HASH1 : word
register HASH2 : word
register RPA : word

/* --- Harness register ids for the 603's own registers -------------------- */

/* cores/common/ppc32_regs.sail takes 0x80-0x9F of the space ppc_harness.sail
 * reserves for the core; a core directory starts at 0xA0. */
/* HID1 uses the shared id hw_hid1, which ppc32_regs.sail reserves for it on
 * whichever cores have one — the 604 has no HID1, so the id is simply unused
 * there.  Reserving rather than renumbering keeps one id-to-name table on the
 * C side (c/harness_hooks.h) valid for every core. */
let hw_dmiss : bits(8) = 0xA0
let hw_imiss : bits(8) = 0xA1
let hw_dcmp  : bits(8) = 0xA2
let hw_icmp  : bits(8) = 0xA3
let hw_hash1 : bits(8) = 0xA4
let hw_hash2 : bits(8) = 0xA5
let hw_rpa   : bits(8) = 0xA6

$endif
