#!/usr/bin/env bash
# 在國網創進一號 (F1) 上安裝 Quantum ESPRESSO 7.6
set -Eeuo pipefail

SRC="${QE_SRC:-$HOME/qe-src}"           # 原始碼放哪
PREFIX="${QE_PREFIX:-$HOME/opt/qe-7.6}" # 裝到哪
JOBS="${QE_JOBS:-16}"                   # 同時編譯幾個檔案

# --- 1. 下載原始碼 ---------------------------------------------------------
# 用 MKL 的話八個 submodule 只需要這三個
if [ ! -d "$SRC" ]; then
    echo ">>> 下載原始碼"
    git clone --depth 1 -b qe-7.6 https://github.com/QEF/q-e.git "$SRC"
    git -C "$SRC" submodule update --init --depth 1 -- \
        external/devxlib external/mbd external/wannier90
else
    echo ">>> 原始碼已存在，跳過下載"
fi

# --- 2. 載入 Intel 工具鏈 --------------------------------------------------
# F1 預設載入的是 gcc + openmpi，不換掉會裝出沒有平行化的版本。
# unset 那行是必要的：gcc 的 module 會設定 F90/FC/CC，殘留下來會讓 configure 誤用 gfortran。
echo ">>> 載入 intel/2024_01_46"
module purge
unset F90 FC CC CXX MPIF90
module load intel/2024_01_46

# --- 3. 設定 ---------------------------------------------------------------
echo ">>> configure"
cd "$SRC"
./configure --enable-parallel --enable-openmp --with-scalapack=intel \
    --prefix="$PREFIX" MPIF90=mpiifx CC=mpiicx

# --- 4. 檢查設定結果 -------------------------------------------------------
# configure 就算沒找到 Intel 編譯器也會回傳 0，所以一定要自己檢查產物
grep -q -- '-D__MPI' make.inc || {
    echo "錯誤：沒有 MPI 平行化"
    exit 1
}
grep -q -- '-D__SCALAPACK' make.inc || {
    echo "錯誤：沒有 ScaLAPACK"
    exit 1
}
grep -q 'BLAS_LIBS.*mkl' make.inc || {
    echo "錯誤：沒有連到 MKL"
    exit 1
}
echo ">>> 設定檢查通過"

# --- 5. 編譯與安裝 ---------------------------------------------------------
echo ">>> 編譯中（-j $JOBS），約需幾分鐘"
make -j"$JOBS" all
make install

# --- 6. 產生環境設定檔 -----------------------------------------------------
cat >"$PREFIX/env.sh" <<ENV
module purge
module load intel/2024_01_46
export PATH="$PREFIX/bin:\$PATH"
ENV

echo
echo "安裝完成：$(ls "$PREFIX/bin" | wc -l) 個執行檔"
echo "使用方式： source $PREFIX/env.sh"
