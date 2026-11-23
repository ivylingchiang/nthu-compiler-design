#!/usr/bin/env bash
# 在 Colima VM（profile: compiler）的容器裡執行指令；不改動本機的 docker 預設 context。
#
#   dev/run.sh --build                 建置映像檔
#   dev/run.sh                         進入互動式 shell
#   dev/run.sh make -C hw1-scanner test
#
# 容器的工作目錄會對應到你目前所在的 repo 子目錄。
set -euo pipefail

CONTEXT="${COMPILER_DOCKER_CONTEXT:-colima-compiler}"
IMAGE="nthu-compiler:latest"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER=(docker --context "$CONTEXT")

if ! "${DOCKER[@]}" info >/dev/null 2>&1; then
    echo "Docker context '$CONTEXT' 無法連線，請先執行：colima start compiler" >&2
    exit 1
fi

if [[ "${1:-}" == "--build" ]]; then
    exec "${DOCKER[@]}" build -t "$IMAGE" "$ROOT/dev/docker"
fi

# 目前目錄相對於 repo root 的位置，對應到容器內 /work/...
rel="${PWD#"$ROOT"}"
[[ "$PWD" == "$ROOT"* ]] || rel=""

tty_flag=()
[[ -t 0 && -t 1 ]] && tty_flag=(-t)

[[ $# -eq 0 ]] && set -- bash

# ${arr[@]+...}：相容 macOS 內建 bash 3.2（set -u 下展開空陣列會報錯）
exec "${DOCKER[@]}" run --rm -i ${tty_flag[@]+"${tty_flag[@]}"} \
    --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$ROOT":/work -w "/work$rel" \
    "$IMAGE" "$@"
