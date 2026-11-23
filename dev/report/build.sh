#!/usr/bin/env bash
# Build the implementation reports (LaTeX -> PDF) with LuaLaTeX.
#
#   dev/run.sh dev/report/build.sh          build every report
#   dev/run.sh dev/report/build.sh hw1      only reports whose path contains "hw1"
#
# Run inside the container (the image has TeX Live, Carlito and TeX Gyre fonts).
# Code excerpts are read from the source files at build time (see report.sty),
# so rebuild after changing the code. Auxiliary files go to a temp directory;
# only the PDF is written next to the .tex file.
set -euo pipefail

cd "$(dirname "$0")/../.."
root="$(pwd)"
filter="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export TEXINPUTS="$root/dev/report//:"
export TEXMFVAR="${TEXMFVAR:-$tmp/texmf-var}"

reports=(
    hw1-scanner/report/HW1_Implementation_Report.tex
    hw2-parser/report/HW2_Implementation_Report.tex
    hw3-codegen/report/HW3_Implementation_Report.tex
    hw3-codegen/bonus/report/HW3_Bonus_Implementation_Report.tex
)

status=0
for tex in "${reports[@]}"; do
    [[ -n "$filter" && "$tex" != *"$filter"* ]] && continue
    [[ -e "$tex" ]] || { echo "skip $tex (not found)"; continue; }
    name="$(basename "$tex" .tex)"
    out="$tmp/$name"
    mkdir -p "$out"
    if latexmk -lualatex -cd -interaction=nonstopmode -halt-on-error \
            -outdir="$out" "$tex" > "$out/build.log" 2>&1; then
        cp "$out/$name.pdf" "$(dirname "$tex")/$name.pdf"
        echo "built $(dirname "$tex")/$name.pdf"
        grep -E 'Overfull \\hbox \(([2-9][0-9]|[0-9]{3,})' "$out/$name.log" | sed 's/^/  warning: /' || true
    else
        echo "FAILED $tex"
        grep -E '^!' -A4 "$out/$name.log" 2>/dev/null | head -30 || tail -30 "$out/build.log"
        status=1
    fi
done
exit $status
