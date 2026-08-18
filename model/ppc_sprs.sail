/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_sprs.sail — special purpose register access, as used by mfspr/mtspr.
 *
 * read_spr/write_spr are SCATTERED so each core can contribute clauses for
 * its own SPRs (see cores/p601/p601_sprs.sail).  The scattered definitions
 * are closed, with wildcard fallback clauses, in ppc_insts_end.sail.
 *
 * The SPR number here is the *architectural* number (already un-swizzled
 * from the instruction encoding — see sprno_of_field in
 * ppc_insts_system.sail).  SPR numbers with manual-bit-0 set (sail bit 9,
 * i.e. number >= 512 ... actually spr[0] of the split field => numbers
 * 16..31 mod 32 — see spr_is_privileged below) are supervisor-only.
 *
 * Returning None() / false means "unimplemented SPR"; the 601 behaviour for
 * those is decided at the call site in mfspr/mtspr (no-op if user-accessible
 * encoding, program exception if privileged encoding and MSR[PR]=1 —
 * MPC601UM §2.2.5, §2.6). */

$ifndef _PPC_SPRS
$define _PPC_SPRS

/* Manual §3.7.2: "SPR[0]=1 iff the register is supervisor-level", where
 * SPR[0] is the first bit of the FIRST 5-bit instruction field — which
 * encodes the LOW-order half of the architectural number.  So the check on
 * the architectural number n is: MSB of its low 5 bits, i.e. n[4].
 * Sanity: SPRG0=272=0b01000_10000, low half 10000 -> supervisor;
 * XER=1=0b00000_00001, low half 00001 -> user; DEC=22 -> supervisor. */
val spr_is_privileged : sprno -> bool
function spr_is_privileged(n) = n[4] == bitone

val read_spr : sprno -> option(word)
scattered function read_spr

val write_spr : (sprno, word) -> bool
scattered function write_spr

/* --- Common user-level SPRs (MPC601UM Table 3-40) ----------------------- */

function clause read_spr(0b0000000001 /* 1 XER */) = Some(XER.bits)
function clause write_spr(0b0000000001, v) = { harness_wrote(hw_xer); XER = Mk_Xer(v); true }

function clause read_spr(0b0000001000 /* 8 LR */) = Some(LR)
function clause write_spr(0b0000001000, v) = { harness_wrote(hw_lr); LR = v; true }

function clause read_spr(0b0000001001 /* 9 CTR */) = Some(CTR)
function clause write_spr(0b0000001001, v) = { harness_wrote(hw_ctr); CTR = v; true }

/* --- Common supervisor-level SPRs (MPC601UM Table 3-41) ----------------- */

function clause read_spr(0b0000010010 /* 18 DSISR */) = Some(DSISR)
function clause write_spr(0b0000010010, v) = { harness_wrote(hw_dsisr); DSISR = v; true }

function clause read_spr(0b0000010011 /* 19 DAR */) = Some(DAR)
function clause write_spr(0b0000010011, v) = { harness_wrote(hw_dar); DAR = v; true }

/* 22 DEC.  Only the upper 25 bits are implemented and a write that drives
 * manual bit 0 from 0 to 1 signals a decrementer exception just as the timer
 * would (§2.3.3.5) — both properties belong to set_dec, so software and the
 * timer cannot diverge.  User read via SPR 6 is a 601-only encoding,
 * provided in p601_sprs.sail. */
function clause read_spr(0b0000010110 /* 22 DEC */) = Some(DEC)
function clause write_spr(0b0000010110, v) = { set_dec(v); true }

function clause read_spr(0b0000011001 /* 25 SDR1 */) = Some(SDR1.bits)
function clause write_spr(0b0000011001, v) = { harness_wrote(hw_sdr1); SDR1 = Mk_Sdr1(v); true }
  /* §6.9.1.1 requires HTABMASK to be a run of 1 bits and HTABORG to carry as
   * many low zero bits, but gives no behaviour for a value that breaks that,
   * so nothing is checked here.
   * TODO: the reserved bits (manual 16-22, Table 6-18) must read as zero on
   * the 601 (Table 2-14) — Mk_Sdr1 keeps all bits; mask them on write, the
   * way fpscr_write masks with fpscr_implemented. */

function clause read_spr(0b0000011010 /* 26 SRR0 */) = Some(SRR0)
function clause write_spr(0b0000011010, v) = { harness_wrote(hw_srr0); SRR0 = v; true }

function clause read_spr(0b0000011011 /* 27 SRR1 */) = Some(SRR1)
function clause write_spr(0b0000011011, v) = { harness_wrote(hw_srr1); SRR1 = v; true }

function clause read_spr(0b0100010000 /* 272 SPRG0 */) = Some(SPRG0)
function clause write_spr(0b0100010000, v) = { harness_wrote(hw_sprg0); SPRG0 = v; true }

function clause read_spr(0b0100010001 /* 273 SPRG1 */) = Some(SPRG1)
function clause write_spr(0b0100010001, v) = { harness_wrote(hw_sprg1); SPRG1 = v; true }

function clause read_spr(0b0100010010 /* 274 SPRG2 */) = Some(SPRG2)
function clause write_spr(0b0100010010, v) = { harness_wrote(hw_sprg2); SPRG2 = v; true }

function clause read_spr(0b0100010011 /* 275 SPRG3 */) = Some(SPRG3)
function clause write_spr(0b0100010011, v) = { harness_wrote(hw_sprg3); SPRG3 = v; true }

function clause read_spr(0b0100011010 /* 282 EAR */) = Some(EAR.bits)
function clause write_spr(0b0100011010, v) = { harness_wrote(hw_ear); EAR = Mk_Ear(v); true }
  /* E (manual bit 0) and RID (manual bits 28-31) are the only defined
   * fields; everything between them is reserved (Table 2-18). */

/* 287 PVR: read-only; the value comes from the core. */
function clause read_spr(0b0100011111 /* 287 PVR */) = Some(core_pvr())
function clause write_spr(0b0100011111, _) = false
  /* Table 10-5 (mtspr) does not list 287, so the write is an unimplemented
   * encoding and no-ops, which is how §2.3.3.11's "read-only" is enforced. */

/* TODO when 603/604 land: TB/TBU (268/269 read, 284/285 write), DBATs
 * (536-543), additional HIDs, MMCR/PMC (604) go in the respective core
 * directories. */

$endif
