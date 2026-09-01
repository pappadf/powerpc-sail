/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p604e_regs.sail — PowerPC 604e-specific registers.
 * Reference: MPC604EUM §2.1.2 and Table 2-48.
 *
 * WHAT THE 604e ADDS TO THE 604, in architected state: a HID1, and four more
 * performance monitor registers (MMCR1, PMC3, PMC4).  Everything else in the
 * programming model is the 604's — same MSR set including PM, same PVR field
 * layout with a different version, same exceptions, same MMU.  The
 * differences the manual spends its length on (bigger caches, the branch
 * target address cache, clocking) are microarchitecture this model does not
 * represent.
 *
 * The shared post-601 registers are in cores/common/ppc32_regs.sail and the
 * DABR in cores/common/ppc32_dabr.sail. */

$ifndef _P604E_REGS
$define _P604E_REGS

/* --- HID1 (SPR 1009, §2.1.2.4) ------------------------------------------- */

/* "This register, which is not implemented in the 604, is used to display the
 * PLL configuration": four read-only PLL_CFG bits reporting the
 * processor/bus clock ratio.  A clock ratio has no meaning in a model with no
 * clock, so this reads back what was written rather than reporting anything.
 * TODO: the bits are read-only on hardware and writable here. */
register HID1 : word

/* --- Processor identification register (SPR 1023, §2.1.2.3) -------------- */

register PIR : word

/* --- Performance monitor (§9.1, Table 9-1) ------------------------------- */

/* The 604's MMCR0/PMC1/PMC2/SIA/SDA plus MMCR1, PMC3 and PMC4.  As on the
 * 604, nothing is counted — see the note in cores/p604/p604_regs.sail, which
 * argues why, and which applies here unchanged. */
register MMCR0 : word
register MMCR1 : word
register PMC1 : word
register PMC2 : word
register PMC3 : word
register PMC4 : word
register SIA : word
register SDA : word

/* --- Harness register ids for the 604e's own registers ------------------- */

/* HID1, PIR and DABR use the ids cores/common/ppc32_regs.sail reserves for
 * them; a core directory starts at 0xA0.  The first five match the 604's
 * numbering so that a consumer handling both cores sees one scheme. */
let hw_mmcr0 : bits(8) = 0xA0
let hw_pmc1  : bits(8) = 0xA1
let hw_pmc2  : bits(8) = 0xA2
let hw_sia   : bits(8) = 0xA3
let hw_sda   : bits(8) = 0xA4
let hw_mmcr1 : bits(8) = 0xA5
let hw_pmc3  : bits(8) = 0xA6
let hw_pmc4  : bits(8) = 0xA7

$endif
