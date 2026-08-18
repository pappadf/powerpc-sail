/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* harness_hooks_noop.c — the do-nothing implementation of the observation
 * hooks declared in model/ppc_harness.sail.
 *
 * This is what every build that is not a test harness links against, the
 * emulator above all: the hooks are pure observation, so discarding what they
 * report leaves the model bit-for-bit what it was before they existed.  At
 * -O2 each one is a `ret`, and the call is inlined away where the compiler
 * can see both sides.
 */

#include "harness_hooks.h"

unit harness_note_mem(const fbits kind, const fbits addr, const fbits width)
{
  (void)kind;
  (void)addr;
  (void)width;
  return UNIT;
}

unit harness_note_exception(const fbits vector)
{
  (void)vector;
  return UNIT;
}

unit harness_note_write(const fbits reg, const fbits mask)
{
  (void)reg;
  (void)mask;
  return UNIT;
}
