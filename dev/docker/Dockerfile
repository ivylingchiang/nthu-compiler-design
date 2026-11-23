# NTHU CS340400 Compiler Design 開發／測試環境
#   flex + byacc + GNU gcc      HW1 / HW2 / HW3 建置（與課程 server 相同的工具組）
#   riscv64-unknown-elf-gcc     HW3 組譯 codegen.S（xPack 預建工具鏈，內含 newlib）
#   spike + pk                  HW3 執行（RISC-V ISA simulator + proxy kernel）
#
# 建置：dev/run.sh --build

FROM ubuntu:24.04 AS toolchain

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -yqq --no-install-recommends \
        build-essential flex byacc bison \
        ca-certificates curl git \
        device-tree-compiler libboost-regex-dev libboost-system-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- RISC-V 工具鏈（xPack riscv-none-elf-gcc，含 newlib 與 rv64gc/lp64d multilib）----
ARG XPACK_VER=14.2.0-3
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in arm64) xarch=arm64 ;; amd64) xarch=x64 ;; *) echo "unsupported: $arch"; exit 1 ;; esac; \
    f="xpack-riscv-none-elf-gcc-${XPACK_VER}-linux-${xarch}.tar.gz"; \
    base="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_VER}"; \
    cd /tmp; curl -fsSLO "$base/$f"; curl -fsSLO "$base/$f.sha"; \
    sha256sum -c "$f.sha"; \
    mkdir -p /opt/xpack; tar -xzf "$f" -C /opt/xpack --strip-components=1; rm -f "$f" "$f.sha"

ENV PATH="/opt/riscv/bin:/opt/xpack/bin:${PATH}"

# 課程規格使用 riscv64-unknown-elf-gcc，包一層固定成 RV64GC / LP64D
RUN mkdir -p /opt/riscv/bin && \
    printf '#!/bin/sh\nexec riscv-none-elf-gcc -march=rv64gc -mabi=lp64d "$@"\n' > /opt/riscv/bin/riscv64-unknown-elf-gcc && \
    for t in objdump as ld; do ln -s /opt/xpack/bin/riscv-none-elf-$t /opt/riscv/bin/riscv64-unknown-elf-$t; done && \
    chmod +x /opt/riscv/bin/riscv64-unknown-elf-gcc

# ---- Spike（固定 commit，確保 CI 與本機結果一致）----
ARG SPIKE_COMMIT=982f078e65ab52d5d9a91248c2178f5399df7783
ARG PK_COMMIT=9c61d29846d8521d9487a57739330f9682d5b542
RUN set -eux; \
    git init -q /tmp/spike; cd /tmp/spike; \
    git remote add origin https://github.com/riscv-software-src/riscv-isa-sim; \
    git fetch -q --depth 1 origin "$SPIKE_COMMIT"; git checkout -q FETCH_HEAD; \
    git submodule update -q --init --recursive --depth 1; \
    git -C /tmp/spike rev-parse HEAD > /opt/riscv/SPIKE_COMMIT; \
    mkdir /tmp/spike/build; cd /tmp/spike/build; \
    ../configure --prefix=/opt/riscv; make -j"$(nproc)"; make install; \
    rm -rf /tmp/spike

# ---- Proxy kernel (pk) ----
RUN set -eux; \
    git init -q /tmp/pk; git -C /tmp/pk fetch -q --depth 1 https://github.com/riscv-software-src/riscv-pk "$PK_COMMIT"; \
    git -C /tmp/pk checkout -q FETCH_HEAD; \
    git -C /tmp/pk rev-parse HEAD > /opt/riscv/PK_COMMIT; \
    mkdir /tmp/pk/build; cd /tmp/pk/build; \
    ../configure --prefix=/opt/riscv --host=riscv-none-elf --with-arch=rv64gc_zicsr_zifencei --with-abi=lp64d; \
    make -j"$(nproc)"; make install; \
    rm -rf /tmp/pk

# Spike 依 target 名稱到 <prefix>/riscv64-unknown-elf/bin/ 找 pk，讓 `spike pk prog` 能直接用
RUN ln -s /opt/riscv/riscv-none-elf /opt/riscv/riscv64-unknown-elf

# 課程 server 的 yacc 是 byacc（bison 也有裝，但 `yacc` 指令要指向 byacc）
RUN ln -s /usr/bin/byacc /opt/riscv/bin/yacc

# ---- RV32 版 proxy kernel：在 Spike 上執行 `codegen --rv32` 的輸出（HW3 Bonus 驗證用）----
#   spike --isa=rv32imac /opt/riscv32/riscv-none-elf/bin/pk prog
#   （Spike 不會從 PATH 找 pk，所以要給完整路徑；pk32 這個 symlink 只是方便查找位置）
RUN set -eux; \
    git init -q /tmp/pk; git -C /tmp/pk fetch -q --depth 1 https://github.com/riscv-software-src/riscv-pk "$PK_COMMIT"; \
    git -C /tmp/pk checkout -q FETCH_HEAD; \
    mkdir /tmp/pk/build; cd /tmp/pk/build; \
    ../configure --prefix=/opt/riscv32 --host=riscv-none-elf --with-arch=rv32imac_zicsr_zifencei --with-abi=ilp32; \
    make -j"$(nproc)"; make install; \
    ln -s /opt/riscv32/riscv-none-elf/bin/pk /opt/riscv/bin/pk32; \
    rm -rf /tmp/pk

WORKDIR /work

# 以上是建置與測試需要的全部工具；CI 只建這個 stage：docker build --target toolchain
FROM toolchain AS full

# ---- Implementation reports: LaTeX (LuaLaTeX + listings + TikZ), see dev/report/build.sh ----
#   Carlito is metric-compatible with Calibri, TeX Gyre Termes with Times New Roman
RUN apt-get update && apt-get install -y --no-install-recommends \
        texlive-luatex texlive-latex-recommended texlive-latex-extra texlive-pictures \
        fonts-crosextra-carlito fonts-texgyre lmodern latexmk \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
