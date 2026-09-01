/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p750_regs.sail — PowerPC 750 (G3) specific registers.
 * Reference: MPC750UM Table 1-3 and §2.1.2.
 *
 * The shared post-601 registers — time base, split BAT arrays, HID0, IABR —
 * are in cores/common/ppc32_regs.sail, and the DABR in
 * cores/common/ppc32_dabr.sail.
 *
 * The 750 has no PIR: Table 1-3 lists its whole implementation-specific set
 * and the processor identification register is not in it, unlike the 604 and
 * 604e. */

$ifndef _P750_REGS
$define _P750_REGS

/* --- HID1 (SPR 1009, §2.1.2.2) ------------------------------------------- */

/* "Allows software to read the configuration of the PLL configuration
 * signals" (Table 1-3) — four read-only PLL_CFG bits, as on the 604e.  A
 * clock ratio has no meaning in a model with no clock.
 * TODO: read-only on hardware, writable here. */
register HID1 : word

/* --- L2 cache control register (SPR 1017, §2.1.5) ------------------------ */

/* Configures and operates the L2 cache: enable, size, RAM type, clock ratio,
 * parity, and the global-invalidate handshake (Table 2-18).  This model has
 * no cache of any level, so no bit of it changes what is computed; it is
 * state a program can set and read back.
 * "It is cleared by a hard reset or power-on reset" (§2.1.5), which is why
 * core_reset zeroes it rather than leaving it undefined. */
register L2CR : word

/* --- Thermal assist unit (SPRs 1020-1022, §2.1.2.5) ---------------------- */

/* THRM1 and THRM2 each hold a junction-temperature threshold and the controls
 * that compare the on-chip sensor against it; THRM3 enables the unit and sets
 * the sample interval.  A temperature crossing raises the thermal management
 * interrupt at 0x01700.
 *
 * NOTHING IS SENSED HERE.  There is no junction and no temperature, so the
 * comparison never happens and the 0x01700 interrupt never fires — the same
 * shape of divergence as the performance monitor below.  The registers are
 * plain state so that mfspr and mtspr behave as Table 2-48 says. */
register THRM1 : word
register THRM2 : word
register THRM3 : word

/* --- Instruction cache throttling control (SPR 1019, §2.1.2.6) ----------- */

/* Controls the interval at which instructions are fetched into the
 * instruction buffer, to hold the junction temperature down.  Fetch rate is
 * not modelled; plain state. */
register ICTC : word

/* --- Performance monitor (§2.1.2.4, §4.5.13) ----------------------------- */

/* MMCR0/MMCR1 select what is counted, PMC1-PMC4 count it, and SIA captures
 * the address current when the interrupt condition arose.  As on the 604 and
 * 604e nothing is counted — see the note in cores/p604/p604_regs.sail, which
 * argues why and applies here unchanged.
 *
 * What the 750 adds over the 604e is a USER-READABLE MIRROR of each: UMMCR0,
 * UMMCR1, UPMC1-UPMC4 and USIA (SPRs 936-942), which "provide user-level read
 * access" to the supervisor registers.  They are mirrors, not separate state,
 * so there are no registers for them here — p750_sprs.sail routes the user
 * SPR numbers to the same registers, which is what makes the mirroring exact
 * by construction.
 *
 * The 750 has no SDA: Table 2-48 and §2.1.2.4 list SIA and no sampled DATA
 * address, unlike the 604 and 604e. */
register MMCR0 : word
register MMCR1 : word
register PMC1 : word
register PMC2 : word
register PMC3 : word
register PMC4 : word
register SIA : word

/* --- Harness register ids for the 750's own registers -------------------- */

/* HID1 and DABR use the ids cores/common/ppc32_regs.sail reserves for them;
 * a core directory starts at 0xA0. */
let hw_mmcr0 : bits(8) = 0xA0
let hw_pmc1  : bits(8) = 0xA1
let hw_pmc2  : bits(8) = 0xA2
let hw_sia   : bits(8) = 0xA3
let hw_mmcr1 : bits(8) = 0xA5
let hw_pmc3  : bits(8) = 0xA6
let hw_pmc4  : bits(8) = 0xA7
let hw_l2cr  : bits(8) = 0xA8
let hw_thrm1 : bits(8) = 0xA9
let hw_thrm2 : bits(8) = 0xAA
let hw_thrm3 : bits(8) = 0xAB
let hw_ictc  : bits(8) = 0xAC
  /* 0xA4 is deliberately skipped: it is the 604's SDA, which the 750 does not
   * have, and leaving the gap keeps the performance monitor ids aligned
   * across the three cores that have one. */

$endif
