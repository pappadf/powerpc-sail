/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* harness_hooks.h — C prototypes for the observation hooks declared in
 * model/ppc_harness.sail.
 *
 * `sail -c` emits calls to these but no declarations for them (an `extern`
 * val is the model saying "someone else supplies this"), so every build must
 * link exactly one implementation:
 *
 *   c/harness_hooks_noop.c   does nothing   — the emulator and anything else
 *   c/harness.c              records        — the single-step test harness
 *
 * Argument types follow the Sail declaration: bits(8)/bits(32) become fbits,
 * unit becomes `unit` (see sail.h).
 */

#ifndef PPC_HARNESS_HOOKS_H
#define PPC_HARNESS_HOOKS_H

#include "sail.h"

/* Must match the `let harness_mem_*` constants in model/ppc_harness.sail. */
#define HARNESS_MEM_READ       0
#define HARNESS_MEM_WRITE      1
#define HARNESS_MEM_FETCH      2
#define HARNESS_MEM_WALK_READ  3
#define HARNESS_MEM_WALK_WRITE 4

/* Must match the `let hw_*` register ids in model/ppc_harness.sail (the
 * architected common set) and in model/cores/<core>/<core>_regs.sail (0x80
 * and up, the core's own).  A single flat id space so that a hook call is one
 * array index on this side. */
#define HW_GPR0        0x00   /* .. 0x1F */
#define HW_FPR0        0x20   /* .. 0x3F */
#define HW_SR0         0x40   /* .. 0x4F */
#define HW_CR          0x50
#define HW_XER         0x51
#define HW_FPSCR       0x52
#define HW_CIA         0x53
#define HW_NIA         0x54
#define HW_LR          0x55
#define HW_CTR         0x56
#define HW_MSR         0x57
#define HW_SRR0        0x58
#define HW_SRR1        0x59
#define HW_DAR         0x5A
#define HW_DSISR       0x5B
#define HW_SPRG0       0x5C   /* .. 0x5F */
#define HW_DEC         0x60
#define HW_SDR1        0x61
#define HW_EAR         0x62
#define HW_RESERVATION 0x63

/* The 0x80-and-up half is the CORE's, and it is NOT one numbering: each core
 * defines the ids for the registers it has, so the same number means
 * different things under different CORE values.  A driver therefore has to
 * know which core it is talking to before it can name a high id — which it
 * does already, since the register SET differs too.
 *
 * p601 (model/cores/p601/p601_regs.sail). */
#define HW_P601_MQ     0x80
#define HW_P601_RTCU   0x81
#define HW_P601_RTCL   0x82
#define HW_P601_HID0   0x83
#define HW_P601_HID1   0x84
#define HW_P601_IABR   0x85
#define HW_P601_DABR   0x86
#define HW_P601_PIR    0x87
#define HW_P601_BATU0  0x88   /* .. 0x8B */
#define HW_P601_BATL0  0x8C   /* .. 0x8F */

/* The shared post-601 layer (model/cores/common/ppc32_regs.sail), used by
 * p603, p604, p604e and p750.  It takes 0x80-0x9F and reserves an id for each
 * register name even where no single core has all of them, so that this table
 * is valid for every one of the four. */
#define HW_TBU         0x80
#define HW_TBL         0x81
#define HW_HID0        0x82
#define HW_HID1        0x83   /* p603, p604e, p750 (the 604 has no HID1)   */
#define HW_IABR        0x84
#define HW_DABR        0x85   /* p604, p604e, p750 (the 603 has no DABR)   */
#define HW_PIR         0x86   /* p604, p604e (the 603 and 750 have no PIR) */
#define HW_IBATU0      0x88   /* .. 0x8B */
#define HW_IBATL0      0x8C   /* .. 0x8F */
#define HW_DBATU0      0x90   /* .. 0x93 */
#define HW_DBATL0      0x94   /* .. 0x97 */

/* p603 (model/cores/p603/p603_regs.sail) — the software table search
 * registers.  A core directory starts at 0xA0. */
#define HW_P603_DMISS  0xA0
#define HW_P603_IMISS  0xA1
#define HW_P603_DCMP   0xA2
#define HW_P603_ICMP   0xA3
#define HW_P603_HASH1  0xA4
#define HW_P603_HASH2  0xA5
#define HW_P603_RPA    0xA6

/* p604 and p604e (model/cores/p604{,e}/p604{,e}_regs.sail) — the performance
 * monitor.  The first five are numbered alike on both; MMCR1/PMC3/PMC4 are the
 * 604e's addition. */
#define HW_MMCR0       0xA0
#define HW_PMC1        0xA1
#define HW_PMC2        0xA2
#define HW_SIA         0xA3
#define HW_SDA         0xA4   /* p604, p604e (the 750 has no SDA)          */
#define HW_MMCR1       0xA5
#define HW_PMC3        0xA6
#define HW_PMC4        0xA7

/* p750 (model/cores/p750/p750_regs.sail) — the same performance monitor ids
 * as above, minus SDA at 0xA4, plus the L2 and thermal registers.  The user
 * mirrors (UMMCRn, UPMCn, USIA) are reads of the registers above and are not
 * separate state, so they have no ids. */
#define HW_P750_L2CR   0xA8
#define HW_P750_THRM1  0xA9
#define HW_P750_THRM2  0xAA
#define HW_P750_THRM3  0xAB
#define HW_P750_ICTC   0xAC

#define HW_ID_COUNT    0x100

unit harness_note_mem(const fbits kind, const fbits addr, const fbits width);
unit harness_note_exception(const fbits vector);
unit harness_note_write(const fbits reg, const fbits mask);

#endif
