/*=======================================================================================*/
/*  powerpc-sail: A Sail model of the PowerPC ISA (PowerPC 601 first)                    */
/*  SPDX-License-Identifier: MIT (see LICENSE)                                           */
/*=======================================================================================*/

/* ppc_types.sail — architecture-level enumerations and result types shared by
 * all cores. */

$ifndef _PPC_TYPES
$define _PPC_TYPES

/* Result of attempting to execute one instruction.  The manual describes
 * sequential execution in terms of an instruction COMPLETING — it never uses
 * "retire", which is a pipeline term — or an exception being taken instead. */
enum Completion = {
  COMPLETED,        /* instruction completed architecturally */
  EXCEPTION_TAKEN   /* instruction did not complete; an exception was
                       signalled (SRR0/SRR1/MSR/NIA already updated by
                       take_exception) */
}

/* MSR[PR], the "privilege level bit" (§2.3.1): 0 = supervisor level,
 * 1 = user level. */
enum PrivilegeLevel = {Supervisor, User}

/* Kind of memory access, used by translation & protection checks. */
enum MemoryAccess = {
  Mem_fetch,
  Mem_load,
  Mem_store
}

/* Which set of §5.4.6.1 boundary rules an access obeys.  The 256 MB rule is
 * common to all three; they differ over the 4 KB one, and over what
 * little-endian mode makes of them (§5.4.6.3).  See alignment_fault. */
enum AlignRule = {
  Align_operand,      /* an ordinary load or store: a 4 KB crossing faults,
                         and in little-endian mode so does any misalignment  */
  Align_string,       /* a string or multiple: a 4 KB crossing faults only if
                         the operand is not word-aligned, and little-endian
                         mode faults outright                                */
  Align_string_4k,    /* a string whose 4 KB crossing faults whatever its
                         alignment (§5.4.6.1.4).  The only instruction with
                         this rule is a POWER holdover the 601 implements    */
  Align_fp            /* a floating-point operand: as Align_operand, plus
                         §5.4.6.1.2's rule that any floating-point access to
                         an I/O controller interface segment that is not
                         memory-forced faults whatever its alignment         */
}

/* Exceptions (interrupts, in later PowerPC terminology).  This is the union
 * of the standard 32-bit PowerPC OEA exceptions and 601-specific ones; each
 * core maps the members it implements onto vector offsets via the
 * core_exception_vector hook (see ppc_core_iface.sail).
 * Reference: MPC601UM Table 5-2 / §5.4. */
enum PPCException = {
  E_Reset,          /* 0x00100 */
  E_MachineCheck,   /* 0x00200 */
  E_DataAccess,     /* 0x00300 DSI  */
  E_InstAccess,     /* 0x00400 ISI  */
  E_External,       /* 0x00500 */
  E_Alignment,      /* 0x00600 */
  E_Program,        /* 0x00700 */
  E_FPUnavailable,  /* 0x00800 */
  E_Decrementer,    /* 0x00900 */
  E_IOCtlError,     /* 0x00A00 -- 601-only: I/O controller interface error (§5.4.10) */
  E_SystemCall,     /* 0x00C00 */
  E_Trace,          /* 0x00D00 -- NOT used by the 601 (601 uses run-mode at 0x02000) */
  E_FPAssist,       /* 0x00E00 -- NOT implemented on the 601 */
  E_RunMode         /* 0x02000 -- 601-only: run-mode / trace exception (§5.4.11) */
}

/* Sub-causes of the program exception; select which SRR1 bit is set on entry.
 * MPC601UM §5.4.7: SRR1[11]=FP-enabled, [12]=illegal, [13]=privileged, [14]=trap. */
enum ProgramCause = {
  Prog_FPEnabled,
  Prog_Illegal,
  Prog_Privileged,
  Prog_Trap
}

/* Why a translation failed.  Every cause below turns into a data access
 * exception for a load or store and an instruction access exception for a
 * fetch, so the cause alone — plus the access type the caller already knows —
 * determines the whole fault image (DSISR/DAR, or the SRR1 high half).
 * Tables 5-10, 5-11 and 6-3. */
enum FaultCause = {
  Fault_PageFault,        /* no matching PTE, and no BAT covered the address:
                             DSISR[1] / SRR1[1] and SRR1[10]                 */
  Fault_Protection,       /* key + PP forbid the access (§6.4):
                             DSISR[4] / SRR1[4]                              */
  Fault_IOSegFetch,       /* fetch from an I/O controller interface segment
                             that is not memory-forced (§6.10): the 601 sets
                             NO SRR1 bits, where the architecture sets [3]    */
  Fault_IOSegUnsupported, /* lwarx/stwcx./lscbx in such a segment (§6.10.5):
                             DSISR[5]                                        */
  Fault_DataBreakpoint    /* DABR match (§2.3.3.13.4): DSISR[9].  Not a
                             translation failure and never produced by
                             translate_addr — the data path raises it before
                             translating, because the compare is on the
                             effective address and runs whether or not
                             translation is enabled (§6.1.9)                 */
}

/* Result of address translation (ppc_mmu.sail).  A success carries the
 * memory/cache access mode (WIM, §6.3) alongside the physical address: it is
 * a property of whatever mechanism did the translation (BAT register, PTE, or
 * a fixed value for the untranslated and I/O cases), and instructions whose
 * behaviour depends on it — dcbz faults when W or I is set (§5.4.6) — have no
 * other way to learn it. */
union TranslationResult = {
  TR_Address : (bits(32), bits(3)),      /* physical address, WIM */
  TR_Fault : FaultCause
}

/* Result of a block address translation (the core_bat_translate hook).  A
 * protection violation inside a matching block is NOT a miss: it must not
 * fall through to page translation (§6.7.4, Figure 6-9). */
union BatResult = {
  BAT_Miss : unit,                       /* no entry covers this address */
  BAT_Hit : (bits(32), bits(3)),         /* physical address, WIM */
  BAT_Violation : unit                   /* matched, but protection forbids it */
}

/* Internal (model, not architecture) failures.  Sail reserves the type name
 * `exception` for whatever `throw`/`try` carry, so only the constructors are
 * ours to name. */
union exception = {
  Model_unimplemented : string,
  Model_internal_error : string
}

$endif
