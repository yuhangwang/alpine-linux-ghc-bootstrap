#!/usr/bin/env sh
#-*-mode: Shell-script; coding: utf-8;-*-
# File: llvm.sh
# Copyright: 2016 Mitchell Tishmack
# Description: bootstrap llvm for ghc bootstrapping
# largely a copypasta of what is in APKBUILD
export script=$(basename "$0")
export dir=$(cd "$(dirname "$0")"; pwd)
export iam=${dir}/${script}
llvm_major=3.5
llvm_version=${llvm_major}.2
llvm_srcdir="/tmp/llvm-${llvm_version}.src"
#mdir="/tmp/llvm-mirror-llvm-7892e56"
#if [ -e ${mdir} ]; then
#  mv ${mdir} ${llvm_srcdir}
#fi
suffix="-${llvm_major}"
llvm_builddir=/tmp/build
polly_orig_srcdir="/tmp/polly-$llvm_version.src"

cd "$llvm_srcdir"
for i in /tmp/llvm*.patch; do
	patch -s -p1 -N -i $i || return 1
done

_cmake_flags="\
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_VERBOSE_MAKEFILE=NO \
	-DLLVM_DEFAULT_TARGET_TRIPLE=$CBUILD \
	-DLLVM_HOST_TRIPLE=$CHOST \
	-DLLVM_BINUTILS_INCDIR=/usr/include \
	-DLLVM_ENABLE_ASSERTIONS=NO \
	-DLLVM_ENABLE_LIBCXX=NO \
	-DLLVM_ENABLE_PIC=YES \
	-DLLVM_ENABLE_ZLIB=YES \
	-DLLVM_ENABLE_RTTI=YES \
	-DLLVM_BUILD_EXAMPLES=NO \
	-DLLVM_INCLUDE_EXAMPLES=NO \
	-DLIBXML2_INCLUDE_DIR=/usr/include/libxml2 \
	-DCMAKE_INSTALL_PREFIX=/usr \
	-DLLVM_TARGETS_TO_BUILD='all' \
	-DLLVM_BUILD_EXTERNAL_COMPILER_RT=NO \
	-DBUILD_SHARED_LIBS=NO \
	-DLLVM_EXTERNAL_POLLY_BUILD=NO \
	-DLINK_POLLY_INTO_TOOLS=NO \
	-DLLVM_BUILD_DOCS=NO \
	-DLLVM_BUILD_TESTS=NO \
	-DLLVM_ENABLE_CXX1Y=NO \
	-DLLVM_ENABLE_FFI=YES \
	-DLLVM_ENABLE_SPHINX=NO \
	-DLLVM_ENABLE_TERMINFO=YES \
	-DWITH_POLLY=YES \
	-DLLVM_INCLUDE_EXAMPLES=NO \
	-DLLVM_INCLUDE_TESTS=NO \
	-DPOLLY_ENABLE_GPGPU_CODEGEN=NO \
	"
srcdir_polly="$llvm_srcdir"/tools/polly
mv /tmp/polly-$llvm_version.src "$srcdir_polly" || return 1

build_isl() {
	srcdir=/tmp
	tmp="$srcdir/tmp"
	install -d ${tmp} || return 1
	isl_srcdir="$tmp/isl"
	cloog_srcdir="$tmp/cloog"
	cd "$srcdir_polly/utils"
	./checkout_cloog.sh ${tmp} || return 1
#	./checkout_isl.sh ${isl_srcdir} || return 1
	cd "$isl_srcdir"
	./configure --build=$CBUILD \
		--host=$CHOST \
		--prefix=$tmp || return 1
	make -j$(grep -c processor /proc/cpuinfo)|| return 1
	make -j1 INSTALL="install -D"	 install || return 1
}

build_isl "$srcdir_polly" || return 1
(
	OCFLAGS="${CFLAGS}"
	OCXXFLAGS="${CXXFLAGS}"
	unset CFLAGS
	unset CXXFLAGS

	test -z "${OCFLAGS}" && OCFLAGS="-O3"
	test -z "${OCXXFLAGS}" && OCXXFLAGS="-O3"

	cflags="${OCFLAGS} -DNDEBUG -I$srcdir/tmp/include"
	cxxflags="${OCXXFLAGS} -DNDEBUG -fno-devirtualize"

	export CBUILD
	export CC=gcc
	export CXX=g++

	ffi_include_dir="$(pkg-config --cflags-only-I libffi | sed 's|^-I||g')"

	cflags="${OCFLAGS} -DNDEBUG"
	cxxflags="${OCXXFLAGS} -DNDEBUG"

	mkdir -p "${llvm_builddir}"
	cd "${llvm_builddir}"
	cmake -G "Unix Makefiles" -Wno-dev ${_cmake_final_flags} \
			  -DCMAKE_C_COMPILER="${CC}" \
			  -DCMAKE_CXX_COMPILER="${CXX}" \
			  -DCMAKE_C_FLAGS_RELEASE="${cflags}" \
			  -DCMAKE_CXX_FLAGS_RELEASE="${cxxflags}" \
			  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS} -L$srcdir/tmp/lib" \
			  -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
			  -DFFI_INCLUDE_DIR="$ffi_include_dir" \
			  -DCMAKE_PREFIX_PATH="$srcdir/tmp" \
			  "${llvm_srcdir}" || return 1

	(
		export LD_LIBRARY_PATH="$srcdir/tmp/lib:$LD_LIBRARY_PATH"
		make -j$(grep -c processor /proc/cpuinfo) llvm-tblgen || return 1
		make -j$(grep -c processor /proc/cpuinfo) || return 1
	) || return 1
	export CFLAGS="${OCFLAGS}"
	export CXXFLAGS="${OCXXFLAGS}"

	# install portion
	make -j1 install || return 1
) || return 1
