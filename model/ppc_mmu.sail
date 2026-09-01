/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_mmu.sail — address translation, common 32-bit PowerPC skeleton.
 *
 * Translation order (MPC601UM Figure 6-4, Table 6-10; MPC603EUM Figure 5-5
 * and 5-6; MPC750UM Figure 5-5 and 5-6):
 *   1. Fetch with MSR[IT]=0, or data access with MSR[DT]=0: direct
 *      (untranslated), PA = EA, WIMG = 0b0010.
 *   2. Segment register with T=1 -> the direct-store facility, which the 601
 *      calls the I/O controller interface.  WHERE this check sits is
 *      core-specific and core_direct_store_first says which: the 601 takes it
 *      before MSR[DT] and ignores the BAT array for such a segment (§6.5.2.2,
 *      §6.7.2), where every later core reaches the segment descriptor only
 *      after the BAT array has missed and only with translation enabled.
 *      WHAT it does is core_direct_store.
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
 * Word 1: manual bits: 0-19 PPN | 23 R | 24 C | 25-28 WIMG | 30-31 PP
 *
 * The G (guarded) bit, manual bit 28, is defined on the 603e, 604, 604e and
 * 750 and RESERVED on the 601 (MPC601UM Table 6-16 stops at WIM).  It is read
 * unconditionally here, so on the 601 a PTE with that reserved bit set yields
 * a non-zero G — which no 601 code path inspects, because the facilities that
 * consume G (guarded-storage fetch and speculative-access rules) exist only on
 * the cores that define the bit. */
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
  WIMG : 6 .. 3,
  PP   : 1 .. 0
}

/* Memory/cache access mode bits, by name.  Manual order, so the leftmost bit
 * of the field is W and the rightmost is G; see TranslationResult in
 * ppc_types.sail for why the field is four bits wide on every core. */
val wimg_write_through : bits(4) -> bool
function wimg_write_through(m) = m[3] == bitone

val wimg_cache_inhibited : bits(4) -> bool
function wimg_cache_inhibited(m) = m[2] == bitone

val wimg_guarded : bits(4) -> bool
function wimg_guarded(m) = m[0] == bitone

/* Memory/cache access mode for an untranslated access: write-back, caching
 * enabled, coherency enforced, not guarded (§6.3, §6.6). */
let wimg_direct : bits(4) = 0b0010

/* Does this access use address translation?  (MSR[IT] for fetch, MSR[DT]
 * for data.) */
val translation_enabled : MemoryAccess -> bool
function translation_enabled(acc) =
  match acc {
    Mem_fetch => MSR[IT] == 0b1,
    _            => MSR[DT] == 0b1
  }

val is_fetch_access : MemoryAccess -> bool
function is_fetch_access(acc) =
  match acc {
    Mem_fetch => true,
    _         => false
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
/* The page table half of page_translate, declared here because Sail requires
 * declaration before use and page_translate calls it. */
val page_translate_pte : (SegReg, word, MemoryAccess) -> TranslationResult

val page_translate : (SegReg, word, MemoryAccess) -> TranslationResult
function page_translate(sr, ea, acc) = {
  /* No-execute (§5.1.5.2 on the 603e and 750): a fetch from a segment with
   * N set faults before the page table is consulted.  Blocks have no N bit,
   * so this belongs on the page path and not in translate_mapped. */
  if core_segment_no_execute() & (sr[N] == 0b1) & is_fetch_access(acc) then
    TR_Fault(Fault_DirectStore)
  else page_translate_pte(sr, ea, acc)
}

/* The page table half of page_translate, split out so the no-execute test
 * above reads as a guard rather than wrapping the whole body in an else. */
function page_translate_pte(sr, ea, acc) = {
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
      if ok then TR_Address(pte1[PPN] @ ea[11 .. 0], pte1[WIMG])
      else TR_Fault(Fault_Protection)
    }
  }
}

/* --- Direct-store segments (SR[T] = 1) ---------------------------------- */

/* Is this address in a direct-store segment that is NOT memory-forced?  This
 * is the line the 601 manual draws for two separate rules:
 *
 *  - §6.10.5: lwarx, stwcx. and lscbx may not be used there, and take a data
 *    access exception with DSISR[5] (Fault_IOSegUnsupported) if they are;
 *  - §3.8.2: a cache control instruction is a no-op there, while one in a
 *    MEMORY-FORCED segment "translates the address appropriately and performs
 *    the cache operation based on that address".
 *
 * That second rule is why the predicate excludes the memory-forced case
 * rather than testing SR[T] alone: the ch. 10 cache pages and §6.10.6 both
 * say flatly "if EA specifies a memory address for which SR[T]=1, the
 * instruction is treated as a no-op", but §3.8.2 is the one that
 * distinguishes the two cases, and being the specific statement it wins.
 * §5.4.6.1.2's floating-point rule uses the same line (M.8).
 *
 * Only the 601 has memory-forced segments, so on every later core this is
 * simply SR[T] = 1 — which is exactly what those cores' manuals say for the
 * same rules (MPC603EUM §3.4.3: "any cache control instruction that generates
 * an effective address that corresponds to a direct-store segment (SR[T] = 1)
 * is treated as a no-op"). */
val nonforced_io_segment : word -> bool
function nonforced_io_segment(ea) = {
  let sr = rSR(ea[31 .. 28]);
  (sr[T] == 0b1) & not_bool(core_memory_forced_segment(ea))
}

/* --- Top-level translation ---------------------------------------------- */

/* Block, then page, for an address in a memory segment (Figure 6-3).  A BAT
 * hit wins outright, and a protection violation inside the matching block is
 * a fault rather than a fall-through to the page tables. */
val translate_mapped : (SegReg, word, MemoryAccess) -> TranslationResult
function translate_mapped(sr, ea, acc) =
  match core_bat_translate(ea, acc) {
    BAT_Hit(pa, wimg) => TR_Address(pa, wimg),
    BAT_Violation()   => TR_Fault(Fault_Protection),
    BAT_Miss()        => page_translate(sr, ea, acc)
  }

/* Block, then segment, for a core that consults the BAT array before the
 * segment descriptor — every core but the 601 (MPC603EUM Figure 5-5/5-6,
 * MPC750UM Figure 5-5/5-6).  A BAT hit wins outright and the T bit is never
 * reached, which is the architected order the 601 inverts. */
val translate_bat_then_segment : (word, MemoryAccess) -> TranslationResult
function translate_bat_then_segment(ea, acc) =
  match core_bat_translate(ea, acc) {
    BAT_Hit(pa, wimg) => TR_Address(pa, wimg),
    BAT_Violation()   => TR_Fault(Fault_Protection),
    BAT_Miss()        => {
      let sr = rSR(ea[31 .. 28]);
      if sr[T] == 0b1 then core_direct_store(ea, acc)
      else page_translate(sr, ea, acc)
    }
  }

val translate_addr : (word, MemoryAccess) -> TranslationResult
function translate_addr(ea, acc) = {
  let sr = rSR(ea[31 .. 28]);
  match acc {
    /* Fetch: the MSR translation-enable bit is checked first on every core,
     * so a direct-store segment is not even looked at with translation off
     * (MPC601UM §6.8.2.2, and the same order in Figure 5-5 of the 603e and
     * 750 manuals). */
    Mem_fetch =>
      if MSR[IT] == 0b0 then TR_Address(ea, wimg_direct)
      else if core_direct_store_first() then {
        if sr[T] == 0b1 then core_direct_store(ea, acc)
        else translate_mapped(sr, ea, acc)
      } else translate_bat_then_segment(ea, acc),
    /* Data: on the 601 the T bit is checked BEFORE MSR[DT] (§6.5.2,
     * Figure 6-4), which is what makes an I/O controller interface access
     * work with data translation disabled; every later core checks MSR[DR]
     * first and reaches the T bit only after the BAT array misses. */
    _ =>
      if core_direct_store_first() then {
        if sr[T] == 0b1 then core_direct_store(ea, acc)
        else if MSR[DT] == 0b0 then TR_Address(ea, wimg_direct)
        else translate_mapped(sr, ea, acc)
      } else if MSR[DT] == 0b0 then TR_Address(ea, wimg_direct)
      else translate_bat_then_segment(ea, acc)
  }
}

$endif
