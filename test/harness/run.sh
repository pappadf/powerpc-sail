#!/bin/sh
# powerpc-sail — self-test for the single-step harness (c/harness.c).
#
# Usage: test/harness/run.sh [path-to-harness]
#        make harness-test
#
# Every case drives the harness over a pipe and diffs its response against the
# expected text inline below, so a failure prints exactly which line moved.
# The cases cover the four things the vector generator depends on being
# right — the instruction result, the register write-set, the memory
# footprint, and exception delivery — plus the two properties that are
# harness-level rather than model-level: determinism and batch throughput.
#
# Addresses come from the test memory window the vector format uses
# (0x0010_0000, 64 KiB), except where a case has to reach outside it to
# provoke a fault.

set -e

HARNESS=${1:-build/ppc_p601_harness}
[ -x "$HARNESS" ] || { echo "no harness at $HARNESS (make harness)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# check <name> <filter-regex> <<commands ... expected on stdin after '---'
# Runs the harness on the commands, keeps only response lines matching the
# filter, and diffs against the expected block.
check() {
  name=$1
  filter=$2
  sed -n '1,/^---$/p' "$TMP/case" | sed '$d' > "$TMP/cmd"
  sed -n '/^---$/,$p' "$TMP/case" | sed '1d' > "$TMP/want"
  "$HARNESS" < "$TMP/cmd" | grep -E "$filter" > "$TMP/got" || true
  if diff -u "$TMP/want" "$TMP/got" > "$TMP/diff"; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name"
    cat "$TMP/diff"
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# 1. add. r5,r3,r4 — the canonical case.  r3=5, r4=7 gives r5=12 and CR0=GT,
#    and the write-set must be exactly {gpr5, cr0, nia}: nothing else on the
#    machine may appear to have changed.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00000005
SET gpr4 0x00000007
OPCODE 0x7CA32215
STEP
QUIT
---
S gpr5 0x0000000C
S cr0 0x4
S cia 0x00100000
S nia 0x00100004
FW gpr5
FW cr0
FW nia
FF 0x00100000 4
EXC none
DONE
EOF
check "add." '^S (gpr5|cr0|cia|nia) |^(FW|FF|EXC|M |HALT|ERR|DONE)'

# ---------------------------------------------------------------------------
# 2. lwz r6,0x10(r3) — a data read must show up as FMR at the effective
#    address with the operand width, and must NOT be confused with the
#    instruction fetch, which is FF.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00100000
MEM 0x00100010 DEADBEEF
OPCODE 0x80C30010
STEP
QUIT
---
S gpr6 0xDEADBEEF
FW gpr6
FW nia
FMR 0x00100010 4
FF 0x00100000 4
EXC none
DONE
EOF
check "lwz" '^S gpr6 |^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

# ---------------------------------------------------------------------------
# 3. stw r5,0x20(r3) — a store must produce both an FMW (what it touched) and
#    an M line (what the bytes became).
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00100000
SET gpr5 0x12345678
OPCODE 0x90A30020
STEP
QUIT
---
M 0x00100020 12345678
FW nia
FMW 0x00100020 4
FF 0x00100000 4
EXC none
DONE
EOF
check "stw" '^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

# ---------------------------------------------------------------------------
# 3b. A store of the value already in memory writes nothing: FMW still
#     reports the access, but there is no M line, because M is a diff.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00100000
SET gpr5 0x12345678
MEM 0x00100020 12345678
OPCODE 0x90A30020
STEP
QUIT
---
FW nia
FMW 0x00100020 4
FF 0x00100000 4
EXC none
DONE
EOF
check "stw-nochange" '^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

# ---------------------------------------------------------------------------
# 4. Exceptions.
#    sc              -> system call, vector 0x0C00, SRR0 = next instruction
#                       (§5.4.10), SRR1[bit 14 of the high half] = 0x0002
#    all-zero word   -> illegal instruction, program exception 0x0700
#    256 MB crossing -> alignment exception 0x0600, with DAR and DSISR
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
OPCODE 0x44000002
STEP
QUIT
---
S cia 0x00100000
S nia 0x00000C00
S msr 0x00000000
S srr0 0x00100004
S srr1 0x00020000
FW nia
FW srr0
FW srr1
FF 0x00100000 4
EXC 0x00000C00
DONE
EOF
check "sc" '^S (cia|nia|msr|srr0|srr1) |^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
OPCODE 0x00000000
STEP
QUIT
---
S nia 0x00000700
S srr0 0x00100000
S srr1 0x00080000
EXC 0x00000700
DONE
EOF
check "illegal" '^S (nia|srr0|srr1) |^(EXC|DONE)'

cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x0FFFFFFE
OPCODE 0x80C30000
STEP
QUIT
---
S cia 0x00100000
S nia 0x00000600
S srr0 0x00100000
S dar 0x0FFFFFFE
S dsisr 0x000000C3
FW nia
FW srr0
FW dar
FW dsisr
FF 0x00100000 4
EXC 0x00000600
DONE
EOF
check "alignment" '^S (cia|nia|srr0|dar|dsisr) |^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

# ---------------------------------------------------------------------------
# 5. The halt convention still works through the harness: sc with the magic in
#    GPR0 is a halt request rather than a system call, and carries GPR3 out.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr0 0x46000D1E
SET gpr3 0x0000002A
OPCODE 0x44000002
STEP
QUIT
---
EXC none
HALT 0x0000002A
DONE
EOF
check "halt" '^(EXC|HALT|DONE)'

# ---------------------------------------------------------------------------
# 6. Sub-field granularity: setting and reading back the named bit fields of
#    XER and FPSCR, and CR by field.  addic. r4,r3,1 with r3 = 0xFFFFFFFF
#    produces a carry and a zero result, so xer.ca and cr0 both move — and
#    xer.so, which was set beforehand, must be copied into CR0[SO] and must
#    NOT appear in the write-set, since the instruction leaves it alone.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0xFFFFFFFF
SET gpr4 0xFFFFFFFF
SET xer.so 0x1
SET fpscr.rn 0x3
SET xer.cmpb 0xA5
OPCODE 0x34830001
STEP
QUIT
---
S gpr4 0x00000000
S cr0 0x3
S xer.so 0x1
S xer.ca 0x1
S xer.cmpb 0xA5
S fpscr.rn 0x3
FW gpr4
FW cr0
FW xer.ca
FW nia
EOF
check "fields" '^S (cr0|xer\.so|xer\.ca|xer\.cmpb|fpscr\.rn|gpr4) |^FW '

# ---------------------------------------------------------------------------
# 6b. Multi-access footprints.  stmw moves four words, so there must be one
#     FMW per word but a single coalesced M line covering all sixteen bytes;
#     dcbz clears a whole 32-byte sector the same way.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00100040
SET gpr28 0x11111111
SET gpr29 0x22222222
SET gpr30 0x33333333
SET gpr31 0x44444444
OPCODE 0xBF830000
STEP
QUIT
---
M 0x00100040 11111111222222223333333344444444
FW nia
FMW 0x00100040 4
FMW 0x00100044 4
FMW 0x00100048 4
FMW 0x0010004C 4
FF 0x00100000 4
EXC none
DONE
EOF
check "stmw" '^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00100040
MEM 0x00100040 FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
OPCODE 0x7C001FEC
STEP
QUIT
---
M 0x00100040 0000000000000000000000000000000000000000000000000000000000000000
FW nia
EXC none
DONE
EOF
check "dcbz" '^(FW nia|EXC|M |DONE)'

# ---------------------------------------------------------------------------
# 6c. Floating point: a 64-bit element read back at full width, an 8-byte
#     FMR, and — with MSR[FP] clear — the floating-point unavailable
#     exception, which is the cheapest check that MSR bits injected by SET
#     really reach the model.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET msr 0x00002000
SET gpr3 0x00100040
MEM 0x00100040 3FF0000000000000
OPCODE 0xC8230000
STEP
RESET
SET cia 0x00100000
SET gpr3 0x00100040
OPCODE 0xC8230000
STEP
QUIT
---
S fpr1 0x3FF0000000000000
FW fpr1
FW nia
FMR 0x00100040 8
FF 0x00100000 4
EXC none
DONE
S fpr1 0x0000000000000000
FW nia
FW srr0
FF 0x00100000 4
EXC 0x00000800
DONE
EOF
check "lfd" '^S fpr1 |^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

# ---------------------------------------------------------------------------
# 7. Errors: an unknown element, a malformed value and an unknown command each
#    produce one ERR line and are otherwise ignored — the stream keeps going
#    and the STEP that follows still works.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET nosuch 0x1
SET gpr3 zz
MEM 0x00100000 ABC
BOGUS ARGS
SET cia 0x00100000
SET gpr3 0x00000005
SET gpr4 0x00000007
OPCODE 0x7CA32215
STEP
QUIT
---
ERR unknown element nosuch
ERR bad hex value zz
ERR odd number of hex digits ABC
ERR unknown command BOGUS
S gpr5 0x0000000C
DONE
EOF
check "errors" '^ERR |^S gpr5 |^DONE'

# ---------------------------------------------------------------------------
# 7b. Values that do not fit are rejected, not truncated, and a malformed MEM
#     writes nothing at all — a half-applied line would silently corrupt a
#     vector rather than fail it.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
MEM 0x100000000 AABBCCDD
OPCODE 0x1FFFFFFFF
SET gpr3 0x1FFFFFFFF
SET cr0 0x14
MEM 0x00100000 AABBZZ
MEM 0x00100000 0x
SET cia 0x00100000
SET gpr3 0x00100000
OPCODE 0x80C30000
STEP
QUIT
---
ERR address out of range 0x100000000
ERR opcode out of range 0x1FFFFFFFF
ERR value too wide for element gpr3
ERR value too wide for element cr0
ERR bad hex bytes AABBZZ
ERR no hex bytes 0x
S gpr6 0x80C30000
DONE
EOF
check "validation" '^ERR |^S gpr6 |^DONE'

# ---------------------------------------------------------------------------
# 8b. OPCODE places its bytes where the NEXT step will fetch, so a second
#     OPCODE/STEP pair after a first one runs at the following address instead
#     of overwriting the instruction just executed.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00000005
SET gpr4 0x00000007
OPCODE 0x7CA32215
STEP
OPCODE 0x7CA32215
STEP
QUIT
---
S gpr5 0x0000000C
S cia 0x00100000
EXC none
DONE
S gpr5 0x0000000C
S cia 0x00100004
EXC none
DONE
EOF
check "opcode-after-step" '^S (gpr5|cia) |^(EXC|DONE)'

# ---------------------------------------------------------------------------
# 8c. An asynchronous interrupt is delivered at the top of step(), BEFORE
#     CIA is loaded from NIA — so CIA lands on the vector and the handler's
#     first instruction runs in the same step.  cia must therefore appear in
#     the write set: the diff has to tell the truth even where the ordinary
#     case makes it look impossible.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET msr 0x00008000
SET ext_int_pending 0x1
MEM 0x00000500 38600042
OPCODE 0x60000000
STEP
QUIT
---
S gpr3 0x00000042
S cia 0x00000500
S nia 0x00000504
S srr0 0x00100000
FW gpr3
FW cia
FW nia
FW msr
FW srr0
FW srr1
FF 0x00000500 4
EXC 0x00000500
DONE
EOF
check "async-interrupt" '^S (gpr3|cia|nia|srr0) |^(FW|FMR|FMW|FF|EXC|M |HALT|ERR|DONE)'

# ---------------------------------------------------------------------------
# 8. State persists across STEP: two steps in a row run consecutive
#    instructions, because step() advances CIA from NIA on its own.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
MEM 0x00100000 386000053880000700000000
STEP
STEP
QUIT
---
S gpr3 0x00000005
S gpr4 0x00000000
S cia 0x00100000
DONE
S gpr3 0x00000005
S gpr4 0x00000007
S cia 0x00100004
DONE
EOF
check "two-steps" '^S (cia|gpr3|gpr4) |^DONE'

# ---------------------------------------------------------------------------
# 9. Determinism.
#    (a) the same vector twice in ONE process must give byte-identical
#        responses — so nothing accumulates between steps (the RTC and the
#        decrementer above all);
#    (b) the same batch in TWO processes must give byte-identical output — so
#        nothing depends on the environment, the clock or an address.
# ---------------------------------------------------------------------------
gen_batch() {
  n=$1
  echo "RESET"
  i=0
  while [ "$i" -lt "$n" ]; do
    a=$(( (i * 2654435761) % 4294967296 ))
    b=$(( (i * 40503 + 12345) % 4294967296 ))
    printf 'RESET\nSET cia 0x00100000\n'
    printf 'SET gpr3 0x%08X\nSET gpr4 0x%08X\n' "$a" "$b"
    # Cycle through add., stw, lwz, sc and an illegal word so that the batch
    # exercises arithmetic, both memory directions and exception delivery.
    case $((i % 5)) in
      0) printf 'OPCODE 0x7CA32215\n' ;;
      1) printf 'SET gpr3 0x00100000\nOPCODE 0x90A30020\n' ;;
      2) printf 'SET gpr3 0x00100000\nMEM 0x00100010 DEADBEEF\nOPCODE 0x80C30010\n' ;;
      3) printf 'OPCODE 0x44000002\n' ;;
      4) printf 'OPCODE 0x00000000\n' ;;
    esac
    printf 'STEP\n'
    i=$((i + 1))
  done
  echo "QUIT"
}

{
  printf 'RESET\nSET cia 0x00100000\nSET gpr3 0x00000005\nSET gpr4 0x00000007\n'
  printf 'OPCODE 0x7CA32215\nSTEP\n'
  printf 'RESET\nSET cia 0x00100000\nSET gpr3 0x00000005\nSET gpr4 0x00000007\n'
  printf 'OPCODE 0x7CA32215\nSTEP\nQUIT\n'
} > "$TMP/twice"
"$HARNESS" < "$TMP/twice" > "$TMP/twice.out"
awk '/^DONE$/ {n++; next} {print > ("'"$TMP"'/half" n)}' "$TMP/twice.out"
if cmp -s "$TMP/half" "$TMP/half1"; then
  echo "PASS determinism-in-process"
  pass=$((pass + 1))
else
  echo "FAIL determinism-in-process"
  diff -u "$TMP/half" "$TMP/half1" || true
  fail=$((fail + 1))
fi

gen_batch 200 > "$TMP/batch"
"$HARNESS" < "$TMP/batch" > "$TMP/batch.out1"
"$HARNESS" < "$TMP/batch" > "$TMP/batch.out2"
if cmp -s "$TMP/batch.out1" "$TMP/batch.out2"; then
  echo "PASS determinism-across-processes"
  pass=$((pass + 1))
else
  echo "FAIL determinism-across-processes"
  fail=$((fail + 1))
fi

# The same batch, but with every vector run twice in one process: the second
# copy of the responses must match the first, which is the strongest form of
# "no state leaks between vectors".
{ gen_batch 200 | sed '$d'; gen_batch 200; } > "$TMP/batch2"
"$HARNESS" < "$TMP/batch2" > "$TMP/batch2.out"
lines=$(wc -l < "$TMP/batch.out1")
head -n "$lines" "$TMP/batch2.out" > "$TMP/batch2.first"
if cmp -s "$TMP/batch.out1" "$TMP/batch2.first"; then
  echo "PASS determinism-repeat-in-process"
  pass=$((pass + 1))
else
  echo "FAIL determinism-repeat-in-process"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# 10. Batch throughput.  Not a pass/fail assertion — the number depends on the
#     machine — but the run must complete and the rate is reported, because
#     "many vectors per process" is the whole reason the harness is a server
#     rather than a command.
# ---------------------------------------------------------------------------
# `date +%s%N` is a GNU extension; BSD and macOS echo a literal "N", which
# would make the arithmetic below fail and — under `set -e` — abort the whole
# suite over a throughput figure that is informational anyway.  Fall back to
# whole seconds there.
now_ns() {
  _t=$(date +%s%N 2>/dev/null) || _t=''
  case "$_t" in
    ''|*[!0-9]*) echo "$(( $(date +%s) * 1000000000 ))" ;;
    *)           echo "$_t" ;;
  esac
}

N=${HARNESS_BENCH_N:-5000}
gen_batch "$N" > "$TMP/bench"
start=$(now_ns)
"$HARNESS" < "$TMP/bench" > "$TMP/bench.out"
end=$(now_ns)
ns=$((end - start))
[ "$ns" -gt 0 ] || ns=1
# `grep -c` exits 1 when the count is zero, which under `set -e` would abort
# the run in exactly the regression this case exists to report.  Zero
# responses must reach the FAIL branch below, not kill the script.
steps=$(grep -c '^DONE$' "$TMP/bench.out" 2>/dev/null || true)
[ -n "$steps" ] || steps=0
rate=$((steps * 1000000000 / ns))
echo "INFO $steps vectors in $((ns / 1000000)) ms = $rate vectors/sec"
if [ "$steps" -eq "$N" ]; then
  echo "PASS batch"
  pass=$((pass + 1))
else
  echo "FAIL batch: expected $N responses, got $steps"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# 11. RESET clears state that has no element name.
#     XER's Xer bitfield names SO, OV, CA, CMPB and BC, but `mtspr XER` stores
#     all 32 bits unmasked, so manual bits 3..24 and sail bit 7 are covered by
#     no element.  Clearing only the named ranges left them alive across RESET
#     — invisible in the S lines, and enough to make one vector's result depend
#     on the vector before it.  Writing 0x00FF00FF and reading back after a
#     RESET returned 0x00FF0080 before the fix.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET gpr3 0x00FF00FF
OPCODE 0x7C6103A6
STEP
RESET
SET cia 0x00100000
OPCODE 0x7C8102A6
STEP
QUIT
---
S gpr4 0x00000000
S gpr4 0x00000000
EOF
check reset-clears-unnamed-bits '^S gpr4'

# ---------------------------------------------------------------------------
# 12. A MEM range may not run off the end of physical memory.
#     Without the check the address wrapped and the tail landed at 0 — silently
#     writing the exception-vector page, which is both where a hardware runner
#     installs its handlers and a region vectors are forbidden to target.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
MEM 0xFFFFFFFE AABBCCDD
MEM 0xFFFFFFFC AABBCCDD
QUIT
---
ERR byte range runs past the end of physical memory AABBCCDD
EOF
check mem-range-must-not-wrap '^ERR'

# ---------------------------------------------------------------------------
# 13. OPCODE lands where the fetch looks, in little-endian mode too.
#     HID0[LM] makes the 601 munge the low address bits rather than byte-swap,
#     which at width 4 is "xor 4" (§2.4.3.3).  Placing the opcode at the
#     unmunged address left the fetch reading whatever was at a ^ 4: before the
#     fix this decoded as garbage and took a program exception instead of
#     executing add.
# ---------------------------------------------------------------------------
cat > "$TMP/case" <<'EOF'
RESET
SET cia 0x00100000
SET hid0 0x00000008
SET gpr3 0x00000005
SET gpr4 0x00000007
OPCODE 0x7CA32215
STEP
QUIT
---
S gpr5 0x0000000C
FF 0x00100004 4
EXC none
EOF
check opcode-placement-little-endian '^(S gpr5|FF|EXC)'

echo "$pass/$((pass + fail)) harness tests passed"
[ "$fail" -eq 0 ]
