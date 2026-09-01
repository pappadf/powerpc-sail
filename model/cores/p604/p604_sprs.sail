/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p604_sprs.sail — SPR map clauses for 604-specific registers.
 * Reference: MPC604UM Table 2-43, which lists this core's whole
 * implementation-specific set: MMCR0, PMC1, PMC2, SIA, SDA, IABR and PIR.
 * IABR and HID0 are in cores/common/ppc32_sprs.sail and the DABR is in
 * cores/common/ppc32_dabr.sail. */

$ifndef _P604_SPRS
$define _P604_SPRS

/* 952-959 — the performance monitor.  All supervisor-level (SPR[0] set); the
 * 604 has no user-readable mirrors, which the 750 adds. */
function clause read_spr(0b1110111000 /* 952 MMCR0 */) = Some(MMCR0)
function clause write_spr(0b1110111000, v) = { harness_wrote(hw_mmcr0); MMCR0 = v; true }

function clause read_spr(0b1110111001 /* 953 PMC1 */) = Some(PMC1)
function clause write_spr(0b1110111001, v) = { harness_wrote(hw_pmc1); PMC1 = v; true }

function clause read_spr(0b1110111010 /* 954 PMC2 */) = Some(PMC2)
function clause write_spr(0b1110111010, v) = { harness_wrote(hw_pmc2); PMC2 = v; true }

function clause read_spr(0b1110111011 /* 955 SIA */) = Some(SIA)
function clause write_spr(0b1110111011, v) = { harness_wrote(hw_sia); SIA = v; true }

function clause read_spr(0b1110111111 /* 959 SDA */) = Some(SDA)
function clause write_spr(0b1110111111, v) = { harness_wrote(hw_sda); SDA = v; true }

/* 1023 PIR (§2.1.2.2).  "Although the SPR number is defined by the OEA, the
 * register structure is defined by each implementation." */
function clause read_spr(0b1111111111 /* 1023 PIR */) = Some(PIR)
function clause write_spr(0b1111111111, v) = { harness_wrote(hw_pir); PIR = v; true }

/* NOT implemented on the 604 (fall through to the wildcard clauses -> no-op /
 * privileged-encoding program exception): HID1 (1009), MMCR1 (956), PMC3
 * (957) and PMC4 (958) — all four arrive with the 604e — and the 603's
 * software table search registers (976-982). */

$endif
