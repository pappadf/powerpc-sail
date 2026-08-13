/* testlib.h — assembler macros shared by powerpc-sail test programs.
 *
 * Include from a .S file (which the cross compiler runs through cpp):
 *
 *     #include "testlib.h"
 *             .text
 *             .globl _start
 *     _start: ...
 *             HALT(0)
 */

#ifndef TESTLIB_H
#define TESTLIB_H

/* Stop the emulator with `status` as the exit status.  This is the model's
 * exit convention: sc with 0x4600_0D1E in r0 halts instead of taking a
 * system call exception (see model/ppc_debug.sail).  r0 and r3 are
 * clobbered, so a
 * test must have finished checking them by this point. */
#define HALT(status)      \
	lis	0, 0x4600;    \
	ori	0, 0, 0x0D1E; \
	li	3, status;    \
	sc

#endif /* TESTLIB_H */
