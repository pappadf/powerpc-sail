/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p604_regs.sail — PowerPC 604-specific registers.
 * Reference: MPC604UM §2.1.2 and Table 2-43.
 *
 * The shared post-601 registers — time base, split BAT arrays, HID0, IABR —
 * are in cores/common/ppc32_regs.sail, and the DABR is in
 * cores/common/ppc32_dabr.sail.
 *
 * The 604 has NO HID1: Table 2-43 lists its whole implementation-specific SPR
 * set and HID1 is not in it (the 604e adds one). */

$ifndef _P604_REGS
$define _P604_REGS

/* --- Processor identification register (SPR 1023, §2.1.2.2) -------------- */

/* "A 32-bit register that holds a processor identification tag in the four
 * least significant bits (PIR[28-31])"; the tag distinguishes processors in a
 * multiprocessor system and is used as a "bus transaction from" tag for
 * direct-store operations.  Nothing in this single-processor, bus-less model
 * reads it, so it is state a program can set and read back and nothing more.
 * TODO: only the 4-bit field exists; the other bits should read zero. */
register PIR : word

/* --- Performance monitor (§9.1, Table 9-1) ------------------------------- */

/* MMCR0 selects what is counted and whether a counter going negative raises
 * the performance monitor interrupt at 0x00F00; PMC1 and PMC2 are the
 * counters; SIA and SDA capture the instruction and data addresses current
 * when the interrupt condition arose.
 *
 * NOTHING IS COUNTED HERE.  Every event MMCR0 can select — cache misses,
 * dispatched instructions, bus transactions, branch mispredictions — is a
 * property of the pipeline and the memory hierarchy, and this model has
 * neither: it completes one instruction at a time against flat memory.  So
 * the counters never move on their own and the 0x00F00 interrupt never fires
 * from a counter going negative.
 *
 * They are modelled as plain read/write registers so that mfspr and mtspr
 * behave as Table 2-43 says, which is what a program that saves and restores
 * them across a context switch depends on.  This is a KNOWN DIVERGENCE, and
 * the same one the 604e and 750 carry.
 * TODO: MMCR0's reserved and read-only fields are not masked. */
register MMCR0 : word
register PMC1 : word
register PMC2 : word
register SIA : word
register SDA : word

/* --- Harness register ids for the 604's own registers -------------------- */

/* cores/common/ppc32_regs.sail takes 0x80-0x9F, including the reserved ids
 * hw_pir and hw_dabr this core uses; a core directory starts at 0xA0. */
let hw_mmcr0 : bits(8) = 0xA0
let hw_pmc1  : bits(8) = 0xA1
let hw_pmc2  : bits(8) = 0xA2
let hw_sia   : bits(8) = 0xA3
let hw_sda   : bits(8) = 0xA4

$endif
