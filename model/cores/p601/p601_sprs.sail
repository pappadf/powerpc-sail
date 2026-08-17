/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* p601_sprs.sail — SPR map clauses for 601-specific registers.
 * Reference: MPC601UM Tables 3-40 / 3-41 and §2.2.5, §2.3.3. */

$ifndef _P601_SPRS
$define _P601_SPRS

/* 0 MQ — POWER holdover, user r/w */
function clause read_spr(0b0000000000 /* 0 MQ */) = Some(MQ)
function clause write_spr(0b0000000000, v) = { harness_wrote(hw_mq); MQ = v; true }

/* 4/5 RTCU/RTCL — user READ-ONLY encodings.  The write encodings are the
 * separate supervisor SPR numbers 20/21 (dual-numbering quirk, §2.2.5.3).
 * Table 10-5 (mtspr) does not list 4/5/6 at all, so mtspr to one of them is
 * an unimplemented encoding and no-ops — which is what omitting the
 * write_spr clauses achieves. */
function clause read_spr(0b0000000100 /* 4 RTCU read */) = Some(RTCU)
function clause read_spr(0b0000000101 /* 5 RTCL read */) = Some(RTCL)
  /* RTCL's unimplemented bits read as zero (§2.2.5.3.1); the register is
   * kept masked by every write and by the tick, so no mask is needed here. */

/* 6 DEC — 601-only POWER-compat user read of the decrementer. */
function clause read_spr(0b0000000110 /* 6 DEC user read */) = Some(DEC)

/* 20/21 RTCU/RTCL — supervisor WRITE-ONLY encodings.  Table 10-4 (mfspr)
 * does not list them: mfspr must name 4/5 whatever the privilege level, so
 * there is no read clause here.  An mfspr naming 20/21 therefore takes the
 * unimplemented-SPR path — a no-op, or a privileged program exception in
 * user mode, since SPR[0]=1 (§2.3.3 and the ch. 10 mfspr page). */
function clause write_spr(0b0000010100 /* 20 RTCU */, v) = { harness_wrote(hw_rtcu); RTCU = v; true }

function clause write_spr(0b0000010101 /* 21 RTCL */, v) = { harness_wrote(hw_rtcl); RTCL = v & rtcl_implemented; true }
  /* "the values of the GPR corresponding to the unimplemented bits in the
   * RTCL are ignored" (§2.2.5.3.1).  RTCU has all 32 bits, so it takes the
   * value as written. */

/* 528-535 BAT0U..BAT3L — named IBATnU/L but unified on the 601.
 * Table 2-14: BATs return the last value written (all bits kept).
 * A BAT write flushes the ITLB on hardware (§6.2); no TLB is modelled here,
 * so there is nothing to flush. */
function clause read_spr(0b1000010000 /* 528 BAT0U */) = Some(BATU[0])
function clause write_spr(0b1000010000, v) = { harness_wrote(hw_batu0); BATU[0] = v; true }
function clause read_spr(0b1000010001 /* 529 BAT0L */) = Some(BATL[0])
function clause write_spr(0b1000010001, v) = { harness_wrote(hw_batl0); BATL[0] = v; true }
function clause read_spr(0b1000010010 /* 530 BAT1U */) = Some(BATU[1])
function clause write_spr(0b1000010010, v) = { harness_wrote(hw_batu1); BATU[1] = v; true }
function clause read_spr(0b1000010011 /* 531 BAT1L */) = Some(BATL[1])
function clause write_spr(0b1000010011, v) = { harness_wrote(hw_batl1); BATL[1] = v; true }
function clause read_spr(0b1000010100 /* 532 BAT2U */) = Some(BATU[2])
function clause write_spr(0b1000010100, v) = { harness_wrote(hw_batu2); BATU[2] = v; true }
function clause read_spr(0b1000010101 /* 533 BAT2L */) = Some(BATL[2])
function clause write_spr(0b1000010101, v) = { harness_wrote(hw_batl2); BATL[2] = v; true }
function clause read_spr(0b1000010110 /* 534 BAT3U */) = Some(BATU[3])
function clause write_spr(0b1000010110, v) = { harness_wrote(hw_batu3); BATU[3] = v; true }
function clause read_spr(0b1000010111 /* 535 BAT3L */) = Some(BATL[3])
function clause write_spr(0b1000010111, v) = { harness_wrote(hw_batl3); BATL[3] = v; true }

/* 1008-1023 HID registers (§2.3.3.13).  Undefined-bit behaviour differs per
 * register (Table 2-14): HID0/HID15 read zeros in undefined bits, HID1/2/5
 * keep last value written.  TODO: masks. */
function clause read_spr(0b1111110000 /* 1008 HID0 */) = Some(HID0.bits)
function clause write_spr(0b1111110000, v) = { harness_wrote(hw_hid0); HID0 = Mk_P601_Hid0(v); true }
  /* Writing HID0[LM] switches endianness; core_bigendian (p601_core.sail)
   * carries the note on the §2.4.3.2 sync sequence. */

function clause read_spr(0b1111110001 /* 1009 HID1 */) = Some(HID1.bits)
function clause write_spr(0b1111110001, v) = { harness_wrote(hw_hid1); HID1 = Mk_P601_Hid1(v); true }

function clause read_spr(0b1111110010 /* 1010 HID2/IABR */) = Some(IABR.bits)
function clause write_spr(0b1111110010, v) = { harness_wrote(hw_iabr); IABR = Mk_P601_Iabr(v); true }

function clause read_spr(0b1111110101 /* 1013 HID5/DABR */) = Some(DABR.bits)
function clause write_spr(0b1111110101, v) = { harness_wrote(hw_dabr); DABR = Mk_P601_Dabr(v); true }
  /* DABR keeps every bit written, including reserved manual bit 29, which
   * "on an mfspr (DABR) ... returns the value last written" (Table 2-25). */

function clause read_spr(0b1111111111 /* 1023 HID15/PIR */) = Some(PIR)
function clause write_spr(0b1111111111, v) = { harness_wrote(hw_pir); PIR = v; true }
  /* TODO: only the 4-bit PID field exists; other bits read zero. */

/* NOT implemented on the 601 (fall through to the wildcard clauses →
 * no-op / privileged-encoding program exception): TB/TBU (284/285),
 * DBAT0U-DBAT3L (536-543), ASR (280), FPECR.  (§2.6, Tables 10-7/10-9) */

$endif
