/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* harness.c — single-step test-vector harness.
 *
 * A second front end for the model, alongside the emulator in main.sail.  The
 * emulator runs a program to a halt; this runs ONE instruction at a time and
 * reports, exactly, what that instruction did: the whole architected state
 * afterwards, which state elements it wrote, and which physical addresses it
 * read, wrote and fetched.  That is what a test-vector generator needs and
 * what the emulator cannot give it.
 *
 * It is a C driver rather than Sail code because `sail -c` emits every
 * register as a plain C global and step() as a plain C function, so the whole
 * architected state can be read straight out of the globals with no model
 * change at all.  What the state cannot show is what the step DID: which
 * addresses it touched, whether it took an exception, and which registers it
 * wrote as opposed to which ones changed value.  Those come from the
 * observation hooks of model/ppc_harness.sail.
 *
 * PROTOCOL.  Line-oriented text on stdin, line-oriented text on stdout, many
 * vectors per process (starting a process per vector is far too slow for the
 * coverage-closure loop the generator runs).  Commands:
 *
 *   RESET                  zero all architected state, clear all memory
 *   SET <elem> <hex>       set one state element by its flat name
 *   MEM <addr> <hexbytes>  write bytes at a physical address
 *   OPCODE <hex>           place a 4-byte big-endian opcode at the current CIA
 *   STEP                   execute exactly one instruction; emit a response
 *   QUIT                   exit
 *
 * Blank lines and lines beginning with '#' are ignored.  SET and MEM
 * accumulate; STEP consumes them; state persists across STEP until a RESET.
 * Only STEP produces output, except that any malformed or unknown command
 * produces one `ERR <message>` line and is otherwise ignored — a bad line in
 * a batch of a million must not take the batch down.
 *
 * The response to STEP, in this order:
 *
 *   S <elem> <hex>         every state element, in the canonical order
 *   M <addr> <hexbytes>    every byte range whose contents the step changed
 *   FW <elem>              every state element the step wrote
 *   FMR <addr> <width>     every data read, width in bytes
 *   FMW <addr> <width>     every data write
 *   FF <addr> <width>      every instruction fetch
 *   FTR <addr> <width>     every page-table-walk read
 *   FTW <addr> <width>     every page-table-walk write (the R/C bits)
 *   EXC none | EXC <hex>   the vector of the exception taken, if any
 *   HALT <hex>             only if the step hit the emulator's halt convention
 *   DONE
 *
 * The full contract, the canonical element names, and the deviations this
 * implementation makes are documented in the powerpc-test project's
 * generator/HARNESS.md.
 *
 * WHY CIA AND NIA BEHAVE AS THEY DO.  step() begins with `CIA = NIA`, so the
 * address a step executes at is the one in NIA, not CIA.  `SET cia X`
 * therefore sets BOTH, which makes `cia` mean what a test vector means by it —
 * "the address of the instruction being tested" — while leaving step() itself
 * completely unmodified.  OPCODE places its bytes at NIA for the same reason:
 * equal to CIA in every ordinary use, and still right after a STEP, where CIA
 * has fallen behind.
 *
 * `nia` is reported in the write set unconditionally, because every step
 * writes it and a branch-to-self would otherwise hide that.  `cia` is reported
 * by diff like everything else; it normally does not appear, but it does when
 * an asynchronous interrupt is delivered, since check_interrupts() redirects
 * NIA to the vector BEFORE step() copies it into CIA.
 *
 * DETERMINISM.  Every source of non-determinism is switched off from here,
 * with no model change:
 *   - tick_ns = 0 makes core_tick() a complete no-op, freezing the RTC and the
 *     decrementer (see p601_core.sail: with no accumulated nanoseconds there
 *     are no ticks, so neither counter moves and no DEC exception is latched);
 *   - trace_enabled = false silences the per-instruction trace print;
 *   - step_limit = 0 and never calling run() means no step or cycle limit, and
 *     in particular cycle_limit_reached() — the only thing in the C runtime
 *     that counts anything across steps — is never called;
 *   - DEC_pending and ext_int_pending are cleared by RESET and only ever set
 *     by an explicit SET;
 *   - nothing here reads the clock, the environment, or an address.
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sail.h"
#include "rts.h"
#include "model.h"
#include "harness_hooks.h"

#ifdef PPC_HARNESS_COVERAGE
#include "harness_cov.h"
#endif

/* Globals the generated code and the C runtime define but do not declare in
 * any header: model_init/model_fini set up and tear down the model (sail's
 * own main() calls them, and --c-no-main takes that main away), and kill_mem
 * empties the runtime's sparse RAM. */
void model_init(void);
void model_fini(void);
void kill_mem(void);

/* ======================================================================= */
/* Output                                                                   */
/* ======================================================================= */

/* Hand-rolled, because a STEP response is ~150 short lines and printf would
 * dominate the measured throughput.  Flushed once per response so a caller
 * driving the harness synchronously through a pipe never deadlocks. */

static char obuf[1 << 16];
static size_t olen;

static void oflush_partial(void)
{
  if (olen) {
    fwrite(obuf, 1, olen, stdout);
    olen = 0;
  }
}

static void oreserve(size_t n)
{
  if (olen + n > sizeof obuf) oflush_partial();
}

static void oputs(const char *s)
{
  size_t n = strlen(s);
  if (n > sizeof obuf) { oflush_partial(); fwrite(s, 1, n, stdout); return; }
  oreserve(n);
  memcpy(obuf + olen, s, n);
  olen += n;
}

static void ochar(char c)
{
  oreserve(1);
  obuf[olen++] = c;
}

static const char HEXD[] = "0123456789ABCDEF";

/* Emit `nibbles` hex digits of v, most significant first. */
static void ohex(uint64_t v, int nibbles)
{
  oreserve((size_t)nibbles);
  for (int i = nibbles - 1; i >= 0; i--)
    obuf[olen++] = HEXD[(v >> (4 * i)) & 0xF];
}

static void ohex0x(uint64_t v, int nibbles)
{
  oputs("0x");
  ohex(v, nibbles);
}

static void odec(unsigned long v)
{
  char tmp[24];
  int n = 0;
  if (v == 0) tmp[n++] = '0';
  while (v) { tmp[n++] = (char)('0' + v % 10); v /= 10; }
  oreserve((size_t)n);
  while (n) obuf[olen++] = tmp[--n];
}

/* Errors go to stdout, in band, so a caller reading one stream sees them in
 * the right place relative to the responses they belong to. */
static void err(const char *msg, const char *detail)
{
  oputs("ERR ");
  oputs(msg);
  if (detail) { ochar(' '); oputs(detail); }
  ochar('\n');
  oflush_partial();
  fflush(stdout);
}

/* ======================================================================= */
/* The state-element table                                                  */
/* ======================================================================= */

/* One entry per flat element name of the canonical vocabulary, in the
 * canonical order — which is also the order S and FW lines come out in.
 *
 * Every element is a bit range of some uint64_t the generated model owns.
 * That is not a simplification: `sail -c` represents a 32-bit register, a
 * 64-bit FPR and a bitfield alike as a uint64_t (bitfield structs are a bare
 * `{ uint64_t zbits; }`), so a pointer plus a (lo, width) pair addresses
 * every one of them, including the sub-fields of CR, XER and FPSCR.  The two
 * exceptions are the register vectors, whose element addresses are only known
 * once model_init() has allocated them, and the booleans. */

enum { VS_NONE = 0, VS_GPR, VS_FPR, VS_SR, VS_BATU, VS_BATL };

typedef struct {
  const char *name;
  uint64_t   *slot;   /* backing word, for VS_NONE elements                */
  bool       *flag;   /* set instead of slot for boolean elements          */
  uint8_t     vec;    /* VS_*: which register vector, if any               */
  uint8_t     idx;    /* index within that vector                          */
  uint8_t     bits;   /* element width in bits                             */
  uint8_t     lo;     /* sail (dec) index of the element's lowest bit      */
  uint8_t     nib;    /* hex digits to print: ceil(bits / 4)               */
} elem_t;

#define MAX_ELEMS 192
static elem_t elems[MAX_ELEMS];
static int n_elems;
static char name_pool[MAX_ELEMS][16];

/* Elements outside the canonical vocabulary: settable, because the
 * determinism contract says the two interrupt latches are false "unless
 * explicitly SET", but deliberately NOT reported in S or FW, so that the
 * response stays exactly the canonical element list.  See HARNESS.md. */
#define MAX_EXTRA 8
static elem_t extra[MAX_EXTRA];
static int n_extra;

/* Indices into elems[] that the step logic needs by name. */
static int idx_cia = -1, idx_nia = -1;

static elem_t *push(elem_t *tab, int *n, int cap, const char *name)
{
  if (*n >= cap) { fprintf(stderr, "harness: element table overflow\n"); exit(1); }
  elem_t *e = &tab[(*n)++];
  memset(e, 0, sizeof *e);
  e->name = name;
  return e;
}

/* Generated names ("gpr7", "sr15", ...) need somewhere to live; one slot per
 * table entry, claimed before the entry is pushed. */
static char *pool_name(const char *prefix, int i)
{
  char *p = name_pool[n_elems];
  snprintf(p, sizeof name_pool[0], "%s%d", prefix, i);
  return p;
}

static void add_field(const char *name, uint64_t *slot, int hi, int lo)
{
  elem_t *e = push(elems, &n_elems, MAX_ELEMS, name);
  e->slot = slot;
  e->bits = (uint8_t)(hi - lo + 1);
  e->lo = (uint8_t)lo;
  e->nib = (uint8_t)((e->bits + 3) / 4);
}

static void add_reg(const char *name, uint64_t *slot)
{
  add_field(name, slot, 31, 0);
}

static void add_vec(const char *prefix, int i, int vs, int bits)
{
  char *nm = pool_name(prefix, i);
  elem_t *e = push(elems, &n_elems, MAX_ELEMS, nm);
  e->vec = (uint8_t)vs;
  e->idx = (uint8_t)i;
  e->bits = (uint8_t)bits;
  e->nib = (uint8_t)((bits + 3) / 4);
}

static void add_flag(const char *name, bool *flag)
{
  elem_t *e = push(elems, &n_elems, MAX_ELEMS, name);
  e->flag = flag;
  e->bits = 1;
  e->nib = 1;
}

static void add_extra_flag(const char *name, bool *flag)
{
  elem_t *e = push(extra, &n_extra, MAX_EXTRA, name);
  e->flag = flag;
  e->bits = 1;
  e->nib = 1;
}

/* CR field n is manual bits 4n..4n+3, i.e. sail bits 31-4n .. 28-4n; within
 * the field, bit 3 = LT, 2 = GT, 1 = EQ, 0 = SO (ppc_regs.sail). */
static void add_cr_field(int n)
{
  char *nm = pool_name("cr", n);
  add_field(nm, &zCR, 31 - 4 * n, 28 - 4 * n);
}

static void build_elem_table(void)
{
  for (int i = 0; i < 32; i++) add_vec("gpr", i, VS_GPR, 32);
  for (int i = 0; i < 32; i++) add_vec("fpr", i, VS_FPR, 64);
  for (int i = 0; i < 8; i++) add_cr_field(i);

  /* XER, Table 2-8 (bit numbers are sail/dec throughout). */
  add_field("xer.so",   &zXER.zbits, 31, 31);
  add_field("xer.ov",   &zXER.zbits, 30, 30);
  add_field("xer.ca",   &zXER.zbits, 29, 29);
  add_field("xer.cmpb", &zXER.zbits, 15,  8);
  add_field("xer.bc",   &zXER.zbits,  6,  0);

  /* FPSCR, Table 2-1.  fpcc is deliberately absent: it is fprf[3:0], and
   * naming an element that overlaps another would make the write-set
   * ambiguous.  Bits 9, 10 (VXSOFT/VXSQRT) and 2 are unimplemented on the
   * 601 and have no names. */
  add_field("fpscr.fx",     &zFPSCR.zbits, 31, 31);
  add_field("fpscr.fex",    &zFPSCR.zbits, 30, 30);
  add_field("fpscr.vx",     &zFPSCR.zbits, 29, 29);
  add_field("fpscr.ox",     &zFPSCR.zbits, 28, 28);
  add_field("fpscr.ux",     &zFPSCR.zbits, 27, 27);
  add_field("fpscr.zx",     &zFPSCR.zbits, 26, 26);
  add_field("fpscr.xx",     &zFPSCR.zbits, 25, 25);
  add_field("fpscr.vxsnan", &zFPSCR.zbits, 24, 24);
  add_field("fpscr.vxisi",  &zFPSCR.zbits, 23, 23);
  add_field("fpscr.vxidi",  &zFPSCR.zbits, 22, 22);
  add_field("fpscr.vxzdz",  &zFPSCR.zbits, 21, 21);
  add_field("fpscr.vximz",  &zFPSCR.zbits, 20, 20);
  add_field("fpscr.vxvc",   &zFPSCR.zbits, 19, 19);
  add_field("fpscr.fr",     &zFPSCR.zbits, 18, 18);
  add_field("fpscr.fi",     &zFPSCR.zbits, 17, 17);
  add_field("fpscr.fprf",   &zFPSCR.zbits, 16, 12);
  add_field("fpscr.vxcvi",  &zFPSCR.zbits,  8,  8);
  add_field("fpscr.ve",     &zFPSCR.zbits,  7,  7);
  add_field("fpscr.oe",     &zFPSCR.zbits,  6,  6);
  add_field("fpscr.ue",     &zFPSCR.zbits,  5,  5);
  add_field("fpscr.ze",     &zFPSCR.zbits,  4,  4);
  add_field("fpscr.xe",     &zFPSCR.zbits,  3,  3);
  add_field("fpscr.rn",     &zFPSCR.zbits,  1,  0);

  idx_cia = n_elems; add_reg("cia", &zCIA);
  idx_nia = n_elems; add_reg("nia", &zNIA);
  add_reg("lr",    &zLR);
  add_reg("ctr",   &zCTR);
  add_reg("msr",   &zMSR.zbits);
  add_reg("srr0",  &zSRR0);
  add_reg("srr1",  &zSRR1);
  add_reg("dar",   &zDAR);
  add_reg("dsisr", &zDSISR);

  add_reg("sprg0", &zSPRG0);
  add_reg("sprg1", &zSPRG1);
  add_reg("sprg2", &zSPRG2);
  add_reg("sprg3", &zSPRG3);
  add_reg("dec",   &zDEC);
  add_reg("rtcu",  &zRTCU);
  add_reg("rtcl",  &zRTCL);
  add_reg("sdr1",  &zSDR1.zbits);
  add_reg("ear",   &zEAR.zbits);

  for (int i = 0; i < 16; i++) add_vec("sr",   i, VS_SR,   32);
  for (int i = 0; i < 4;  i++) add_vec("batu", i, VS_BATU, 32);
  for (int i = 0; i < 4;  i++) add_vec("batl", i, VS_BATL, 32);

  add_reg("mq",   &zMQ);
  add_reg("hid0", &zHID0.zbits);
  add_reg("hid1", &zHID1.zbits);
  add_reg("iabr", &zIABR.zbits);
  add_reg("dabr", &zDABR.zbits);
  add_reg("pir",  &zPIR);
  add_flag("reservation", &zreservation_valid);

  /* Settable but unreported; see the comment on extra[] above. */
  add_extra_flag("dec_pending", &zDEC_pending);
  add_extra_flag("ext_int_pending", &zext_int_pending);
}

static uint64_t *slot_of(const elem_t *e)
{
  switch (e->vec) {
  case VS_GPR:  return &zGPRs.data[e->idx];
  case VS_FPR:  return &zFPRs.data[e->idx];
  case VS_SR:   return &zSRs.data[e->idx];
  case VS_BATU: return &zBATU.data[e->idx];
  case VS_BATL: return &zBATL.data[e->idx];
  default:      return e->slot;
  }
}

static uint64_t elem_mask(const elem_t *e)
{
  return e->bits >= 64 ? ~(uint64_t)0 : ((uint64_t)1 << e->bits) - 1;
}

/* Zero an element's ENTIRE backing word, not just the bit range it names.
 *
 * RESET has to do this rather than elem_set(e, 0), because several architected
 * registers hold bits that the model stores but the canonical vocabulary has
 * no name for.  XER is the clearest case: the Xer bitfield names SO, OV, CA,
 * CMPB (sail 15..8) and BC (6..0), while `mtspr XER` stores all 32 bits
 * unmasked -- so manual bits 3..24 and sail bit 7 have no element covering
 * them.  Clearing only the named ranges left those bits alive across RESET,
 * invisible in the S lines, which made a batch order-dependent and broke the
 * one guarantee RESET exists to provide.  Reproduced before this fix as:
 * mtspr XER with 0x00FF00FF, RESET, mfspr -> 0x00FF0080 instead of 0. */
static void elem_zero_storage(const elem_t *e)
{
  if (e->flag) { *e->flag = false; return; }
  uint64_t *p = slot_of(e);
  if (p) *p = 0;
}

static uint64_t elem_get(const elem_t *e)
{
  if (e->flag) return *e->flag ? 1u : 0u;
  return (*slot_of(e) >> e->lo) & elem_mask(e);
}

static void elem_set(const elem_t *e, uint64_t v)
{
  if (e->flag) { *e->flag = (v & 1) != 0; return; }
  uint64_t m = elem_mask(e);
  uint64_t *p = slot_of(e);
  *p = (*p & ~(m << e->lo)) | ((v & m) << e->lo);
}

/* Name lookup.  Linear search would be a measurable share of the run time at
 * a dozen SETs per vector and a million vectors, so intern the names into an
 * open-addressed table once. */
#define NAME_HASH_CAP 512
static int16_t name_hash[NAME_HASH_CAP];

static uint32_t str_hash(const char *s)
{
  uint32_t h = 2166136261u;
  while (*s) { h ^= (unsigned char)*s++; h *= 16777619u; }
  return h;
}

static void intern_names(void)
{
  for (int i = 0; i < NAME_HASH_CAP; i++) name_hash[i] = -1;
  for (int i = 0; i < n_elems + n_extra; i++) {
    const char *nm = (i < n_elems) ? elems[i].name : extra[i - n_elems].name;
    uint32_t h = str_hash(nm) & (NAME_HASH_CAP - 1);
    while (name_hash[h] != -1) h = (h + 1) & (NAME_HASH_CAP - 1);
    name_hash[h] = (int16_t)i;
  }
}

/* Returns the element, or NULL.  Indices >= n_elems are the extras. */
static const elem_t *find_elem(const char *nm)
{
  uint32_t h = str_hash(nm) & (NAME_HASH_CAP - 1);
  while (name_hash[h] != -1) {
    int i = name_hash[h];
    const elem_t *e = (i < n_elems) ? &elems[i] : &extra[i - n_elems];
    if (strcmp(e->name, nm) == 0) return e;
    h = (h + 1) & (NAME_HASH_CAP - 1);
  }
  return NULL;
}

/* ======================================================================= */
/* Register id -> element mapping                                           */
/* ======================================================================= */

/* The model's write hook names a register by id (model/ppc_harness.sail); the
 * response names a state element.  The two vocabularies differ only where an
 * element is a FIELD of a register — CR0..CR7 inside CR, xer.ca inside XER,
 * the FPSCR flags — so the mapping is "this id starts at this element, and
 * covers this many".  The count is derived from the element table rather than
 * written down, by taking the run of elements sharing the register's backing
 * word: add a field to XER and the mapping follows on its own.
 *
 * Built by name so that a mismatch between the id list and the element table
 * is a startup failure, not a wrong write-set. */

static int16_t hw_first[HW_ID_COUNT];
static uint8_t hw_count[HW_ID_COUNT];

static int elem_index(const char *nm)
{
  const elem_t *e = find_elem(nm);
  if (!e || e < elems || e >= elems + n_elems) {
    fprintf(stderr, "harness: no state element named %s\n", nm);
    exit(1);
  }
  return (int)(e - elems);
}

static void map_hw(int id, const char *first_name)
{
  int i = elem_index(first_name);
  int n = 1;
  /* Sub-fields of one register are contiguous and share a backing word.
   * Vector elements (GPRs, SRs, ...) and booleans have no backing word here
   * and are always one element each. */
  if (elems[i].slot)
    while (i + n < n_elems && elems[i + n].slot == elems[i].slot) n++;
  hw_first[id] = (int16_t)i;
  hw_count[id] = (uint8_t)n;
}

static void build_write_map(void)
{
  char nm[16];

  for (int i = 0; i < HW_ID_COUNT; i++) { hw_first[i] = -1; hw_count[i] = 0; }

  for (int i = 0; i < 32; i++) { snprintf(nm, sizeof nm, "gpr%d", i); map_hw(HW_GPR0 + i, nm); }
  for (int i = 0; i < 32; i++) { snprintf(nm, sizeof nm, "fpr%d", i); map_hw(HW_FPR0 + i, nm); }
  for (int i = 0; i < 16; i++) { snprintf(nm, sizeof nm, "sr%d",  i); map_hw(HW_SR0  + i, nm); }
  for (int i = 0; i < 4;  i++) { snprintf(nm, sizeof nm, "sprg%d", i); map_hw(HW_SPRG0 + i, nm); }
  for (int i = 0; i < 4;  i++) { snprintf(nm, sizeof nm, "batu%d", i); map_hw(HW_BATU0 + i, nm); }
  for (int i = 0; i < 4;  i++) { snprintf(nm, sizeof nm, "batl%d", i); map_hw(HW_BATL0 + i, nm); }

  map_hw(HW_CR,    "cr0");        /* 8 fields  */
  map_hw(HW_XER,   "xer.so");     /* 5 fields  */
  map_hw(HW_FPSCR, "fpscr.fx");   /* 23 fields */

  map_hw(HW_CIA,   "cia");
  map_hw(HW_NIA,   "nia");
  map_hw(HW_LR,    "lr");
  map_hw(HW_CTR,   "ctr");
  map_hw(HW_MSR,   "msr");
  map_hw(HW_SRR0,  "srr0");
  map_hw(HW_SRR1,  "srr1");
  map_hw(HW_DAR,   "dar");
  map_hw(HW_DSISR, "dsisr");
  map_hw(HW_DEC,   "dec");
  map_hw(HW_SDR1,  "sdr1");
  map_hw(HW_EAR,   "ear");
  map_hw(HW_RESERVATION, "reservation");

  map_hw(HW_MQ,   "mq");
  map_hw(HW_RTCU, "rtcu");
  map_hw(HW_RTCL, "rtcl");
  map_hw(HW_HID0, "hid0");
  map_hw(HW_HID1, "hid1");
  map_hw(HW_IABR, "iabr");
  map_hw(HW_DABR, "dabr");
  map_hw(HW_PIR,  "pir");

  /* cia/nia/lr/... are single 32-bit registers with no named sub-fields, so
   * the run-of-elements rule above must have found exactly one of each; if it
   * found more, two elements are sharing a backing word by accident and the
   * write-set would name both. */
  static const int singles[] = { HW_CIA, HW_NIA, HW_LR, HW_CTR, HW_MSR, HW_SRR0,
                                 HW_SRR1, HW_DAR, HW_DSISR, HW_DEC, HW_SDR1,
                                 HW_EAR, HW_MQ, HW_RTCU, HW_RTCL, HW_HID0,
                                 HW_HID1, HW_IABR, HW_DABR, HW_PIR };
  for (size_t i = 0; i < sizeof singles / sizeof singles[0]; i++)
    if (hw_count[singles[i]] != 1) {
      fprintf(stderr, "harness: register id 0x%02X covers %u elements, expected 1\n",
              singles[i], hw_count[singles[i]]);
      exit(1);
    }
}

/* ======================================================================= */
/* Memory: touched-byte tracking                                            */
/* ======================================================================= */

/* Two jobs, one structure.
 *
 * RESET must clear all memory.  kill_mem() does that, but the C runtime
 * allocates RAM in 16 MiB blocks, so a RESET per vector would free and
 * re-zero 16 MiB per vector.  Remembering which bytes were ever written since
 * the last RESET — which is exact, because the only two writers are the MEM
 * command and phys_write, and both come through here — lets RESET zero just
 * those.  If the set ever overflows we fall back to kill_mem(), so the
 * correctness does not depend on the capacity.
 *
 * Occupancy is stamped with a generation counter rather than cleared, so
 * RESET is O(bytes actually written) rather than O(table size).
 *
 * The table GROWS rather than having one fixed size.  It used to hold 65536
 * bytes, which is exactly the size of the generator's memory window — so a
 * vector that populated its whole window overflowed on the first byte of the
 * opcode and every step after it reported ERR memory-tracking-overflow.  The
 * error was harmless (the fallback is correct, just slower) but a caller has
 * no way to know that from the line alone and rightly discarded the vector.
 * Starting at 128 Ki slots and doubling keeps the ordinary case at one
 * allocation while putting the ceiling out of reach of any real vector.
 *
 * The ceiling still exists because past a few million bytes the fallback is
 * the CHEAPER branch: replaying N single-byte writes stops beating freeing a
 * handful of 16 MiB blocks.  It is a performance crossover, not a limit. */

#define TOUCH_INIT_CAP (1u << 17)     /* power of two, slots not bytes    */
#define TOUCH_MAX_ENTRIES (1u << 22)  /* ~4.2M distinct bytes per RESET   */

static uint32_t *touch_key;
static uint32_t *touch_gen;
static uint32_t *touch_list;
static uint32_t touch_cap;            /* slots in touch_key/touch_gen     */
static uint32_t touch_max;            /* entries allowed at this capacity */
static uint32_t n_touch;
static uint32_t cur_gen = 1;
static bool touch_overflow;

/* Doubling the table means rehashing, which is why the insertion-order list
 * is kept: it is exactly the set of live keys.  Returns false if the table
 * cannot grow (at the ceiling, or out of memory), which puts RESET on the
 * kill_mem() path — slower, never wrong. */
static bool touch_grow(void)
{
  uint32_t cap = touch_cap ? touch_cap * 2 : TOUCH_INIT_CAP;
  if (cap / 2 > TOUCH_MAX_ENTRIES || cap < touch_cap) return false;

  uint32_t *key = calloc(cap, sizeof *key);
  uint32_t *gen = calloc(cap, sizeof *gen);
  uint32_t *list = realloc(touch_list, (size_t)(cap / 2) * sizeof *list);
  if (!key || !gen || !list) { free(key); free(gen); if (list) touch_list = list; return false; }

  free(touch_key);
  free(touch_gen);
  touch_key = key;
  touch_gen = gen;
  touch_list = list;
  touch_cap = cap;
  touch_max = cap / 2;                /* keep the load factor at 50% */

  /* calloc zeroed the stamps and cur_gen is never 0, so every slot reads as
   * stale; reinsert what is live. */
  for (uint32_t i = 0; i < n_touch; i++) {
    uint32_t a = touch_list[i];
    uint32_t h = (a * 2654435761u) & (touch_cap - 1);
    while (touch_gen[h] == cur_gen) h = (h + 1) & (touch_cap - 1);
    touch_gen[h] = cur_gen;
    touch_key[h] = a;
  }
  return true;
}

static void touch_mark(uint32_t a)
{
  if (touch_overflow) return;
  if (n_touch >= touch_max && !touch_grow()) { touch_overflow = true; return; }

  uint32_t h = (a * 2654435761u) & (touch_cap - 1);
  for (;;) {
    if (touch_gen[h] != cur_gen) {
      touch_gen[h] = cur_gen;
      touch_key[h] = a;
      touch_list[n_touch++] = a;
      return;
    }
    if (touch_key[h] == a) return;
    h = (h + 1) & (touch_cap - 1);
  }
}

static void mem_put(uint32_t a, uint8_t b)
{
  touch_mark(a);
  write_mem(a, b);
}

static void mem_clear_all(void)
{
  if (touch_overflow) {
    kill_mem();
  } else {
    for (uint32_t i = 0; i < n_touch; i++) write_mem(touch_list[i], 0);
  }
  n_touch = 0;
  touch_overflow = false;
  cur_gen++;
  if (cur_gen == 0) {                 /* wrapped: every stamp is stale again */
    if (touch_gen) memset(touch_gen, 0, (size_t)touch_cap * sizeof *touch_gen);
    cur_gen = 1;
  }
}

/* ======================================================================= */
/* Footprint recording (the model/ppc_harness.sail hooks)                   */
/* ======================================================================= */

#define MAX_EXC 8

/* One list per access kind, in the order the accesses happened.  They grow on
 * demand rather than living in fixed arrays, because a truncated footprint is
 * the one failure this whole project exists to avoid: an access the harness
 * does not report becomes a read the vector does not list, and a runner that
 * trusts the vector then passes on state the instruction actually consulted.
 * A step's footprint is bounded in practice (the widest single instruction is
 * a 32-register lmw/stmw, and each of its accesses can drag a page-table walk
 * behind it), so the growth is a safety net, not a hot path. */
typedef struct { uint32_t addr; uint8_t width; } acc_t;

typedef struct { acc_t *v; int n, cap; const char *tag; } acclist_t;

static acclist_t acc_r  = { NULL, 0, 0, "FMR " };
static acclist_t acc_w  = { NULL, 0, 0, "FMW " };
static acclist_t acc_f  = { NULL, 0, 0, "FF " };
static acclist_t acc_tr = { NULL, 0, 0, "FTR " };
static acclist_t acc_tw = { NULL, 0, 0, "FTW " };
static bool acc_overflow;

/* Pre-step contents of every byte the step is about to overwrite.  Captured
 * in the hook, which the model calls BEFORE the write lands — that is the
 * whole reason the hook is placed where it is. */
typedef struct { uint32_t addr; uint8_t old; } dirty_t;
static dirty_t *dirty;
static int n_dirty, dirty_cap;

static uint32_t exc_vec[MAX_EXC];
static int n_exc;

static bool step_active;

/* Both lists double from 64.  Returns the new block, or NULL — on failure the
 * step is marked overflowed and the response says so; nothing is dropped
 * quietly. */
static void *grow(void *p, int *cap, size_t elem)
{
  int next = *cap ? *cap * 2 : 64;
  void *q = realloc(p, (size_t)next * elem);
  if (q) *cap = next;
  return q;
}

static void acc_note(acclist_t *l, uint32_t a, uint8_t w)
{
  if (l->n >= l->cap) {
    acc_t *v = grow(l->v, &l->cap, sizeof *l->v);
    if (!v) { acc_overflow = true; return; }
    l->v = v;
  }
  l->v[l->n].addr = a;
  l->v[l->n].width = w;
  l->n++;
}

static void dirty_note(uint32_t a)
{
  for (int i = 0; i < n_dirty; i++) if (dirty[i].addr == a) return;
  if (n_dirty >= dirty_cap) {
    dirty_t *d = grow(dirty, &dirty_cap, sizeof *dirty);
    if (!d) { acc_overflow = true; return; }
    dirty = d;
  }
  dirty[n_dirty].addr = a;
  dirty[n_dirty].old = (uint8_t)read_mem(a);
  n_dirty++;
}

unit harness_note_mem(const fbits kind, const fbits addr, const fbits width)
{
  if (!step_active) return UNIT;

  uint32_t a = (uint32_t)addr;
  uint8_t w = (uint8_t)width;
  bool is_write = (kind == HARNESS_MEM_WRITE || kind == HARNESS_MEM_WALK_WRITE);

  switch (kind) {
  case HARNESS_MEM_READ:       acc_note(&acc_r,  a, w); break;
  case HARNESS_MEM_WRITE:      acc_note(&acc_w,  a, w); break;
  case HARNESS_MEM_WALK_READ:  acc_note(&acc_tr, a, w); break;
  case HARNESS_MEM_WALK_WRITE: acc_note(&acc_tw, a, w); break;
  default:                     acc_note(&acc_f,  a, w); break;
  }

  /* The byte diff and the RESET-clearing set do not care WHO wrote: an R/C
   * bit the MMU set is as much a change to memory as a store is, and RESET
   * must undo it either way. */
  if (is_write)
    for (uint8_t i = 0; i < w; i++) { dirty_note(a + i); touch_mark(a + i); }

  return UNIT;
}

unit harness_note_exception(const fbits vector)
{
  if (step_active && n_exc < MAX_EXC) exc_vec[n_exc++] = (uint32_t)vector;
  return UNIT;
}

/* --- Register writes ---------------------------------------------------- */

/* Set by the model's write hook, one flag per canonical element.  This is
 * what makes the reported write-set a WRITE-set rather than a change-set: a
 * store of the value already present sets the flag with no state diff to show
 * for it, and that is precisely the case a diff cannot see (see the header of
 * model/ppc_harness.sail for why it is not a corner case). */
static uint8_t wrote[MAX_ELEMS];

/* hw_first / hw_count map a register id to the elements it covers; see
 * build_write_map above.  Most ids name exactly one element; CR, XER and
 * FPSCR name a contiguous run of them, and the mask says which of the run the
 * write reached. */

unit harness_note_write(const fbits reg, const fbits mask)
{
  if (!step_active) return UNIT;

  unsigned id = (unsigned)reg & (HW_ID_COUNT - 1);
  int first = hw_first[id];
  if (first < 0) return UNIT;          /* an id this build does not name */

  int n = hw_count[id];
  if (n == 1) { wrote[first] = 1; return UNIT; }

  uint32_t m = (uint32_t)mask;
  for (int i = first; i < first + n; i++) {
    const elem_t *e = &elems[i];
    uint32_t em = (uint32_t)(elem_mask(e) << e->lo);
    if (m & em) wrote[i] = 1;
  }
  return UNIT;
}

/* ======================================================================= */
/* Parsing                                                                  */
/* ======================================================================= */

static int hexval(int c)
{
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

/* Parse an unsigned hex literal: optional 0x/0X prefix, underscores tolerated
 * (the vector format forbids emitting them but requires readers to accept
 * them).  Returns false on anything else, including an empty digit string or
 * more than 16 significant digits. */
static bool parse_hex(const char *s, uint64_t *out)
{
  if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
  uint64_t v = 0;
  int ndig = 0;   /* digits seen at all, so that "" and "0x" are rejected   */
  int nsig = 0;   /* significant digits: leading zeros cost nothing, which
                     is what makes the 16-digit cap a check for overflow
                     rather than a limit on how widely a caller may pad     */
  for (; *s; s++) {
    if (*s == '_') continue;
    int d = hexval((unsigned char)*s);
    if (d < 0) return false;
    ndig++;
    if ((nsig > 0 || d != 0) && ++nsig > 16) return false;
    v = (v << 4) | (uint64_t)d;
  }
  if (ndig == 0) return false;
  *out = v;
  return true;
}

/* Split a line into whitespace-separated tokens in place. */
static int tokenize(char *line, char *tok[], int max)
{
  int n = 0;
  char *p = line;
  while (*p && n < max) {
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (!*p) break;
    tok[n++] = p;
    while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') p++;
    if (*p) *p++ = '\0';
  }
  return n;
}

/* ======================================================================= */
/* Commands                                                                 */
/* ======================================================================= */

/* Non-architectural model state that RESET must also put in a known place,
 * and that the determinism contract requires (see the file header). */
static void apply_determinism_knobs(void)
{
  ztrace_enabled = false;
  mpz_set_ui(zstep_limit, 0);
  mpz_set_ui(ztick_ns, 0);      /* freezes core_tick(): no RTC, no DEC       */
  mpz_set_ui(zrtc_ns_acc, 0);
}

static void do_reset(void)
{
  for (int i = 0; i < n_elems; i++) elem_zero_storage(&elems[i]);
  for (int i = 0; i < n_extra; i++) elem_zero_storage(&extra[i]);
  zcur_instr = 0;
  zhalt_req = false;
  zhalt_status = 0;
  zcheckstop_req = false;
  apply_determinism_knobs();
  mem_clear_all();
}

/* `SET cia X` sets NIA too: step() starts with CIA = NIA, so NIA is what
 * decides where the next instruction comes from, and a vector's `cia` means
 * "where the instruction under test lives".  Setting `nia` afterwards
 * overrides it, which is how a caller asks for anything else. */
static void do_set(const char *name, uint64_t v)
{
  const elem_t *e = find_elem(name);
  if (!e) { err("unknown element", name); return; }
  /* Reject rather than truncate: a value too wide for the element is a bug in
   * whatever produced the batch, and silently masking it turns that bug into
   * a plausible-looking wrong vector. */
  if (e->bits < 64 && (v >> e->bits) != 0) { err("value too wide for element", name); return; }
  elem_set(e, v);
  if (e == &elems[idx_cia]) elem_set(&elems[idx_nia], v);
}

/* Validated in full before a single byte is written, so that a malformed line
 * really is "ignored" rather than half-applied. */
static void do_mem(uint32_t addr, const char *bytes)
{
  const char *s = bytes;
  if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;

  int ndig = 0;
  for (const char *p = s; *p; p++) {
    if (*p == '_') continue;
    if (hexval((unsigned char)*p) < 0) { err("bad hex bytes", bytes); return; }
    ndig++;
  }
  if (ndig == 0) { err("no hex bytes", bytes); return; }
  if (ndig & 1) { err("odd number of hex digits", bytes); return; }

  /* The range must fit in the 32-bit physical address space.  Without this the
   * store address wraps and the tail of the range lands at 0 -- silently
   * writing the exception-vector page, which is precisely the region a
   * hardware runner puts its handlers in and which vectors are forbidden to
   * target.  Checked here, with the other validation, so the line is ignored
   * whole rather than half-applied. */
  if ((uint64_t)addr + (uint64_t)(ndig / 2) > 0x100000000ull) {
    err("byte range runs past the end of physical memory", bytes);
    return;
  }

  int hi = -1;
  uint32_t a = addr;
  for (; *s; s++) {
    if (*s == '_') continue;
    int d = hexval((unsigned char)*s);
    if (hi < 0) hi = d;
    else { mem_put(a++, (uint8_t)((hi << 4) | d)); hi = -1; }
  }
}

/* Place the opcode where the next STEP will fetch from, big-endian, and let
 * the real step() fetch it.  Deliberately not injected into cur_instr: fetch,
 * the cur_instr latch that the alignment exception's DSISR image depends on,
 * and decode then all run exactly as they do in a program.  The fetch is
 * reported as FF so that a caller building core vectors can drop it.
 *
 * That address is NIA, not CIA: step() begins with CIA = NIA.  After a RESET
 * or a SET cia the two are equal and this is literally "at the current cia";
 * after a STEP they are not, and using CIA would overwrite the instruction
 * just executed while the next step fetched whatever happened to be at NIA. */
static void do_opcode(uint32_t op)
{
  uint32_t a = (uint32_t)zNIA;
  /* Little-endian mode moves where the fetch looks.  The 601 does not
   * byte-swap in LE mode; it munges the low address bits, which at width 4 is
   * "xor 4" -- §2.4.3.3's "instructions are swapped within a double word"
   * (see le_munge and phys_fetch in model/ppc_mem.sail).  Placing the opcode
   * at the unmunged address would leave the fetch reading whatever was at
   * a ^ 4, which decodes as garbage and traps: the command would silently
   * stop doing what it says.  Mirrors le_munge(a, 4) rather than calling it,
   * because that is a Sail function; if the model's munge ever changes, this
   * has to change with it.
   *
   * HID0[LM] is sail bit 3 of the P601_Hid0 bitfield (manual bit 28). */
  if ((zHID0.zbits >> 3) & 1) a ^= 4;
  mem_put(a + 0, (uint8_t)(op >> 24));
  mem_put(a + 1, (uint8_t)(op >> 16));
  mem_put(a + 2, (uint8_t)(op >> 8));
  mem_put(a + 3, (uint8_t)op);
}

/* --- STEP --------------------------------------------------------------- */

static uint64_t snap[MAX_ELEMS];

static int cmp_dirty(const void *a, const void *b)
{
  uint32_t x = ((const dirty_t *)a)->addr;
  uint32_t y = ((const dirty_t *)b)->addr;
  return x < y ? -1 : x > y ? 1 : 0;
}

static void emit_mem_diff(void)
{
  /* Only bytes the step wrote can have changed, and every one of those was
   * recorded with its previous value by the write hook — so the diff is
   * exact without snapshotting memory. */
  int n = 0;
  for (int i = 0; i < n_dirty; i++) {
    uint8_t now = (uint8_t)read_mem(dirty[i].addr);
    if (now != dirty[i].old) dirty[n++] = dirty[i];
  }
  if (n == 0) return;
  qsort(dirty, (size_t)n, sizeof dirty[0], cmp_dirty);

  int i = 0;
  while (i < n) {
    int j = i + 1;
    while (j < n && dirty[j].addr == dirty[j - 1].addr + 1) j++;
    oputs("M ");
    ohex0x(dirty[i].addr, 8);
    ochar(' ');
    for (int k = i; k < j; k++) ohex(read_mem(dirty[k].addr), 2);
    ochar('\n');
    i = j;
  }
}

static void emit_acc(const acclist_t *l)
{
  for (int i = 0; i < l->n; i++) {
    oputs(l->tag);
    ohex0x(l->v[i].addr, 8);
    ochar(' ');
    odec(l->v[i].width);
    ochar('\n');
  }
}

static unsigned long step_count;

static void do_step(void)
{
  acc_r.n = acc_w.n = acc_f.n = acc_tr.n = acc_tw.n = 0;
  n_dirty = 0;
  n_exc = 0;
  acc_overflow = false;
  memset(wrote, 0, (size_t)n_elems);

  zhalt_req = false;
  zhalt_status = 0;
  zcheckstop_req = false;
  apply_determinism_knobs();

  for (int i = 0; i < n_elems; i++) snap[i] = elem_get(&elems[i]);

#ifdef PPC_HARNESS_COVERAGE
  ppc_cov_step_begin();
#endif

  step_active = true;
  (void)zstep(UNIT);
  step_active = false;

#ifdef PPC_HARNESS_COVERAGE
  ppc_cov_step_end(step_count);
#endif
  step_count++;

  /* A Sail `throw` that escapes step() (the model raises Model_internal_error
   * for the handful of things it does not implement, e.g. a real I/O
   * controller segment transaction).  The architected state is whatever it
   * was when the throw happened, so say so and carry on rather than leaving
   * the flag set, which would make every later step a no-op. */
  bool threw = have_exception;
  if (threw) have_exception = false;

  for (int i = 0; i < n_elems; i++) {
    oputs("S ");
    oputs(elems[i].name);
    ochar(' ');
    ohex0x(elem_get(&elems[i]), elems[i].nib);
    ochar('\n');
  }

  emit_mem_diff();

  /* The write set.  Two sources, deliberately unioned:
   *
   *  - the model's write hook, which is exact and is the whole point of it —
   *    it sees a write that stores the value already there, which no diff can;
   *  - the state diff, which is the safety net.  Every hook call site was put
   *    in by hand (there is no choke point for register assignment in Sail),
   *    so a future model change can add a write that nobody hooked.  If the
   *    diff ever shows an element the hook did not claim, that has happened,
   *    and the response says so rather than quietly reporting one write set
   *    while the model performed another.
   *
   * `cia` is exempt from neither: step() writes it every time, and it appears
   * whenever it changed — which it does when an asynchronous interrupt is
   * delivered, since check_interrupts() redirects NIA before step() copies it
   * into CIA.  It is suppressed when unchanged (below) because "the address
   * the instruction under test ran at" is an input to a vector, not an
   * output, and a caller reads it from the vector, not from the write set. */
  bool gap = false;
  for (int i = 0; i < n_elems; i++) {
    bool changed = elem_get(&elems[i]) != snap[i];
    if (changed && !wrote[i]) gap = true;
    /* nia is written by every step by construction, so it is reported
     * unconditionally (a branch-to-self would otherwise hide it). */
    if (i != idx_nia && i != idx_cia && !wrote[i] && !changed) continue;
    if (i == idx_cia && !changed) continue;
    oputs("FW ");
    oputs(elems[i].name);
    ochar('\n');
  }

  emit_acc(&acc_r);
  emit_acc(&acc_w);
  emit_acc(&acc_f);
  emit_acc(&acc_tr);
  emit_acc(&acc_tw);

  if (n_exc == 0) oputs("EXC none\n");
  else { oputs("EXC "); ohex0x(exc_vec[0], 8); ochar('\n'); }

  if (zhalt_req) {
    oputs("HALT ");
    ohex0x(zhalt_status, 8);
    ochar('\n');
  }

  /* Conditions protocol v1 has no line for.  Reported as ERR rather than
   * dropped: silence about a step that did something unusual is worse than
   * an extra line a strict parser can ignore. */
  if (zcheckstop_req) oputs("ERR checkstop\n");
  if (acc_overflow)   oputs("ERR footprint-overflow\n");
  if (touch_overflow) oputs("ERR memory-tracking-overflow\n");
  if (threw)          oputs("ERR sail-throw\n");
  if (n_exc > 1)      oputs("ERR multiple-exceptions\n");
  /* An element changed that the model's write hook never claimed: a write
   * site in the model has no harness_note_write beside it.  The FW lines
   * above are still complete (the diff is unioned in), but the write set is
   * no longer trustworthy for the value-preserving case, which is the reason
   * the hook exists — so this is a bug report, not a vector condition. */
  if (gap)            oputs("ERR write-tracking-gap\n");

  oputs("DONE\n");
  oflush_partial();
  fflush(stdout);
}

/* ======================================================================= */
/* Driver                                                                   */
/* ======================================================================= */

static const char USAGE[] =
  "usage: ppc_p601_harness [options]  < commands  > responses\n"
  "\n"
  "Single-step test-vector harness for the powerpc-sail PowerPC 601 model.\n"
  "Reads commands on stdin, writes responses on stdout; many vectors per\n"
  "process.  See generator/HARNESS.md in the powerpc-test project.\n"
  "\n"
  "commands:  RESET | SET <elem> <hex> | MEM <addr> <hexbytes>\n"
  "           OPCODE <hex> | STEP | QUIT\n"
  "\n"
  "options:\n"
  "  --elements            list every element name, one per line, and exit\n"
  "  --help                this text\n"
#ifdef PPC_HARNESS_COVERAGE
  "\n"
  "coverage build:\n"
  "  --coverage-out FILE   write accumulated coverage (sailcov format) at exit\n"
  "  --coverage-per-step FILE\n"
  "                        append one bitmap line per STEP\n"
  "  --coverage-branches FILE\n"
  "                        pre-size the per-step bitmaps from a .branches file\n"
  "                        so every line has the same width\n"
#endif
  ;

int main(int argc, char *argv[])
{
  bool list_elements = false;
#ifdef PPC_HARNESS_COVERAGE
  const char *cov_out = NULL, *cov_step = NULL, *cov_branches = NULL;
#endif

  for (int i = 1; i < argc; i++) {
    const char *a = argv[i];
    if (!strcmp(a, "--help") || !strcmp(a, "-h")) { fputs(USAGE, stdout); return 0; }
    else if (!strcmp(a, "--elements")) list_elements = true;
#ifdef PPC_HARNESS_COVERAGE
    else if (!strcmp(a, "--coverage-out") && i + 1 < argc) cov_out = argv[++i];
    else if (!strcmp(a, "--coverage-per-step") && i + 1 < argc) cov_step = argv[++i];
    else if (!strcmp(a, "--coverage-branches") && i + 1 < argc) cov_branches = argv[++i];
#else
    else if (!strncmp(a, "--coverage", 10)) {
      fprintf(stderr,
              "%s: not a coverage build; use build/ppc_p601_harness_cov "
              "(make harness-cov)\n", argv[0]);
      return 2;
    }
#endif
    else { fprintf(stderr, "%s: unknown option %s\n", argv[0], a); fputs(USAGE, stderr); return 2; }
  }

  model_init();
  build_elem_table();
  intern_names();
  build_write_map();

  if (list_elements) {
    for (int i = 0; i < n_elems; i++) printf("%s\n", elems[i].name);
    model_fini();
    return 0;
  }

#ifdef PPC_HARNESS_COVERAGE
  if (cov_branches) ppc_cov_presize(cov_branches);
  if (cov_step) ppc_cov_set_per_step(cov_step);
  if (cov_out) ppc_cov_set_output(cov_out);
#endif

  do_reset();

  char *line = NULL;
  size_t cap = 0;
  ssize_t len;
  char *tok[4];

  while ((len = getline(&line, &cap, stdin)) > 0) {
    int n = tokenize(line, tok, 4);
    if (n == 0 || tok[0][0] == '#') continue;

    const char *cmd = tok[0];
    uint64_t v;

    if (!strcmp(cmd, "STEP")) {
      if (n != 1) { err("STEP takes no arguments", NULL); continue; }
      do_step();
    } else if (!strcmp(cmd, "SET")) {
      if (n != 3) { err("SET needs <elem> <hex>", NULL); continue; }
      if (!parse_hex(tok[2], &v)) { err("bad hex value", tok[2]); continue; }
      do_set(tok[1], v);
    } else if (!strcmp(cmd, "MEM")) {
      if (n != 3) { err("MEM needs <addr> <hexbytes>", NULL); continue; }
      if (!parse_hex(tok[1], &v)) { err("bad address", tok[1]); continue; }
      /* Physical addresses are 32 bits; truncating a wider one would put the
       * bytes somewhere plausible but wrong. */
      if (v > 0xFFFFFFFFu) { err("address out of range", tok[1]); continue; }
      do_mem((uint32_t)v, tok[2]);
    } else if (!strcmp(cmd, "OPCODE")) {
      if (n != 2) { err("OPCODE needs <hex>", NULL); continue; }
      if (!parse_hex(tok[1], &v)) { err("bad opcode", tok[1]); continue; }
      if (v > 0xFFFFFFFFu) { err("opcode out of range", tok[1]); continue; }
      do_opcode((uint32_t)v);
    } else if (!strcmp(cmd, "RESET")) {
      if (n != 1) { err("RESET takes no arguments", NULL); continue; }
      do_reset();
    } else if (!strcmp(cmd, "QUIT")) {
      break;
    } else {
      err("unknown command", cmd);
    }
  }

  free(line);
  oflush_partial();
  fflush(stdout);

#ifdef PPC_HARNESS_COVERAGE
  ppc_cov_finish();
#endif

  model_fini();
  return 0;
}
