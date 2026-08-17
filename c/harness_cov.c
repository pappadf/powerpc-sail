/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* harness_cov.c — coverage runtime for the single-step harness.
 *
 * `sail -c --c-coverage <file>` instruments the generated C: every function
 * entry, every branch and every branch target calls out to one of the five
 * entry points declared in Sail's lib/sail_coverage.h, and <file> receives the
 * full list of instrumentable source locations with the ids used at run time.
 *
 * Sail ships an implementation of those five entry points as
 * lib/coverage/libsail_coverage.a.  We do not link it, for one reason: it
 * accumulates every location ever reached into a single global set and dumps
 * that set at exit.  That answers "what did the whole run cover?", but the
 * vector generator's set-cover loop asks "what did THIS instruction cover?",
 * which the stock library cannot answer at all — the sets are never reset and
 * there is no way to read them mid-run.
 *
 * So: same five entry points, two bitmaps each (one for the run, one for the
 * step just executed), plus a writer for each of the two questions.
 *
 *   --coverage-out FILE        accumulated, in the stock library's own format,
 *                              so `sailcov` reads it unchanged
 *   --coverage-per-step FILE   one line per STEP:
 *                                <step> F:<hex> B:<hex> T:<hex>
 *                              hex is a bitmap, bit i set = id i was reached
 *                              during that step, most significant nibble
 *                              first, ids counting up from 0.
 *
 * The ids are exactly the ones in the .branches file, and Sail allocates all
 * three spaces densely from 0, so a bitmap indexed by id is compact and
 * stable across runs of the same binary.  (Branch-target ids in particular
 * are globally unique, not per-branch, which is what makes T a flat bitmap
 * rather than a table of pairs.)  Pass --coverage-branches to fix the widths
 * from the start; otherwise each line is only as wide as the largest id seen
 * so far.
 *
 * Nothing here writes to stdout: the response stream stays exactly protocol
 * v1, whichever binary produced it.
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "harness_cov.h"

/* --- one bitmap kind ---------------------------------------------------- */

typedef struct {
  uint8_t *run;      /* set during the whole run                            */
  uint8_t *step;     /* set during the current STEP                         */
  size_t   cap;      /* bytes allocated in each                             */
  size_t   nbits;    /* high-water mark: (largest id seen) + 1              */
} bitmap_t;

static bitmap_t bm_f, bm_b, bm_t;

static void bm_grow(bitmap_t *m, size_t nbits)
{
  size_t need = (nbits + 7) / 8;
  if (need <= m->cap) return;
  size_t cap = m->cap ? m->cap : 64;
  while (cap < need) cap *= 2;
  m->run = realloc(m->run, cap);
  m->step = realloc(m->step, cap);
  if (!m->run || !m->step) { fprintf(stderr, "harness-cov: out of memory\n"); exit(1); }
  memset(m->run + m->cap, 0, cap - m->cap);
  memset(m->step + m->cap, 0, cap - m->cap);
  m->cap = cap;
}

static void bm_set(bitmap_t *m, int id)
{
  if (id < 0) return;
  size_t i = (size_t)id;
  bm_grow(m, i + 1);
  if (i + 1 > m->nbits) m->nbits = i + 1;
  m->run[i >> 3] |= (uint8_t)(1u << (i & 7));
  m->step[i >> 3] |= (uint8_t)(1u << (i & 7));
}

static void bm_clear_step(bitmap_t *m)
{
  if (m->cap) memset(m->step, 0, m->cap);
}

static void bm_write_hex(FILE *f, const bitmap_t *m)
{
  size_t nbytes = (m->nbits + 7) / 8;
  for (size_t i = 0; i < nbytes; i++)
    fprintf(f, "%02X", m->step[i]);
  if (nbytes == 0) fputc('0', f);
}

/* --- accumulated span sets, for the sailcov-format dump ----------------- */

/* The stock library keys its sets on the span (file, l1, c1, l2, c2) and
 * dedupes.  Ids do that for us: one span per id, so remembering the span the
 * first time an id is seen is enough, and the run bitmap says which to
 * print.  The `sail_file` strings are literals in the generated code, so
 * keeping the pointer is safe and free. */

typedef struct { const char *file; int l1, c1, l2, c2; } span_t;

typedef struct { span_t *v; size_t cap; } spans_t;

static spans_t sp_f, sp_b, sp_t;

static void sp_put(spans_t *s, int id, const char *file, int l1, int c1, int l2, int c2)
{
  if (id < 0) return;
  size_t i = (size_t)id;
  if (i >= s->cap) {
    size_t cap = s->cap ? s->cap : 256;
    while (cap <= i) cap *= 2;
    s->v = realloc(s->v, cap * sizeof *s->v);
    if (!s->v) { fprintf(stderr, "harness-cov: out of memory\n"); exit(1); }
    memset(s->v + s->cap, 0, (cap - s->cap) * sizeof *s->v);
    s->cap = cap;
  }
  s->v[i].file = file;
  s->v[i].l1 = l1; s->v[i].c1 = c1; s->v[i].l2 = l2; s->v[i].c2 = c2;
}

/* --- Sail's coverage entry points --------------------------------------- */

void sail_function_entry(int function_id, const char *function_name,
                         const char *sail_file, int l1, int c1, int l2, int c2)
{
  (void)function_name;
  bm_set(&bm_f, function_id);
  sp_put(&sp_f, function_id, sail_file, l1, c1, l2, c2);
}

void sail_branch_reached(int branch_id, const char *sail_file,
                         int l1, int c1, int l2, int c2)
{
  bm_set(&bm_b, branch_id);
  sp_put(&sp_b, branch_id, sail_file, l1, c1, l2, c2);
}

void sail_branch_target_taken(int branch_id, int branch_target_id,
                              const char *sail_file, int l1, int c1, int l2, int c2)
{
  (void)branch_id;
  bm_set(&bm_t, branch_target_id);
  sp_put(&sp_t, branch_target_id, sail_file, l1, c1, l2, c2);
}

/* Sail's own runtime declares these two; the model calls sail_set_coverage_file
 * through a function pointer in rts.c and sail_coverage_exit from its main(),
 * neither of which this binary uses.  Provided so the link succeeds and so
 * that a caller who does reach them gets the behaviour they expect. */
static const char *cov_out_path;

void sail_set_coverage_file(const char *output_file)
{
  cov_out_path = output_file;
}

int sail_coverage_exit(void);

/* --- the harness-facing API --------------------------------------------- */

static const char *per_step_path;
static FILE *per_step_file;

void ppc_cov_set_output(const char *path)
{
  cov_out_path = path;
}

void ppc_cov_set_per_step(const char *path)
{
  per_step_path = path;
  per_step_file = fopen(path, "w");
  if (!per_step_file) {
    fprintf(stderr, "harness-cov: cannot write %s\n", path);
    exit(1);
  }
}

/* Learn the id counts from a .branches file so that every per-step line is
 * the same width.  Lines look like
 *   F <id>, "name", "file", l1, c1, l2, c2
 *   B <id>, "file", l1, c1, l2, c2
 *   T <id>, <target-id>, "file", l1, c1, l2, c2
 * and only the leading kind and the ids matter here — for T it is the SECOND
 * number, the globally unique target id, that indexes the bitmap. */
void ppc_cov_presize(const char *branches_file)
{
  FILE *f = fopen(branches_file, "r");
  if (!f) {
    fprintf(stderr, "harness-cov: cannot read %s\n", branches_file);
    exit(1);
  }
  char line[4096];
  long max_f = -1, max_b = -1, max_t = -1;
  while (fgets(line, sizeof line, f)) {
    char kind = line[0];
    if (kind != 'F' && kind != 'B' && kind != 'T') continue;
    char *end;
    long a = strtol(line + 1, &end, 10);
    if (end == line + 1) continue;
    if (kind == 'F') { if (a > max_f) max_f = a; }
    else if (kind == 'B') { if (a > max_b) max_b = a; }
    else {
      while (*end == ',' || *end == ' ') end++;
      long b = strtol(end, NULL, 10);
      if (b > max_t) max_t = b;
    }
  }
  fclose(f);
  if (max_f >= 0) { bm_grow(&bm_f, (size_t)max_f + 1); bm_f.nbits = (size_t)max_f + 1; }
  if (max_b >= 0) { bm_grow(&bm_b, (size_t)max_b + 1); bm_b.nbits = (size_t)max_b + 1; }
  if (max_t >= 0) { bm_grow(&bm_t, (size_t)max_t + 1); bm_t.nbits = (size_t)max_t + 1; }
}

void ppc_cov_step_begin(void)
{
  if (!per_step_file) return;
  bm_clear_step(&bm_f);
  bm_clear_step(&bm_b);
  bm_clear_step(&bm_t);
}

void ppc_cov_step_end(unsigned long step_index)
{
  if (!per_step_file) return;
  fprintf(per_step_file, "%lu F:", step_index);
  bm_write_hex(per_step_file, &bm_f);
  fputs(" B:", per_step_file);
  bm_write_hex(per_step_file, &bm_b);
  fputs(" T:", per_step_file);
  bm_write_hex(per_step_file, &bm_t);
  fputc('\n', per_step_file);
}

/* The accumulated dump, byte-for-byte in the format libsail_coverage.a
 * produces: one line per reached location, kind then the span. */
static void dump_kind(FILE *f, char kind, const bitmap_t *m, const spans_t *s)
{
  for (size_t i = 0; i < m->nbits; i++) {
    if (!(m->run[i >> 3] & (1u << (i & 7)))) continue;
    if (i >= s->cap || !s->v[i].file) continue;
    fprintf(f, "%c \"%s\", %d, %d, %d, %d\n", kind, s->v[i].file,
            s->v[i].l1, s->v[i].c1, s->v[i].l2, s->v[i].c2);
  }
}

int sail_coverage_exit(void)
{
  if (!cov_out_path) return 0;
  FILE *f = fopen(cov_out_path, "a");
  if (!f) return 1;
  dump_kind(f, 'B', &bm_b, &sp_b);
  dump_kind(f, 'F', &bm_f, &sp_f);
  dump_kind(f, 'T', &bm_t, &sp_t);
  fclose(f);
  return 0;
}

void ppc_cov_finish(void)
{
  if (per_step_file) { fclose(per_step_file); per_step_file = NULL; }
  (void)per_step_path;
  sail_coverage_exit();
}
