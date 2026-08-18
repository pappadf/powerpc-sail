/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_mmu.sail — address translation, common 32-bit PowerPC skeleton.
 *
 * Translation order (MPC601UM Figure 6-4, Table 6-10):
 *   1. Fetch with MSR[IT]=0, or data access with MSR[DT]=0 and a segment
 *      register with T=0: direct (untranslated), PA = EA, WIM = 0b001.
 *   2. Segment register with T=1 -> I/O controller interface segment.  The
 *      BAT array is IGNORED for these on the 601 (§6.7.2), and for DATA the
 *      T bit is consulted before MSR[DT], so an I/O segment translates even
 *      with data translation off (§6.5.2.2).  Both are 601 deviations from
 *      the architecture, where a matching BAT always wins and T=1 handling
 *      needs MSR[DT]=1.  TODO: move both behind the core interface when a
 *      core that does it the architected way lands.
 *   3. BAT array lookup (core hook: entry format and protection differ).
 *   4. Segment + hashed page table translation.
 *
 * There is no TLB, and none is planned: every access walks the page table
 * afresh, which is observationally equivalent to a TLB that is always
 * coherent with memory.  The one visible consequence is that reference and
 * change bits are written on every access rather than on a miss — the same
 * values, so only the bus traffic differs, and that is not modelled either.
 */

$ifndef _PPC_MMU
$define _PPC_MMU

/* Page table entry, standard 32-bit PowerPC (MPC601UM §6.8.3.2, Table 6-16).
 * Word 0: manual bits: 0 V | 1-24 VSID | 25 H | 26-31 API
 * Word 1: manual bits: 0-19 PPN | 23 R | 24 C | 25-27 WIM | 30-31 PP  */
bitfield Pte0 : bits(32) = {
  V    : 31,
  VSID : 30 .. 7,
  H    : 6,
  API  : 5 .. 0
}
bitfield Pte1 : bits(32) = {
  PPN : 31 .. 12,
  R   : 8,
  C   : 7,
  WIM : 6 .. 4,
  PP  : 1 .. 0
}

/* Memory/cache access mode for an untranslated access: write-back, caching
 * enabled, coherency enforced (§6.3, §6.6). */
let wim_direct : bits(3) = 0b001

/* Does this access use address translation?  (MSR[IT] for fetch, MSR[DT]
 * for data.) */
val translation_enabled : MemoryAccess -> bool
function translation_enabled(acc) =
  match acc {
    Mem_fetch => MSR[IT] == 0b1,
    _            => MSR[DT] == 0b1
  }

val is_store_access : MemoryAccess -> bool
function is_store_access(acc) =
  match acc {
    Mem_store => true,
    _            => false
  }

/* --- Protection --------------------------------------------------------- */

/* The general memory protection mechanism (§6.4), shared by block and page
 * translation: the caller picks the key bit (Ks for supervisor accesses, Ku
 * for user ones) and supplies the PP field of the BAT entry or PTE.
 * Table 6-8 lists the prohibited combinations; everything else is allowed.
 * An instruction fetch is a read. */
val protection_ok : (bits(1), bits(2), MemoryAccess) -> bool
function protection_ok(key, pp, acc) = {
  let store = is_store_access(acc);
  match (key, pp) {
    (0b1, 0b00) => false,               /* no access             */
    (0b1, 0b01) => not_bool(store),     /* read only             */
    (_,   0b11) => not_bool(store),     /* read only, either key */
    (_,   _)    => true
  }
}

/* Key bit for an access to a segment: Ks in supervisor mode, Ku in user mode
 * (§6.4).  The block mechanism selects the same way out of the upper BAT
 * register — that lives in the core's BAT code. */
val segment_key : SegReg -> bits(1)
function segment_key(sr) = if MSR[PR] == 0b1 then sr[Ku] else sr[Ks]

/* --- Hashed page table -------------------------------------------------- */

/* Physical address of the page table entry group selected by a hash value
 * (§6.9.1.4, Figure 6-19):
 *   PA[0:6]   = SDR1[HTABORG] bits 0-6      (never masked)
 *   PA[7:15]  = SDR1[HTABORG] bits 7-15 OR (hash[0:8] AND SDR1[HTABMASK])
 *   PA[16:25] = hash[9:18]                  (the low 10 bits of the hash)
 *   PA[26:31] = 0                           (PTE0 of the group)             */
val pteg_addr : bits(19) -> bits(32)
function pteg_addr(hash) =
  (SDR1[HTABORG] | (zeros(7) @ (hash[18 .. 10] & SDR1[HTABMASK])))
    @ hash[9 .. 0] @ zeros(6)

/* Search the eight PTEs of one PTEG for a match (§6.9.2 steps 2-7): the
 * entry must be valid, belong to the hash class being searched, and carry
 * the VSID and abbreviated page index of the virtual address.  Returns the
 * physical address of the matching entry's first word. */
val pteg_search : (bits(32), bits(1), bits(24), bits(6)) -> option(bits(32))
function pteg_search(base, h, vsid, api) = {
  var hit : bool = false;
  var hit_addr : bits(32) = zeros(32);
  foreach (i from 0 to 7) {
    if not_bool(hit) then {
      let addr = base + (8 * i);
      let pte0 = Mk_Pte0(phys_read_pte(addr));
      if (pte0[V] == 0b1) & (pte0[H] == h) & (pte0[VSID] == vsid)
         & (pte0[API] == api) then {
        hit = true;
        hit_addr = addr
      }
    }
  };
  if hit then Some(hit_addr) else None()
}

/* Page address translation (§6.8.3, §6.9).  The 32-bit effective address
 * becomes a 52-bit virtual address — VSID from the segment register, then
 * EA[4:19] as the page index and EA[20:31] as the byte offset — and the page
 * table maps its virtual page number to a physical page number. */
val page_translate : (SegReg, word, MemoryAccess) -> TranslationResult
function page_translate(sr, ea, acc) = {
  let vsid = sr[VSID];
  let api : bits(6) = ea[27 .. 22];       /* VA[24:29] = EA[4:9]  */
  /* Primary hash (§6.9.1.3, Figure 6-18): the low 19 bits of the VSID xor
   * the 16-bit page index widened with three high-order zeros.  The
   * secondary hash is its one's complement. */
  let hash1 : bits(19) = xor_vec(vsid[18 .. 0], 0b000 @ ea[27 .. 12]);
  let found : option(bits(32)) = match pteg_search(pteg_addr(hash1), 0b0, vsid, api) {
    Some(a) => Some(a),
    None()  => pteg_search(pteg_addr(not_vec(hash1)), 0b1, vsid, api)
  };
  match found {
    None() => TR_Fault(Fault_PageFault),
    Some(pte_addr) => {
      let pte1 = Mk_Pte1(phys_read_pte(pte_addr + 4));
      let ok = protection_ok(segment_key(sr), pte1[PP], acc);
      /* Page history recording (§6.8.4).  R is set on every
       * reference, including one the protection mechanism goes on to reject
       * (§6.8.4.1, Figure 6-23); C only when a store is actually permitted
       * (§6.8.4.2, §6.8.5).  dcbt/dcbtst would need an exemption from both
       * (§6.8.4) — they never reach here, because with no cache to prefetch
       * into and no exception to report they are pure no-ops. */
      let hist : Pte1 = [pte1 with R = 0b1,
                              C = if ok & is_store_access(acc) then 0b1
                                  else pte1[C]];
      if hist.bits != pte1.bits then phys_write_pte(pte_addr + 4, hist.bits);
      if ok then TR_Address(pte1[PPN] @ ea[11 .. 0], pte1[WIM])
      else TR_Fault(Fault_Protection)
    }
  }
}

/* --- I/O controller interface segments ---------------------------------- */

/* Is this address in an I/O controller interface segment that is NOT
 * memory-forced?  This is the line the manual draws for two separate rules:
 *
 *  - §6.10.5: lwarx, stwcx. and lscbx may not be used there, and take a data
 *    access exception with DSISR[5] (Fault_IOSegUnsupported) if they are;
 *  - §3.8.2: a cache control instruction is a no-op there, while one in a
 *    MEMORY-FORCED segment "translates the address appropriately and performs
 *    the cache operation based on that address".
 *
 * That second rule is why the predicate excludes BUID x'07F' rather than
 * testing SR[T] alone: the ch. 10 cache pages and §6.10.6 both say flatly
 * "if EA specifies a memory address for which SR[T]=1, the instruction is
 * treated as a no-op", but §3.8.2 is the one that distinguishes the two BUID
 * cases, and being the specific statement it wins.
 *
 * §5.4.6.1.2's floating-point rule uses the same line (M.8). */
val nonforced_io_segment : word -> bool
function nonforced_io_segment(ea) = {
  let sr = rSR(ea[31 .. 28]);
  (sr[T] == 0b1) & (sr[BUID] != 0b001111111)
}

/* I/O controller interface segment access, T=1 (§6.10).  601/POWER only:
 * later cores call this the direct-store facility (603) or drop it (604).
 *
 * The BUID x'07F' encoding is the memory-forced case (§6.10.4): the access
 * becomes an ordinary memory access whose physical address is the segment
 * register's low four bits followed by EA[4:31], bypassing every protection
 * mechanism, with WIM = 0b011 (cache-inhibited and global).  This maps a
 * whole 256 MB segment through one register and no page tables.
 *
 * Every other BUID names a device on the I/O controller interface, reached
 * with a two-packet bus protocol (§6.10.2, §9.6) that has nothing behind it
 * in this model — hence the throw.  A fetch from such a segment is an
 * instruction access exception instead (§6.8.2.2), and the 601 sets no SRR1
 * bits for it where the architecture sets bit 3 (Table 6-3, §5.4.4).
 * Protection is not enforced here at all: the key bit is passed to the
 * device, which may or may not act on it (§6.10.3).
 *
 * The cache instructions are no-ops in these segments (§6.10.6); cache_op
 * and dcbz check for that themselves (ppc_insts_cache.sail). */
val io_segment_translate : (SegReg, word, MemoryAccess) -> TranslationResult
function io_segment_translate(sr, ea, acc) =
  if sr[BUID] == 0b001111111 then
    TR_Address(sr[P1] @ ea[27 .. 0], 0b011)
  else match acc {
    Mem_fetch => TR_Fault(Fault_IOSegFetch),
    _ => throw(Model_unimplemented("I/O controller interface transaction"))
  }

/* --- Top-level translation ---------------------------------------------- */

/* Block, then page, for an address in a memory segment (Figure 6-3).  A BAT
 * hit wins outright, and a protection violation inside the matching block is
 * a fault rather than a fall-through to the page tables. */
val translate_mapped : (SegReg, word, MemoryAccess) -> TranslationResult
function translate_mapped(sr, ea, acc) =
  match core_bat_translate(ea, acc) {
    BAT_Hit(pa, wim) => TR_Address(pa, wim),
    BAT_Violation()  => TR_Fault(Fault_Protection),
    BAT_Miss()       => page_translate(sr, ea, acc)
  }

val translate_addr : (word, MemoryAccess) -> TranslationResult
function translate_addr(ea, acc) = {
  let sr = rSR(ea[31 .. 28]);
  match acc {
    /* Fetch: MSR[IT] is checked first, so an I/O controller interface
     * segment is not even looked at with translation off (§6.8.2.2). */
    Mem_fetch =>
      if MSR[IT] == 0b0 then TR_Address(ea, wim_direct)
      else if sr[T] == 0b1 then io_segment_translate(sr, ea, acc)
      else translate_mapped(sr, ea, acc),
    /* Data: the T bit is checked BEFORE MSR[DT] (§6.5.2, Figure 6-4), which
     * is what makes an I/O controller interface access work with data
     * translation disabled. */
    _ =>
      if sr[T] == 0b1 then io_segment_translate(sr, ea, acc)
      else if MSR[DT] == 0b0 then TR_Address(ea, wim_direct)
      else translate_mapped(sr, ea, acc)
  }
}

$endif
