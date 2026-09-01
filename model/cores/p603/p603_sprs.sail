/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p603_sprs.sail — SPR map clauses for 603-specific registers.
 * Reference: MPC603EUM Table 2-40 (implementation-specific SPR encodings) and
 * §2.1.2.  The shared post-601 SPRs — time base, IBAT/DBAT, HID0, IABR — are
 * in cores/common/ppc32_sprs.sail. */

$ifndef _P603_SPRS
$define _P603_SPRS

/* 976-982 — the software table search registers (§2.1.2.2 - §2.1.2.5).
 *
 * HASH1 and HASH2 are READ-ONLY: "these read-only registers are constructed
 * from the DMISS or IMISS contents" (§2.1.2.4), so they get no write clause
 * and an mtspr naming one takes the unimplemented-encoding no-op path.  The
 * other five are "read and write to the software" and get both.
 *
 * All seven have SPR[0] set, so they are supervisor-level and a user-mode
 * access is a privileged program exception (handled in mfspr/mtspr). */
function clause read_spr(0b1111010000 /* 976 DMISS */) = Some(DMISS)
function clause write_spr(0b1111010000, v) = { harness_wrote(hw_dmiss); DMISS = v; true }

function clause read_spr(0b1111010001 /* 977 DCMP */) = Some(DCMP)
function clause write_spr(0b1111010001, v) = { harness_wrote(hw_dcmp); DCMP = v; true }

function clause read_spr(0b1111010010 /* 978 HASH1 */) = Some(HASH1)

function clause read_spr(0b1111010011 /* 979 HASH2 */) = Some(HASH2)

function clause read_spr(0b1111010100 /* 980 IMISS */) = Some(IMISS)
function clause write_spr(0b1111010100, v) = { harness_wrote(hw_imiss); IMISS = v; true }

function clause read_spr(0b1111010101 /* 981 ICMP */) = Some(ICMP)
function clause write_spr(0b1111010101, v) = { harness_wrote(hw_icmp); ICMP = v; true }

function clause read_spr(0b1111010110 /* 982 RPA */) = Some(RPA)
function clause write_spr(0b1111010110, v) = { harness_wrote(hw_rpa); RPA = v; true }

/* 1009 HID1 — PLL configuration read-back (§2.1.2.1). */
function clause read_spr(0b1111110001 /* 1009 HID1 */) = Some(HID1)
function clause write_spr(0b1111110001, v) = { harness_wrote(hw_hid1); HID1 = v; true }

/* NOT implemented on the 603 (fall through to the wildcard clauses -> no-op /
 * privileged-encoding program exception): DABR (1013), PIR (1023), and the
 * performance monitor registers the 604 and 750 have.  Table 2-40 lists the
 * whole implementation-specific set and none of them appears in it. */

$endif
