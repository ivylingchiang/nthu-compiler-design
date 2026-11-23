#!/usr/bin/env bash
# HW3 Bonus tests (no board needed). For each bonus/testcases/*.c:
#
#   1. Expected: compile the test with host gcc, intrinsics from the C reference (pext_ref.h)
#   2. Actual: codegen --rv32 --pext-emulate, run on RV32 Spike
#      (P-extension instructions become calls to equivalent C functions, same operand order as the real output)
#   3. Real output: codegen --rv32 builds the codegen.S for the board; P-extension instructions are
#      replaced with nop and assembled with GNU as to check the rest is valid RV32 and the intrinsic count matches
#
# Output goes to build/bonus/<n>/; its codegen.S is the file for the Arduino project.
# Run inside the container: dev/run.sh make -C hw3-codegen test-bonus
set -uo pipefail

cd "$(dirname "$0")/../.."
root="$(pwd)"
tests="$root/bonus/tests"
rv32_cc=(riscv-none-elf-gcc -march=rv32imac -mabi=ilp32)
rv32_sim=(spike --isa=rv32imac /opt/riscv32/riscv-none-elf/bin/pk)
pext_re='^[[:space:]]*(ukadd8|uksub8|cmpeq8|ucmplt8)[[:space:]]'

pass=0
fail=0

for src in bonus/testcases/*.c; do
    name="$(basename "$src" .c)"
    dir="build/bonus/$name"
    mkdir -p "$dir"
    why=""

    # 1. Expected
    if ! gcc -w -include stdint.h -include "$tests/native_intrinsics.h" -I "$tests" \
            -o "$dir/native" "$src" "$tests/main.c" 2> "$dir/native.err"; then
        why="native build failed"
    else
        "$dir/native" > "$dir/expected.txt"
    fi

    # 2. Emulated run
    if [[ -z "$why" ]]; then
        mkdir -p "$dir/emulate"
        if ! (cd "$dir/emulate" && "$root/codegen" --rv32 --pext-emulate < "$root/$src") 2> "$dir/codegen.err"; then
            why="codegen error: $(head -1 "$dir/codegen.err")"
        elif ! "${rv32_cc[@]}" -I "$tests" -o "$dir/prog" "$tests/main.c" "$tests/pext_emulate.c" \
                "$dir/emulate/codegen.S" 2> "$dir/gcc.err"; then
            why="assemble/link error, see $dir/gcc.err"
        else
            timeout 20 "${rv32_sim[@]}" "$dir/prog" 2>&1 | grep '^ext_dsp_codegen' > "$dir/output.txt"
            diff -u "$dir/expected.txt" "$dir/output.txt" > "$dir/output.diff" || why="output differs, see $dir/output.diff"
        fi
    fi

    # 3. Real output
    if [[ -z "$why" ]]; then
        if ! (cd "$dir" && "$root/codegen" --rv32 < "$root/$src") 2>> "$dir/codegen.err"; then
            why="codegen error (real mode)"
        else
            n_insn=$(grep -cE "$pext_re" "$dir/codegen.S")
            n_call=$(grep -c 'jal ra, __pext_' "$dir/emulate/codegen.S")
            sed -E "s/$pext_re.*/  nop/" "$dir/codegen.S" > "$dir/codegen.nop.S"
            if [[ "$n_insn" -eq 0 || "$n_insn" -ne "$n_call" ]]; then
                why="expected $n_call P-extension instructions, found $n_insn"
            elif grep -q '__rv__' "$dir/codegen.S"; then
                why="codegen.S still calls an __rv__ function"
            elif ! "${rv32_cc[@]}" -c -o "$dir/codegen.o" "$dir/codegen.nop.S" 2> "$dir/as.err"; then
                why="real codegen.S is not valid RV32 assembly, see $dir/as.err"
            fi
        fi
    fi

    if [[ -z "$why" ]]; then
        echo "PASS $name  ($(wc -l < "$dir/expected.txt" | tr -d ' ') inputs, $n_insn P-ext instructions)"
        pass=$((pass + 1))
    else
        echo "FAIL $name  ($why)"
        fail=$((fail + 1))
    fi
done

echo "[bonus] $pass passed, $fail failed"
[[ $fail -eq 0 ]]
