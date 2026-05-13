#!/bin/sh
set -eu

# Simple distro bootstrap:
#   1. clone or fetch source into bootstrap/work/cache
#   2. prepare patched source trees in bootstrap/work/src
#   3. build a host-seeded root at bootstrap/work/root
#   4. build replacement roots with that root, then compare manifests
#   5. build one final /-prefixed root and archive bootstrap.tar.xz/bootstrap.tar.gz
#
# Knobs:
#   WORK=...       where cache, sources, builds, and roots live
#   STAGES=2      number of self-hosted replacement stages to build
#   JOBS=...      make parallelism
#   HOST_CC=cc    host compiler used only for the first root
#   TARBALL=...      final xz archive path
#   TARBALL_GZ=...   final gzip archive path
#   CHECKSUM_FILE=... expected final archive checksums

die() {
	printf 'bootstrap.sh: %s\n' "$*" >&2
	exit 1
}

log() {
	printf '\n==> %s\n' "$*"
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATCH_DIR=$SCRIPT_DIR/patches
WORK=${WORK:-$SCRIPT_DIR/work}
CACHE=$WORK/cache
SRC=$WORK/src
BUILD=$WORK/build
ROOT=$WORK/root
ROOT_PREV=$WORK/root.prev
ROOT_NEW=$WORK/root.new
TARBALL_ROOT=$WORK/bootstrap-root
TARBALL=${TARBALL:-$SCRIPT_DIR/bootstrap.tar.xz}
TARBALL_GZ=${TARBALL_GZ:-$SCRIPT_DIR/bootstrap.tar.gz}
CHECKSUM_FILE=${CHECKSUM_FILE:-$SCRIPT_DIR/bootstrap.sha256}
TARGET=${TARGET:-x86_64-linux-musl}
STAGES=${STAGES:-2}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 1)}
HOST_CC=${HOST_CC:-cc}
HOST_MAKE=${HOST_MAKE:-make}
HOST_AR=${HOST_AR:-ar}
HOST_RANLIB=${HOST_RANLIB:-ranlib}
HOST_SHELL=${HOST_SHELL:-/bin/sh}
HOST_PATH=$PATH

TARGET_CPP_FLAGS="-V199901L -W0 -e utf8 -D__linux__ -D__unix__ -D__ELF__ -D__x86_64__ -D__amd64__ -D__LP64__"

need curl
need git
need tar
need gzip
need patch
need sha256sum
need awk
need find
need sort
need diff
need readlink
need "${HOST_CC%% *}"
need "$HOST_MAKE"
need "$HOST_AR"
need "$HOST_RANLIB"

mkdir -p "$CACHE/tar" "$CACHE/git" "$SRC" "$BUILD"

check_sha256() {
	file=$1
	expected=$2
	actual=
	actual=$(sha256sum "$file" | awk '{ print $1 }')
	[ "$actual" = "$expected" ] || die "sha256 mismatch for $file"
}

fetch_tar() {
	name=$1
	url=$2
	sha256=$3
	file=
	file=$CACHE/tar/$name

	if [ ! -f "$file" ]; then
		log "fetch $name"
		curl -L -o "$file.tmp" "$url"
		mv "$file.tmp" "$file"
	fi
	check_sha256 "$file" "$sha256"
}

prepare_tar() {
	name=$1
	url=$2
	sha256=$3
	file=
	out=
	file=$CACHE/tar/$name
	out=$SRC/$name

	fetch_tar "$name" "$url" "$sha256"
	rm -rf "$out"
	mkdir -p "$out"
	tar -xf "$file" -C "$out" --strip-components=1
}

prepare_git() {
	name=$1
	url=$2
	rev=$3
	mirror=
	out=
	commit=
	mirror=$CACHE/git/$name.git
	out=$SRC/$name

	if [ -d "$mirror" ]; then
		log "update $name"
		git --git-dir="$mirror" fetch --tags --prune
	else
		log "clone $name"
		git clone --mirror "$url" "$mirror"
	fi

	commit=$(git --git-dir="$mirror" rev-parse --verify "$rev^{commit}") ||
		die "cannot resolve $name revision $rev"

	rm -rf "$out"
	mkdir -p "$out"
	git --git-dir="$mirror" archive "$commit" | tar -xf - -C "$out"
}

apply_bootstrap_patch() {
	name=$1
	patch_file=$2
	log "patch $name"
	( cd "$SRC/$name" && patch -p1 < "$PATCH_DIR/$patch_file" )
}

prepare_sources() {
	log "prepare sources"
	prepare_git cproc https://github.com/andrewchambers/cproc.git c023205e716896727addbfcc870034c20fc29b1a
	prepare_git musl https://github.com/andrewchambers/musl.git 4b8873814833c15af9d28f7c1d483345b60bde59
	prepare_git mcpp https://github.com/museoa/mcpp.git 2.7.2.2
	prepare_git oksh https://github.com/ibara/oksh.git oksh-7.8
	prepare_git pigz https://github.com/madler/pigz.git fe4894f57739e3039a2ffc2a2a360d35e19bacbe
	prepare_git tinybinutils https://github.com/andrewchambers/tinybinutils.git 30978e16be98c30fb441ce2926c84871bb03779b
	prepare_git sbase https://git.suckless.org/sbase c1341583c96307cb0e6152c963ed23c4d56a4278

	prepare_tar xz-5.8.1.tar.gz https://tukaani.org/xz/xz-5.8.1.tar.gz \
		507825b599356c10dca1cd720c9d0d0c9d5400b9de300af00e4d1ea150795543
	prepare_tar zlib-1.3.1.tar.gz https://zlib.net/fossils/zlib-1.3.1.tar.gz \
		9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
	prepare_tar make-4.4.1.tar.gz https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz \
		dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3
	prepare_tar mawk-1.3.4-20240819.tgz https://invisible-mirror.net/archives/mawk/mawk-1.3.4-20240819.tgz \
		6e1fde8ee7ad8a5c15382316863fd6b4c6d23fab781dd5ab0177ffa3ee9aae5c

	apply_bootstrap_patch mcpp mcpp-bootstrap.patch
	apply_bootstrap_patch make-4.4.1.tar.gz gnumake-bootstrap.patch
	apply_bootstrap_patch mawk-1.3.4-20240819.tgz mawk-bootstrap.patch
	apply_bootstrap_patch oksh oksh-bootstrap.patch
	apply_bootstrap_patch sbase sbase-bootstrap.patch
	apply_bootstrap_patch sbase sbase-reproducible-tar.patch
	apply_bootstrap_patch sbase sbase-no-share.patch
}

copy_source() {
	name=$1
	dest=$2
	rm -rf "$dest"
	mkdir -p "$dest"
	cp -R "$SRC/$name"/. "$dest"/
	chmod -R u+w "$dest"
}

retouch() {
	file=
	for file in "$@"; do
		[ ! -e "$file" ] || touch "$file"
	done
}

prefix_path() {
	prefix=$1
	path=$2

	if [ "$prefix" = "/" ]; then
		printf '/%s' "${path#/}"
	else
		printf '%s/%s' "${prefix%/}" "${path#/}"
	fi
}

set_stage_env() {
	prev=$1
	libc=$2

	export LC_ALL=C
	export TZ=UTC
	export AWK=awk
	export SED=sed
	export GREP=grep
	export EGREP='grep -E'
	export FGREP='grep -F'
	export ac_cv_path_SED=sed
	export lt_cv_path_SED=sed
	export ac_cv_path_EGREP='grep -E'
	export ac_cv_path_EGREP_TRADITIONAL='grep -E'
	export ac_cv_path_FGREP='grep -F'
	export MAKEINFO=true
	export lt_cv_path_MAGIC_CMD=:

	if [ "$prev" = host ]; then
		export PATH=$HOST_PATH
		export SHELL=$HOST_SHELL
		export CONFIG_SHELL=$HOST_SHELL
		export AR=$HOST_AR
		export RANLIB=$HOST_RANLIB
		MAKE_CMD=$HOST_MAKE
		CC_BIN=$HOST_CC
		CC_FOR=$HOST_CC
		CC_FOR_MUSL="$HOST_CC -no-pie"
		CFLAGS_FOR=
		LDFLAGS_FOR=
	else
		export PATH=$prev/bin
		export SHELL=$prev/bin/oksh
		export CONFIG_SHELL=$prev/bin/oksh
		export AR=$prev/bin/ar
		export RANLIB=$prev/bin/ranlib
		MAKE_CMD=$prev/bin/make
		CC_BIN=$prev/bin/cproc
		CC_FOR="$prev/bin/cproc -I$libc/include -L$libc/lib"
		CC_FOR_MUSL=$prev/bin/cproc
		CFLAGS_FOR="-I$libc/include"
		LDFLAGS_FOR="-L$libc/lib"
	fi
}

copy_from_destdir() {
	destdir=$1
	out=$2
	prefix=$3
	prefix_dir=
	if [ "$prefix" = "/" ]; then
		prefix_dir=$destdir
	else
		prefix_dir=$destdir$prefix
	fi

	[ -d "$prefix_dir" ] || die "install did not populate $prefix_dir"
	mkdir -p "$out"
	cp -R "$prefix_dir"/. "$out"/
}

build_musl() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/musl
	destdir=$BUILD/musl.dest
	log "build musl"
	copy_source musl "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
			CC="$CC_FOR_MUSL" "$CONFIG_SHELL" ./configure \
			--prefix="$prefix" \
			--target="$TARGET" \
			--disable-shared \
			--enable-static
		"$MAKE_CMD" -j"$JOBS" AR="$AR" RANLIB="$RANLIB" \
			lib/libc.a lib/crt1.o lib/crti.o lib/crtn.o
		rm -rf "$destdir"
		"$MAKE_CMD" install DESTDIR="$destdir" AR="$AR" RANLIB="$RANLIB"
		copy_from_destdir "$destdir" "$out" "$prefix"
	)
}

build_mcpp() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/mcpp
	destdir=$BUILD/mcpp.dest
	log "build mcpp"
	copy_source mcpp "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		retouch aclocal.m4 configure Makefile.in src/Makefile.in src/config.h.in tests/Makefile.in
		CC="$CC_FOR" CFLAGS="$CFLAGS_FOR" LDFLAGS="$LDFLAGS_FOR" \
			"$CONFIG_SHELL" ./configure \
				--prefix="$prefix" \
				--enable-mcpplib \
				--disable-shared \
				--enable-static
		"$MAKE_CMD" -j"$JOBS"
		rm -rf "$destdir"
		"$MAKE_CMD" install-exec DESTDIR="$destdir"
		"$MAKE_CMD" -C src install-data DESTDIR="$destdir"
		copy_from_destdir "$destdir" "$out" "$prefix"
	)
}

build_gnumake() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/gnumake
	destdir=$BUILD/gnumake.dest
	log "build gnumake"
	copy_source make-4.4.1.tar.gz "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		retouch aclocal.m4 configure Makefile.in src/Makefile.in lib/Makefile.in po/Makefile.in.in doc/Makefile.in
		CC="$CC_FOR" CFLAGS="$CFLAGS_FOR" LDFLAGS="$LDFLAGS_FOR" make_cv_sys_gnu_glob=no \
			"$CONFIG_SHELL" ./configure \
				--prefix="$prefix" \
				--disable-dependency-tracking \
				--disable-nls \
				--without-guile
		"$MAKE_CMD" -j"$JOBS"
		rm -rf "$destdir"
		"$MAKE_CMD" install-exec DESTDIR="$destdir"
		copy_from_destdir "$destdir" "$out" "$prefix"
	)
}

build_mawk() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/mawk
	log "build mawk"
	copy_source mawk-1.3.4-20240819.tgz "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		retouch parse.c parse.h scan.c scancode.h Makefile.in configure config_h.in
		CC="$CC_FOR" BUILD_CC="$CC_FOR" \
		CFLAGS="$CFLAGS_FOR" BUILD_CFLAGS="$CFLAGS_FOR" \
		LDFLAGS="$LDFLAGS_FOR" BUILD_LDFLAGS="$LDFLAGS_FOR" \
			"$CONFIG_SHELL" ./configure \
				--prefix="$prefix" \
				--enable-builtin-regex
		"$MAKE_CMD" -j"$JOBS" YACC=false
		mkdir -p "$out/bin"
		cp mawk "$out/bin/mawk"
		ln -sf mawk "$out/bin/awk"
	)
}

build_zlib() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/zlib
	log "build zlib"
	copy_source zlib-1.3.1.tar.gz "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		CC="$CC_FOR" CFLAGS="$CFLAGS_FOR" LDFLAGS="$LDFLAGS_FOR" \
		AR="$AR" RANLIB="$RANLIB" \
			"$CONFIG_SHELL" ./configure \
				--prefix="$prefix" \
				--static
		"$MAKE_CMD" -j"$JOBS"
		mkdir -p "$out/include" "$out/lib/pkgconfig"
		cp zlib.h zconf.h "$out/include/"
		cp libz.a "$out/lib/"
		cp zlib.pc "$out/lib/pkgconfig/"
		"$RANLIB" "$out/lib/libz.a"
	)
}

build_tinybinutils() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/tinybinutils
	shell_path=
	shell_path=$(prefix_path "$prefix" bin/sh)
	log "build tinybinutils"
	copy_source tinybinutils "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		"$MAKE_CMD" clean
		"$MAKE_CMD" -j"$JOBS" \
			CC="$CC_FOR" \
			CFLAGS="$CFLAGS_FOR" \
			LDFLAGS="$LDFLAGS_FOR" \
			tinyld tinyas tinyar
		mkdir -p "$out/bin"
		cp tinyld tinyas tinyar "$out/bin/"
		ln -sf tinyld "$out/bin/ld"
		ln -sf tinyas "$out/bin/as"
		ln -sf tinyar "$out/bin/ar"
		printf '%s\n' "#!$shell_path" 'exit 0' > "$out/bin/ranlib"
		chmod +x "$out/bin/ranlib"
	)
}

build_pigz() {
	prev=$1
	out=$2
	dir=$BUILD/pigz
	log "build pigz"
	copy_source pigz "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		"$MAKE_CMD" -j"$JOBS" pigz \
			CC="$CC_FOR" \
			CFLAGS="$CFLAGS_FOR -I$out/include -D_FILE_OFFSET_BITS=64" \
			LDFLAGS="$LDFLAGS_FOR -L$out/lib" \
			LIBS="-lm -lpthread -lz"
		mkdir -p "$out/bin"
		cp pigz unpigz "$out/bin/"
		ln -sf pigz "$out/bin/gzip"
		ln -sf unpigz "$out/bin/gunzip"
	)
}

build_xz() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/xz
	log "build xz"
	copy_source xz-5.8.1.tar.gz "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		retouch aclocal.m4 configure config.h.in Makefile.in lib/Makefile.in \
			src/Makefile.in src/liblzma/Makefile.in src/liblzma/api/Makefile.in \
			src/xz/Makefile.in src/xzdec/Makefile.in src/lzmainfo/Makefile.in \
			src/scripts/Makefile.in tests/Makefile.in debug/Makefile.in po/Makefile.in.in
		CC="$CC_FOR" CFLAGS="$CFLAGS_FOR" LDFLAGS="$LDFLAGS_FOR" \
			"$CONFIG_SHELL" ./configure \
				--prefix="$prefix" \
				--disable-shared \
				--enable-static \
				--disable-nls \
				--disable-scripts \
				--disable-doc \
				--disable-xzdec \
				--disable-lzmadec \
				--disable-lzmainfo \
				--disable-lzma-links \
				--disable-microlzma \
				--disable-lzip-decoder \
				--disable-assembler \
				--disable-clmul-crc \
				--disable-sandbox \
				--enable-threads=no \
				--enable-small
		"$MAKE_CMD" -j"$JOBS"
		mkdir -p "$out/bin" "$out/include/lzma" "$out/lib/pkgconfig"
		cp src/xz/xz "$out/bin/"
		ln -sf xz "$out/bin/unxz"
		ln -sf xz "$out/bin/xzcat"
		cp src/liblzma/.libs/liblzma.a "$out/lib/"
		cp src/liblzma/api/lzma.h "$out/include/"
		cp src/liblzma/api/lzma/*.h "$out/include/lzma/"
		cp src/liblzma/liblzma.pc "$out/lib/pkgconfig/"
		"$RANLIB" "$out/lib/liblzma.a"
	)
}

build_oksh() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/oksh
	static_flag=
	log "build oksh"
	copy_source oksh "$dir"
	[ "$prev" = host ] || static_flag=--enable-static
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		CC="$CC_FOR" CFLAGS="$CFLAGS_FOR" LDFLAGS="$LDFLAGS_FOR" \
			"$CONFIG_SHELL" ./configure \
				--prefix="$prefix" \
				--no-strip \
				--disable-curses \
				$static_flag
		"$MAKE_CMD" -j"$JOBS"
		mkdir -p "$out/bin"
		cp oksh "$out/bin/oksh"
		ln -sf oksh "$out/bin/sh"
	)
}

build_sbase() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/sbase
	destdir=$BUILD/sbase.dest
	manprefix=
	manprefix=$(prefix_path "$prefix" share/man)
	log "build sbase"
	copy_source sbase "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		env MAKEFLAGS= "$MAKE_CMD" \
			CC="$CC_BIN" \
			AR="$AR" RANLIB="$RANLIB" \
			CFLAGS="$CFLAGS_FOR" \
			LDFLAGS="$LDFLAGS_FOR" \
			SMAKE="$MAKE_CMD"
		rm -rf "$destdir"
		env MAKEFLAGS= "$MAKE_CMD" \
			DESTDIR="$destdir" \
			PREFIX="$prefix" \
			MANPREFIX="$manprefix" \
			CC="$CC_BIN" \
			AR="$AR" RANLIB="$RANLIB" \
			CFLAGS="$CFLAGS_FOR" \
			LDFLAGS="$LDFLAGS_FOR" \
			SMAKE="$MAKE_CMD" \
			sbase-box-install
		copy_from_destdir "$destdir" "$out" "$prefix"
	)
}

build_cproc() {
	prev=$1
	out=$2
	prefix=$3
	dir=$BUILD/cproc
	cpp_path=
	as_path=
	ld_path=
	lib_path=
	cpp_path=$(prefix_path "$prefix" bin/mcpp)
	as_path=$(prefix_path "$prefix" bin/as)
	ld_path=$(prefix_path "$prefix" bin/ld)
	lib_path=$(prefix_path "$prefix" lib)
	log "build cproc"
	copy_source cproc "$dir"
	(
		cd "$dir"
		set_stage_env "$prev" "$out"
		"$CONFIG_SHELL" ./configure \
			--prefix="$prefix" \
			--target="$TARGET" \
			--with-cpp="$cpp_path $TARGET_CPP_FLAGS" \
			--with-as="$as_path" \
			--with-ld="$ld_path -static -L$lib_path" \
			--with-ldso= \
			CC="$CC_FOR" \
			CFLAGS="$CFLAGS_FOR" \
			LDFLAGS="$LDFLAGS_FOR -s"
		"$MAKE_CMD" -j"$JOBS"
		mkdir -p "$out/bin"
		cp cproc cproc-amd64 "$out/bin/"
	)
}

build_stage() {
	prev=$1
	out=$2
	prefix=$3

	rm -rf "$out" "$BUILD"
	mkdir -p "$out" "$BUILD"
	build_musl "$prev" "$out" "$prefix"
	build_mcpp "$prev" "$out" "$prefix"
	build_gnumake "$prev" "$out" "$prefix"
	build_mawk "$prev" "$out" "$prefix"
	build_zlib "$prev" "$out" "$prefix"
	build_tinybinutils "$prev" "$out" "$prefix"
	build_pigz "$prev" "$out" "$prefix"
	build_xz "$prev" "$out" "$prefix"
	build_oksh "$prev" "$out" "$prefix"
	build_sbase "$prev" "$out" "$prefix"
	build_cproc "$prev" "$out" "$prefix"
	rm -rf "$out/share"
}

check_final_checksums() {
	final_sha256sum=$TARBALL_ROOT/bin/sha256sum
	checksum_tmp=$WORK/bootstrap.sha256.check

	[ -x "$final_sha256sum" ] || die "missing final sha256sum: $final_sha256sum"
	[ -f "$CHECKSUM_FILE" ] || die "missing checksum file: $CHECKSUM_FILE"

	awk -v xz="$TARBALL" -v gz="$TARBALL_GZ" '
		$2 == "bootstrap.tar.xz" { print $1 "  " xz; found_xz = 1; next }
		$2 == "bootstrap.tar.gz" { print $1 "  " gz; found_gz = 1; next }
		{ bad = 1 }
		END { if (bad || !found_xz || !found_gz) exit 1 }
	' "$CHECKSUM_FILE" > "$checksum_tmp" ||
		die "checksum file must list bootstrap.tar.xz and bootstrap.tar.gz"

	log "check final archive checksums"
	"$final_sha256sum" -c "$checksum_tmp"
}

build_tarball() {
	log "build final prefix=/ root"
	rm -rf "$TARBALL_ROOT"
	build_stage "$ROOT" "$TARBALL_ROOT" /

	final_tar=$TARBALL_ROOT/bin/tar
	final_pigz=$TARBALL_ROOT/bin/pigz
	final_xz=$TARBALL_ROOT/bin/xz
	tar_tmp=$WORK/bootstrap.tar

	log "archive $(basename "$TARBALL")"
	rm -f "$TARBALL" "$tar_tmp"
	"$final_tar" -c -R -C "$TARBALL_ROOT" -f "$tar_tmp" .
	"$final_xz" -T1 -c "$tar_tmp" > "$TARBALL"
	log "final tarball is at $TARBALL"

	log "archive $(basename "$TARBALL_GZ")"
	rm -f "$TARBALL_GZ"
	"$final_pigz" -n -p 1 -c "$tar_tmp" > "$TARBALL_GZ"
	rm -f "$tar_tmp"
	log "final gzip tarball is at $TARBALL_GZ"

	check_final_checksums
}

manifest() {
	dir=$1
	out=$2
	(
		cd "$dir"
		find . -type f -print | sort | while IFS= read -r file; do
			sha256sum "$file" | awk -v file="$file" '{ print "file " file " " $1 }'
		done
		find . -type l -print | sort | while IFS= read -r link; do
			printf 'link %s %s\n' "$link" "$(readlink "$link")"
		done
	) > "$out"
}

compare_roots() {
	old=$1
	new=$2
	old_manifest=$BUILD/root.prev.manifest
	new_manifest=$BUILD/root.manifest

	manifest "$old" "$old_manifest"
	manifest "$new" "$new_manifest"
	diff -u "$old_manifest" "$new_manifest"
}

prepare_sources

log "build host-seeded root"
rm -rf "$ROOT" "$ROOT_PREV" "$ROOT_NEW"
build_stage host "$ROOT" "$ROOT"

if [ "$STAGES" -eq 0 ]; then
	log "host-seeded root is at $ROOT"
	exit 0
fi

if [ "$STAGES" -lt 2 ]; then
	die "STAGES must be at least 2 to check self-hosted convergence"
fi

log "build self-hosted stage 1"
rm -rf "$ROOT_NEW"
build_stage "$ROOT" "$ROOT_NEW" "$ROOT"
rm -rf "$ROOT"
mv "$ROOT_NEW" "$ROOT"

stage=2
while [ "$stage" -le "$STAGES" ]; do
	log "build self-hosted stage $stage"
	rm -rf "$ROOT_PREV" "$ROOT_NEW"
	cp -R "$ROOT" "$ROOT_PREV"
	build_stage "$ROOT" "$ROOT_NEW" "$ROOT"
	rm -rf "$ROOT"
	mv "$ROOT_NEW" "$ROOT"

	log "compare stage $stage with previous root"
	if ! compare_roots "$ROOT_PREV" "$ROOT"; then
		die "stage $stage differed from previous self-hosted root"
	fi

	log "stage $stage matched previous root"
	stage=$((stage + 1))
done

log "final root is at $ROOT"
build_tarball
