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

/* p601 (model/cores/p601/p601_regs.sail). */
#define HW_MQ          0x80
#define HW_RTCU        0x81
#define HW_RTCL        0x82
#define HW_HID0        0x83
#define HW_HID1        0x84
#define HW_IABR        0x85
#define HW_DABR        0x86
#define HW_PIR         0x87
#define HW_BATU0       0x88   /* .. 0x8B */
#define HW_BATL0       0x8C   /* .. 0x8F */

#define HW_ID_COUNT    0x100

unit harness_note_mem(const fbits kind, const fbits addr, const fbits width);
unit harness_note_exception(const fbits vector);
unit harness_note_write(const fbits reg, const fbits mask);

#endif
