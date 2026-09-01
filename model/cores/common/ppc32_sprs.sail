/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc32_sprs.sail — SPR map clauses shared by the 603e, 604, 604e and 750:
 * the time base, the split BAT arrays, HID0 and the IABR.  Registers only
 * some of the four have (DABR, PIR, HID1, the performance monitor, the 603e's
 * table search registers, the 750's L2 and thermal registers) are in the core
 * directory that has them.
 *
 * Reference: MPCFPE32B §2.3.12 and §7.5; MPC603EUM Figure 2-1 and Table 2-40;
 * MPC604UM Figure 2-1 and Table 2-43; MPC750UM Table 2-48. */

$ifndef _PPC32_SPRS
$define _PPC32_SPRS

/* --- Time base (MPCFPE32B §2.3.12, MPC750UM Table 2-48) ------------------ */

/* Dual-numbered, and asymmetrically so: 268/269 READ (user-level, and also
 * what mftb names), 284/285 WRITE (supervisor).  "The TB registers ... can be
 * written to using the mtspr instruction in supervisor mode and the TBR
 * numbers here.  The TB registers can be read in user mode using either the
 * mftb or mtspr instruction and specifying TBR 268 for TBL and TBR 269 for
 * TBU" (MPC750UM Table 2-48 note 2).
 *
 * So there is deliberately no write clause for 268/269 and no read clause for
 * 284/285; each missing direction takes the unimplemented-SPR path, which is
 * a no-op for the user-level numbers and, since 284/285 have SPR[0] set, a
 * privileged program exception for a user-mode mfspr naming them.  This is
 * the same shape as the 601's RTC (cores/p601/p601_sprs.sail) — the facility
 * changed but the dual-numbering trick did not. */
function clause read_spr(0b0100001100 /* 268 TBL read */) = Some(TBL)
function clause read_spr(0b0100001101 /* 269 TBU read */) = Some(TBU)

function clause write_spr(0b0100011100 /* 284 TBL write */, v) = { harness_wrote(hw_tbl); TBL = v; true }
function clause write_spr(0b0100011101 /* 285 TBU write */, v) = { harness_wrote(hw_tbu); TBU = v; true }

/* --- Block address translation registers (§7.5.3) ------------------------ */

/* 528-535 IBAT0U..IBAT3L, 536-543 DBAT0U..DBAT3L.  Every bit is kept as
 * written; the reserved fields (upper 15-18, lower 15-24 and 29) are not
 * masked here.
 * TODO: per-core reserved-bit masks, as for the 601's BATs.
 * A BAT write invalidates TLB entries on hardware; no TLB is modelled here,
 * so there is nothing to invalidate. */
function clause read_spr(0b1000010000 /* 528 IBAT0U */) = Some(IBATU[0])
function clause write_spr(0b1000010000, v) = { harness_wrote(hw_ibatu0 + 0x00); IBATU[0] = v; true }
function clause read_spr(0b1000010001 /* 529 IBAT0L */) = Some(IBATL[0])
function clause write_spr(0b1000010001, v) = { harness_wrote(hw_ibatl0 + 0x00); IBATL[0] = v; true }
function clause read_spr(0b1000010010 /* 530 IBAT1U */) = Some(IBATU[1])
function clause write_spr(0b1000010010, v) = { harness_wrote(hw_ibatu0 + 0x01); IBATU[1] = v; true }
function clause read_spr(0b1000010011 /* 531 IBAT1L */) = Some(IBATL[1])
function clause write_spr(0b1000010011, v) = { harness_wrote(hw_ibatl0 + 0x01); IBATL[1] = v; true }
function clause read_spr(0b1000010100 /* 532 IBAT2U */) = Some(IBATU[2])
function clause write_spr(0b1000010100, v) = { harness_wrote(hw_ibatu0 + 0x02); IBATU[2] = v; true }
function clause read_spr(0b1000010101 /* 533 IBAT2L */) = Some(IBATL[2])
function clause write_spr(0b1000010101, v) = { harness_wrote(hw_ibatl0 + 0x02); IBATL[2] = v; true }
function clause read_spr(0b1000010110 /* 534 IBAT3U */) = Some(IBATU[3])
function clause write_spr(0b1000010110, v) = { harness_wrote(hw_ibatu0 + 0x03); IBATU[3] = v; true }
function clause read_spr(0b1000010111 /* 535 IBAT3L */) = Some(IBATL[3])
function clause write_spr(0b1000010111, v) = { harness_wrote(hw_ibatl0 + 0x03); IBATL[3] = v; true }

function clause read_spr(0b1000011000 /* 536 DBAT0U */) = Some(DBATU[0])
function clause write_spr(0b1000011000, v) = { harness_wrote(hw_dbatu0 + 0x00); DBATU[0] = v; true }
function clause read_spr(0b1000011001 /* 537 DBAT0L */) = Some(DBATL[0])
function clause write_spr(0b1000011001, v) = { harness_wrote(hw_dbatl0 + 0x00); DBATL[0] = v; true }
function clause read_spr(0b1000011010 /* 538 DBAT1U */) = Some(DBATU[1])
function clause write_spr(0b1000011010, v) = { harness_wrote(hw_dbatu0 + 0x01); DBATU[1] = v; true }
function clause read_spr(0b1000011011 /* 539 DBAT1L */) = Some(DBATL[1])
function clause write_spr(0b1000011011, v) = { harness_wrote(hw_dbatl0 + 0x01); DBATL[1] = v; true }
function clause read_spr(0b1000011100 /* 540 DBAT2U */) = Some(DBATU[2])
function clause write_spr(0b1000011100, v) = { harness_wrote(hw_dbatu0 + 0x02); DBATU[2] = v; true }
function clause read_spr(0b1000011101 /* 541 DBAT2L */) = Some(DBATL[2])
function clause write_spr(0b1000011101, v) = { harness_wrote(hw_dbatl0 + 0x02); DBATL[2] = v; true }
function clause read_spr(0b1000011110 /* 542 DBAT3U */) = Some(DBATU[3])
function clause write_spr(0b1000011110, v) = { harness_wrote(hw_dbatu0 + 0x03); DBATU[3] = v; true }
function clause read_spr(0b1000011111 /* 543 DBAT3L */) = Some(DBATL[3])
function clause write_spr(0b1000011111, v) = { harness_wrote(hw_dbatl0 + 0x03); DBATL[3] = v; true }

/* --- Implementation-dependent registers ---------------------------------- */

/* 1008 HID0 — a plain word here; see the note on the register declaration in
 * ppc32_regs.sail for why none of its bits is broken out. */
function clause read_spr(0b1111110000 /* 1008 HID0 */) = Some(HID0)
function clause write_spr(0b1111110000, v) = { harness_wrote(hw_hid0); HID0 = v; true }

/* 1010 IABR — instruction address breakpoint (MPC603EUM Table 2-8,
 * MPC604UM Table 2-4, MPC750UM Table 2-3). */
function clause read_spr(0b1111110010 /* 1010 IABR */) = Some(IABR.bits)
function clause write_spr(0b1111110010, v) = { harness_wrote(hw_iabr); IABR = Mk_Ppc32_Iabr(v); true }

$endif
