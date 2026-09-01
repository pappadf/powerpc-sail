/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p750_sprs.sail — SPR map clauses for 750-specific registers.
 * Reference: MPC750UM Table 2-48 and §2.1.2.  IABR and HID0 are in
 * cores/common/ppc32_sprs.sail and the DABR in
 * cores/common/ppc32_dabr.sail. */

$ifndef _P750_SPRS
$define _P750_SPRS

/* --- Performance monitor, supervisor numbers (§2.1.2.4) ------------------ */

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

/* 959 SDA is NOT implemented on this core (§2.1.2.4 lists SIA alone), so it
 * is deliberately absent and takes the unimplemented-SPR path. */

/* --- Performance monitor, user-level mirrors (SPRs 936-942) -------------- */

/* "The contents of the PMC1-PMC4 are reflected to UPMC1-UPMC4, which can be
 * READ by user-level software" (§2.1.2.4.6), and the same for UMMCR0/UMMCR1
 * and USIA.  READ ONLY, hence no write clauses: an mtspr naming one of these
 * numbers takes the unimplemented-encoding no-op path.
 *
 * These numbers have SPR[0] CLEAR, so spr_is_privileged is false for them and
 * a user-mode mfspr reaches the clause — which is the whole point of the
 * mirrors, and is exactly the mechanism the 601 uses to make the RTC
 * user-readable at 4/5 while it is written at 20/21.
 *
 * They return the supervisor registers themselves rather than copies, so the
 * mirroring cannot drift. */
function clause read_spr(0b1110101000 /* 936 UMMCR0 */) = Some(MMCR0)
function clause read_spr(0b1110101001 /* 937 UPMC1  */) = Some(PMC1)
function clause read_spr(0b1110101010 /* 938 UPMC2  */) = Some(PMC2)
function clause read_spr(0b1110101011 /* 939 USIA   */) = Some(SIA)
function clause read_spr(0b1110101100 /* 940 UMMCR1 */) = Some(MMCR1)
function clause read_spr(0b1110101101 /* 941 UPMC3  */) = Some(PMC3)
function clause read_spr(0b1110101110 /* 942 UPMC4  */) = Some(PMC4)

/* --- Implementation-dependent registers ---------------------------------- */

/* 1009 HID1 — PLL configuration read-back (§2.1.2.2). */
function clause read_spr(0b1111110001 /* 1009 HID1 */) = Some(HID1)
function clause write_spr(0b1111110001, v) = { harness_wrote(hw_hid1); HID1 = v; true }

/* 1017 L2CR — L2 cache control (§2.1.5). */
function clause read_spr(0b1111111001 /* 1017 L2CR */) = Some(L2CR)
function clause write_spr(0b1111111001, v) = { harness_wrote(hw_l2cr); L2CR = v; true }

/* 1019 ICTC — instruction cache throttling control (§2.1.2.6). */
function clause read_spr(0b1111111011 /* 1019 ICTC */) = Some(ICTC)
function clause write_spr(0b1111111011, v) = { harness_wrote(hw_ictc); ICTC = v; true }

/* 1020-1022 THRM1-THRM3 — thermal assist unit (§2.1.2.5). */
function clause read_spr(0b1111111100 /* 1020 THRM1 */) = Some(THRM1)
function clause write_spr(0b1111111100, v) = { harness_wrote(hw_thrm1); THRM1 = v; true }

function clause read_spr(0b1111111101 /* 1021 THRM2 */) = Some(THRM2)
function clause write_spr(0b1111111101, v) = { harness_wrote(hw_thrm2); THRM2 = v; true }

function clause read_spr(0b1111111110 /* 1022 THRM3 */) = Some(THRM3)
function clause write_spr(0b1111111110, v) = { harness_wrote(hw_thrm3); THRM3 = v; true }

/* NOT implemented on the 750 (fall through to the wildcard clauses -> no-op /
 * privileged-encoding program exception): PIR (1023), SDA (959), and the
 * 603's software table search registers (976-982) — the 750 reloads its TLBs
 * in hardware, and it is the MPC755, not the MPC750, that has those
 * (§C.4.3). */

$endif
