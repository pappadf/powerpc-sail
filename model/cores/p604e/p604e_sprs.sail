/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p604e_sprs.sail — SPR map clauses for 604e-specific registers.
 * Reference: MPC604EUM Table 2-48, which lists this core's whole
 * implementation-specific set: MMCR0, MMCR1, PMC1-PMC4, SIA, SDA, IABR and
 * PIR, plus the HID1 of §2.1.2.4.  IABR and HID0 are in
 * cores/common/ppc32_sprs.sail and the DABR in
 * cores/common/ppc32_dabr.sail. */

$ifndef _P604E_SPRS
$define _P604E_SPRS

/* 952-959 — the performance monitor, all supervisor-level.  The three
 * numbers the 604 leaves unimplemented (956 MMCR1, 957 PMC3, 958 PMC4) are
 * the 604e's addition. */
function clause read_spr(0b1110111000 /* 952 MMCR0 */) = Some(MMCR0)
function clause write_spr(0b1110111000, v) = { harness_wrote(hw_mmcr0); MMCR0 = v; true }

function clause read_spr(0b1110111001 /* 953 PMC1 */) = Some(PMC1)
function clause write_spr(0b1110111001, v) = { harness_wrote(hw_pmc1); PMC1 = v; true }

function clause read_spr(0b1110111010 /* 954 PMC2 */) = Some(PMC2)
function clause write_spr(0b1110111010, v) = { harness_wrote(hw_pmc2); PMC2 = v; true }

function clause read_spr(0b1110111011 /* 955 SIA */) = Some(SIA)
function clause write_spr(0b1110111011, v) = { harness_wrote(hw_sia); SIA = v; true }

function clause read_spr(0b1110111100 /* 956 MMCR1 */) = Some(MMCR1)
function clause write_spr(0b1110111100, v) = { harness_wrote(hw_mmcr1); MMCR1 = v; true }

function clause read_spr(0b1110111101 /* 957 PMC3 */) = Some(PMC3)
function clause write_spr(0b1110111101, v) = { harness_wrote(hw_pmc3); PMC3 = v; true }

function clause read_spr(0b1110111110 /* 958 PMC4 */) = Some(PMC4)
function clause write_spr(0b1110111110, v) = { harness_wrote(hw_pmc4); PMC4 = v; true }

function clause read_spr(0b1110111111 /* 959 SDA */) = Some(SDA)
function clause write_spr(0b1110111111, v) = { harness_wrote(hw_sda); SDA = v; true }

/* 1009 HID1 — PLL configuration read-back (§2.1.2.4), not present on the
 * 604. */
function clause read_spr(0b1111110001 /* 1009 HID1 */) = Some(HID1)
function clause write_spr(0b1111110001, v) = { harness_wrote(hw_hid1); HID1 = v; true }

/* 1023 PIR (§2.1.2.3). */
function clause read_spr(0b1111111111 /* 1023 PIR */) = Some(PIR)
function clause write_spr(0b1111111111, v) = { harness_wrote(hw_pir); PIR = v; true }

$endif
