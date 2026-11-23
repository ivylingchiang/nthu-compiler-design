#!/usr/bin/env bash
# HW3 end-to-end tests: codegen -> riscv64-unknown-elf-gcc -> spike pk -> compare the Arduino log
#
#   tests/run.sh                 run all tests
#   tests/run.sh Pointer         run only tests whose name contains "Pointer"
#   TARGET=rv32 tests/run.sh     emit RV32 with `codegen --rv32` and run on RV32 Spike
#
# Run inside the container (make test does this).
#   TA tests:  testcases/<Category>/<n>.c, expected output tests/expected/<Category>_<n>.expected
#   own tests: tests/extra/<name>.c, expected output tests/extra/<name>.expected
set -uo pipefail

cd "$(dirname "$0")/.."
root="$(pwd)"
filter="${1:-}"
target="${TARGET:-rv64}"
case "$target" in
    rv64) codegen_flags=();        cc=(riscv64-unknown-elf-gcc);                               sim=(spike pk) ;;
    rv32) codegen_flags=(--rv32);  cc=(riscv-none-elf-gcc -march=rv32imac -mabi=ilp32);        sim=(spike --isa=rv32imac /opt/riscv32/riscv-none-elf/bin/pk) ;;
    *) echo "unknown TARGET: $target" >&2; exit 2 ;;
esac
build="build/$target"
mkdir -p "$build"

pass=0
fail=0
failed=()

run_case() {
    local src="$1" expected="$2" name="$3"
    [[ -n "$filter" && "$name" != *"$filter"* ]] && return
    local dir="$build/$name"
    mkdir -p "$dir"

    if ! (cd "$dir" && "$root/codegen" ${codegen_flags[@]+"${codegen_flags[@]}"} < "$root/$src") 2> "$dir/codegen.err"; then
        echo "FAIL $name  (codegen error: $(head -1 "$dir/codegen.err"))"
        fail=$((fail + 1)); failed+=("$name"); return
    fi
    if ! "${cc[@]}" -o "$dir/prog" spike-sample/main.c "$dir/codegen.S" 2> "$dir/gcc.err"; then
        echo "FAIL $name  (assemble/link error, see $dir/gcc.err)"
        fail=$((fail + 1)); failed+=("$name"); return
    fi
    timeout 20 "${sim[@]}" "$dir/prog" 2>&1 | grep '^Arduino' > "$dir/output.txt"
    if diff -u "$expected" "$dir/output.txt" > "$dir/output.diff"; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name  (see $dir/output.diff)"
        fail=$((fail + 1)); failed+=("$name")
    fi
}

for src in testcases/*/*.c; do
    category="$(basename "$(dirname "$src")")"
    name="${category}_$(basename "$src" .c)"
    run_case "$src" "tests/expected/$name.expected" "$name"
done

for src in tests/extra/*.c; do
    [[ -e "$src" ]] || continue
    name="extra_$(basename "$src" .c)"
    run_case "$src" "${src%.c}.expected" "$name"
done

echo "[$target] $pass passed, $fail failed"
[[ $fail -eq 0 ]]
