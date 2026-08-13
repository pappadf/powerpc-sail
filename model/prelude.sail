/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* prelude.sail — standard-library imports and basic utilities.
 *
 * BIT NUMBERING CONVENTION
 * ------------------------
 * The PowerPC architecture (and the MPC601UM manual) numbers bits big-endian:
 * bit 0 is the MOST significant bit of a 32-bit register.  Sail models work
 * best with decreasing ("dec") indexing where bit 0 is the LEAST significant.
 *
 * We use `default Order dec` throughout.  Conversion rule for a 32-bit value:
 *
 *     sail bit index  =  31 - (PowerPC manual bit index)
 *
 * Every bitfield definition in this model carries a comment giving the
 * manual's big-endian bit numbers so the two can be cross-checked.  When an
 * instruction encoding diagram in the manual shows fields left-to-right,
 * writing them left-to-right with `@` concatenation in an encdec mapping
 * clause produces exactly the right layout in dec order.
 */

default Order dec

$include <prelude.sail>
$include <reverse_endianness.sail>

$ifndef _PPC_PRELUDE
$define _PPC_PRELUDE

/* Additional bitvector operator overloads not provided by the stdlib default set */
val sub_bits_int : forall 'n. (bits('n), int) -> bits('n)
function sub_bits_int(x, y) = add_bits_int(x, 0 - y)

overload operator - = {sub_bits, sub_bits_int}

/* --- Fundamental type abbreviations ------------------------------------- */

/* PowerPC fixes its data lengths: a byte, half word, word and double word
 * are 8, 16, 32 and 64 bits on every implementation of the architecture.
 * Nothing scales with the implementation the way a word size does on some
 * other architectures, so there is no width parameter here — the targeted
 * cores (601/603/604) are all 32-bit implementations and the model says
 * `word` where it means 32 bits.
 *
 * A 64-bit core would NOT simply widen this alias.  The manual is careful
 * about which registers follow the implementation: the LR and CTR are "32
 * bits wide in 32-bit implementations" (§1.3.2.1.8), whereas the CR is
 * flatly "a 32-bit register" (§2.2.4), as are XER, DSISR and DEC, and the
 * segment registers are "present only in 32-bit implementations"
 * (§6.1.11) — a 64-bit part has no SRs at all.  Widening a single alias
 * would get all four groups wrong, so that distinction is left to be drawn
 * properly by whoever adds such a core. */
type word = bits(32)

/* Instruction operand fields, named after the manual's own operand spellings
 * (rA/rB/rS/rD for the GPR fields, frA/frB/frC/frS/frD for the FPR fields).
 * These are synonyms, not distinct types — Sail will not catch an FPR index
 * passed where a GPR index belongs — so they document intent only. */
type ridx = bits(5)       /* GPR field:  rA, rB, rS, rD             */
type fridx = bits(5)      /* FPR field:  frA, frB, frC, frS, frD    */
type cridx = bits(3)      /* CR field index (crfD/crfS)             */
type sridx = bits(4)      /* segment register selector, EA[0:3]     */
type sprno = bits(10)     /* SPR number (already un-swizzled)       */

/* --- Small helpers ------------------------------------------------------ */

val zeros : forall 'n, 'n >= 0. int('n) -> bits('n)
function zeros(n) = sail_zeros(n)

val ones : forall 'n, 'n >= 0. int('n) -> bits('n)
function ones(n) = sail_ones(n)

val bool_to_bit : bool -> bit
function bool_to_bit(b) = if b then bitone else bitzero

val bool_to_bits : bool -> bits(1)
function bool_to_bits(b) = if b then 0b1 else 0b0

val bit_to_bool : bit -> bool
function bit_to_bool(b) = b == bitone

/* Sign/zero extension to a word, under the manual's RTL names EXTS/EXTZ */
val exts : forall 'n, 0 < 'n <= 32. bits('n) -> word
function exts(v) = sail_sign_extend(v, 32)

val extz : forall 'n, 0 < 'n <= 32. bits('n) -> word
function extz(v) = sail_zero_extend(v, 32)

/* Truncate a model-level integer (an ELF entry point, a configured address)
 * to a word. */
val to_word : int -> word
function to_word(i) = get_slice_int(32, i, 0)

$endif
