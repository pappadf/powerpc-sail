/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* harness_cov.h — the coverage-build half of the single-step harness.
 * Implemented in harness_cov.c; only linked into build/ppc_<core>_harness_cov.
 */

#ifndef PPC_HARNESS_COV_H
#define PPC_HARNESS_COV_H

/* Read a `sail -c --c-coverage` .branches file just to learn how many
 * function, branch and branch-target ids the model has, so that every
 * per-step bitmap line comes out the same width.  Optional. */
void ppc_cov_presize(const char *branches_file);

/* Append one line per STEP to this file. */
void ppc_cov_set_per_step(const char *path);

/* Write the accumulated coverage to this file at exit, in the same format the
 * stock libsail_coverage.a produces (so `sailcov` can read it). */
void ppc_cov_set_output(const char *path);

void ppc_cov_step_begin(void);
void ppc_cov_step_end(unsigned long step_index);
void ppc_cov_finish(void);

#endif
