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
#define HARNESS_MEM_READ  0
#define HARNESS_MEM_WRITE 1
#define HARNESS_MEM_FETCH 2

unit harness_note_mem(const fbits kind, const fbits addr, const fbits width);
unit harness_note_exception(const fbits vector);

#endif
