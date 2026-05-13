{
  pkgs ? import <nixpkgs> { },
  target ? "x86_64-linux-musl",
}:

let
  lib = pkgs.lib;

  cprocSrc = pkgs.fetchFromGitHub {
    owner = "andrewchambers";
    repo = "cproc";
    rev = "c023205e716896727addbfcc870034c20fc29b1a";
    hash = "sha256-llDTlwwKzzAkj3Q37mw7cMVTO9XrDO1+GfPBFl9rDU8=";
  };
  muslSrc = pkgs.fetchFromGitHub {
    owner = "andrewchambers";
    repo = "musl";
    rev = "4b8873814833c15af9d28f7c1d483345b60bde59";
    hash = "sha256-8evkOSkoY33iSQ0soepApSYLT+EtEYpEcmtZRBFZEUk=";
  };
  mcppSrc = pkgs.fetchFromGitHub {
    owner = "museoa";
    repo = "mcpp";
    rev = "2.7.2.2";
    hash = "sha256-wz225bhBF0lFerOAhl8Rwmw8ItHd9BXQceweD9BqvEQ=";
  };
  okshSrc = pkgs.fetchFromGitHub {
    owner = "ibara";
    repo = "oksh";
    rev = "oksh-7.8";
    hash = "sha256-fgTwj1U/bySVkQReE799Z2gZ0/SEek08WSdpHUHCHhk=";
  };
  tinybinutilsSrc = pkgs.fetchFromGitHub {
    owner = "andrewchambers";
    repo = "tinybinutils";
    rev = "30978e16be98c30fb441ce2926c84871bb03779b";
    hash = "sha256-t3Uo8CXA5CCTKOdSR0R0b6ruSC3SSaXtL4ey35ip9iI=";
  };
  zlibSrc = pkgs.fetchzip {
    url = "https://zlib.net/fossils/zlib-1.3.1.tar.gz";
    hash = "sha256-acY8yFzIRYbrZ2CGODoxLnZuppsP6KZy19I9Yy77pfc=";
  };
  makeSrc = pkgs.fetchzip {
    url = "https://ftpmirror.gnu.org/make/make-4.4.1.tar.gz";
    hash = "sha256-+Cg7R8wougcWcFf6u5B3lVX6RRgMRYZ1CD+e21URP5A=";
  };
  mawkSrc = pkgs.fetchzip {
    url = "https://invisible-mirror.net/archives/mawk/mawk-1.3.4-20240819.tgz";
    hash = "sha256-zlJN4oOFBTOM4/mjYAgk5PifnKn6ldFQoxFBpyuVz4w=";
  };
  sbaseSrc = pkgs.fetchgit {
    url = "https://git.suckless.org/sbase";
    rev = "c1341583c96307cb0e6152c963ed23c4d56a4278";
    hash = "sha256-v6VAi8Xv5cygN3z+4OqLTRlOH98sskt+v4i1x0xI65Q=";
  };

  prepareSource =
    {
      name,
      src,
      patches ? [ ],
    }:
    if patches == [ ] then
      src
    else
      pkgs.applyPatches {
        inherit name src patches;
      };

  retouch = files: lib.concatMapStringsSep "\n" (file: "touch ${lib.escapeShellArg file}") files;

  mcppGeneratedFiles = [
    "aclocal.m4"
    "configure"
    "Makefile.in"
    "src/Makefile.in"
    "src/config.h.in"
    "tests/Makefile.in"
  ];

  gnumakeGeneratedFiles = [
    "aclocal.m4"
    "configure"
    "Makefile.in"
    "src/Makefile.in"
    "lib/Makefile.in"
    "po/Makefile.in.in"
    "doc/Makefile.in"
  ];

  mawkGeneratedFiles = [
    "parse.c"
    "parse.h"
    "scan.c"
    "scancode.h"
    "Makefile.in"
    "configure"
    "config_h.in"
  ];

  cprocBootstrapSrc = prepareSource {
    name = "bootstrap-cproc-src";
    src = cprocSrc;
  };

  mcppBootstrapSrc = prepareSource {
    name = "bootstrap-mcpp-src";
    src = mcppSrc;
    patches = [ ./patches/mcpp-bootstrap.patch ];
  };

  gnumakeBootstrapSrc = prepareSource {
    name = "bootstrap-gnumake-src";
    src = makeSrc;
    patches = [ ./patches/gnumake-bootstrap.patch ];
  };

  mawkBootstrapSrc = prepareSource {
    name = "bootstrap-mawk-src";
    src = mawkSrc;
    patches = [ ./patches/mawk-bootstrap.patch ];
  };

  okshBootstrapSrc = prepareSource {
    name = "bootstrap-oksh-src";
    src = okshSrc;
    patches = [ ./patches/oksh-bootstrap.patch ];
  };

  sbaseBootstrapSrc = prepareSource {
    name = "bootstrap-sbase-src";
    src = sbaseSrc;
    patches = [ ./patches/sbase-bootstrap.patch ];
  };

  hostCC = "${pkgs.stdenv.cc}/bin/cc";
  gnuMake = "${pkgs.gnumake}/bin/make";
  hostPath = lib.makeBinPath [
    pkgs.bash
    pkgs.binutils
    pkgs.coreutils
    pkgs.diffutils
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gnumake
    pkgs.which
  ];

  # mcpp is a standalone preprocessor, so give it the target macros that
  # cproc previously inherited from the host compiler's cpp.
  targetCppFlags = lib.concatStringsSep " " [
    "-V199901L"
    "-W0"
    "-e"
    "utf8"
    "-D__linux__"
    "-D__unix__"
    "-D__ELF__"
    "-D__x86_64__"
    "-D__amd64__"
    "-D__LP64__"
  ];

  stageTools =
    prev:
    lib.optionals (prev != null) [
      prev.binutils
      prev.cproc
      prev.mawk
      prev.gnumake
      prev.mcpp
      prev.oksh
      prev.sbase
    ];

  stagePath = prev: lib.makeBinPath (stageTools prev);
  toolPath = prev: if prev == null then hostPath else stagePath prev;

  shellFor = prev: if prev == null then "${pkgs.bash}/bin/sh" else "${prev.oksh}/bin/oksh";
  makeFor = prev: if prev == null then gnuMake else "${prev.gnumake}/bin/make";
  arFor = prev: if prev == null then "${pkgs.binutils}/bin/ar" else "${prev.binutils}/bin/ar";
  ranlibFor = prev: if prev == null then "${pkgs.binutils}/bin/ranlib" else "${prev.binutils}/bin/ranlib";

  ccBinFor = prev: if prev == null then hostCC else "${prev.cproc}/bin/cproc";
  ccFor = prev: libc: if prev == null then hostCC else "${ccBinFor prev} -I${libc}/include -L${libc}/lib";
  ccForMusl = prev: if prev == null then "${hostCC} -no-pie" else "${prev.cproc}/bin/cproc";
  cflagsFor = prev: libc: if prev == null then "" else "-I${libc}/include";
  ldflagsFor = prev: libc: if prev == null then "" else "-L${libc}/lib";
  commonEnv =
    prev: ''
      export PATH=${toolPath prev}
      export SHELL=${shellFor prev}
      export CONFIG_SHELL=${shellFor prev}
      export AR=${arFor prev}
      export RANLIB=${ranlibFor prev}
      export AWK=awk
      export SED=sed
      export GREP=grep
      export EGREP='grep -E'
      export FGREP='grep -F'
      export ac_cv_path_SED=sed
      export lt_cv_path_SED=sed
      export MAKEINFO=true
      export lt_cv_path_MAGIC_CMD=:
    '';

  mkDerivationFor = prev: if prev == null then pkgs.stdenv.mkDerivation else pkgs.stdenvNoCC.mkDerivation;

  commonAttrs =
    prev:
    {
      strictDeps = true;
      nativeBuildInputs = stageTools prev;
      hardeningDisable = [ "all" ];
      dontConfigure = false;
      dontFixup = true;
      doCheck = false;
      dontUpdateAutotoolsGnuConfigScripts = true;
      NIX_CFLAGS_COMPILE = "";
      NIX_LDFLAGS = "";
      prePatch = commonEnv prev;
      unpackPhase = ''
        ${commonEnv prev}
        mkdir source
        cp_tries=0
        while :; do
          if cp -Rf "$src"/. source 2>copy.log; then
            rm -f copy.log
            break
          fi
          cp_tries=$((cp_tries + 1))
          if [ "$cp_tries" -ge 20 ]; then
            cat copy.log >&2
            exit 1
          fi
          chmod -R u+w source
        done
        chmod -R u+w source
        echo "source root is source"
        cd source
      '';
    };

  mkMusl =
    name: prev:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-musl";
        version = "local";
        src = muslSrc;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          CC=${lib.escapeShellArg (ccForMusl prev)} \
            ${shellFor prev} ./configure \
              --prefix=$out \
              --target=${lib.escapeShellArg target} \
              --disable-shared \
              --enable-static
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1} \
            AR=$AR RANLIB=$RANLIB \
            lib/libc.a lib/crt1.o lib/crti.o lib/crtn.o
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          ${makeFor prev} install AR=$AR RANLIB=$RANLIB
          runHook postInstall
        '';
      }
    );

  mkMcpp =
    name: prev: libc:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-mcpp";
        version = "local";
        src = mcppBootstrapSrc;

        postPatch = retouch mcppGeneratedFiles;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          CC=${lib.escapeShellArg (ccFor prev libc)} \
          CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
          LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
            ${shellFor prev} ./configure \
              --prefix=$out \
              --enable-mcpplib \
              --disable-shared \
              --enable-static
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1}
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          ${makeFor prev} install
          runHook postInstall
        '';
      }
    );

  mkGnumake =
    name: prev: libc:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-gnumake";
        version = "4.4.1";
        src = gnumakeBootstrapSrc;

        postPatch = retouch gnumakeGeneratedFiles;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          CC=${lib.escapeShellArg (ccFor prev libc)} \
          CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
          LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
          make_cv_sys_gnu_glob=no \
            ${shellFor prev} ./configure \
              --prefix=$out \
              --disable-dependency-tracking \
              --disable-nls \
              --without-guile
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1}
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          ${makeFor prev} install
          rm -rf $out/share/info
          runHook postInstall
        '';
      }
    );

  mkMawk =
    name: prev: libc:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-mawk";
        version = "1.3.4-20240819";
        src = mawkBootstrapSrc;

        postPatch = retouch mawkGeneratedFiles;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          CC=${lib.escapeShellArg (ccFor prev libc)} \
          BUILD_CC=${lib.escapeShellArg (ccFor prev libc)} \
          CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
          BUILD_CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
          LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
          BUILD_LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
            ${shellFor prev} ./configure \
              --prefix=$out \
              --enable-builtin-regex
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1} YACC=false
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          mkdir -p $out/bin
          cp mawk $out/bin/mawk
          ln -s mawk $out/bin/awk
          runHook postInstall
        '';
      }
    );

  mkZlib =
    name: prev: libc:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-zlib";
        version = "1.3.1";
        src = zlibSrc;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          CC=${lib.escapeShellArg (ccFor prev libc)} \
          CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
          LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
          AR=$AR \
          RANLIB=$RANLIB \
            ${shellFor prev} ./configure \
              --prefix=$out \
              --static
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1}
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          ${makeFor prev} install
          rm -rf $out/share
          runHook postInstall
        '';
      }
    );

  mkBinutils =
    name: prev: libc:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-tinybinutils";
        version = "local";
        src = tinybinutilsSrc;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} clean
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1} \
            CC=${lib.escapeShellArg (ccFor prev libc)} \
            CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
            LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
            tinyld tinyas tinyar
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          mkdir -p $out/bin
          cp tinyld tinyas tinyar $out/bin/
          ln -s tinyld $out/bin/ld
          ln -s tinyas $out/bin/as
          ln -s tinyar $out/bin/ar
          printf '%s\n' '#!${shellFor prev}' 'exit 0' > $out/bin/ranlib
          chmod +x $out/bin/ranlib
          runHook postInstall
        '';
      }
    );

  mkOksh =
    name: prev: libc:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-oksh";
        version = "local";
        src = okshBootstrapSrc;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          CC=${lib.escapeShellArg (ccFor prev libc)} \
          CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
          LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
            ${shellFor prev} ./configure \
              --prefix=$out \
              --no-strip \
              --disable-curses \
              ${lib.optionalString (prev != null) "--enable-static"}
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1}
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          ${makeFor prev} install
          ln -s oksh $out/bin/sh
          runHook postInstall
        '';
      }
    );

  mkSbase =
    name: prev: libc:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-sbase";
        version = "local";
        src = sbaseBootstrapSrc;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          env MAKEFLAGS= ${makeFor prev} \
            CC=${lib.escapeShellArg (ccBinFor prev)} \
            AR=$AR RANLIB=$RANLIB \
            CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
            LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
            SMAKE=${lib.escapeShellArg (makeFor prev)}
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          env MAKEFLAGS= ${makeFor prev} \
            PREFIX=$out \
            MANPREFIX=$out/share/man \
            CC=${lib.escapeShellArg (ccBinFor prev)} \
            AR=$AR RANLIB=$RANLIB \
            CFLAGS=${lib.escapeShellArg (cflagsFor prev libc)} \
            LDFLAGS=${lib.escapeShellArg (ldflagsFor prev libc)} \
            SMAKE=${lib.escapeShellArg (makeFor prev)} \
            sbase-box-install
          runHook postInstall
        '';
      }
    );

  mkCproc =
    name: prev: stage:
    (mkDerivationFor prev) (
      commonAttrs prev
      // {
        pname = "bootstrap-${name}-cproc";
        version = "local";
        src = cprocBootstrapSrc;

        configurePhase = ''
          runHook preConfigure
          ${commonEnv prev}
          ${shellFor prev} ./configure \
            --prefix=$out \
            --target=${lib.escapeShellArg target} \
            --with-cpp=${lib.escapeShellArg "${stage.mcpp}/bin/mcpp ${targetCppFlags}"} \
            --with-as=${lib.escapeShellArg "${stage.binutils}/bin/as"} \
            --with-ld=${lib.escapeShellArg "${stage.binutils}/bin/ld -static -L${stage.musl}/lib"} \
            --with-ldso= \
            CC=${lib.escapeShellArg (ccFor prev stage.musl)} \
            CFLAGS=${lib.escapeShellArg (cflagsFor prev stage.musl)} \
            LDFLAGS=${lib.escapeShellArg "${ldflagsFor prev stage.musl} -s"}
          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ${commonEnv prev}
          ${makeFor prev} -j''${NIX_BUILD_CORES:-1}
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${commonEnv prev}
          ${makeFor prev} install
          runHook postInstall
        '';
      }
    );

  mkStage =
    name: prev:
    let
      stage = rec {
        musl = mkMusl name prev;
        mcpp = mkMcpp name prev musl;
        gnumake = mkGnumake name prev musl;
        mawk = mkMawk name prev musl;
        zlib = mkZlib name prev musl;
        binutils = mkBinutils name prev musl;
        oksh = mkOksh name prev musl;
        sbase = mkSbase name prev musl;
        cproc = mkCproc name prev stage;
        env = pkgs.buildEnv {
          name = "bootstrap-${name}-env";
          ignoreCollisions = true;
          paths = [
            cproc
            musl
            mcpp
            gnumake
            mawk
            zlib
            binutils
            oksh
            sbase
          ];
        };
      };
    in
    stage;

  stage1 = mkStage "stage1" null;
  stage2 = mkStage "stage2" stage1;
  stage3 = mkStage "stage3" stage2;
  stage4 = mkStage "stage4" stage3;
  final = stage4;

  finalEnv = pkgs.buildEnv {
    name = "cproc-bootstrap-self-hosted";
    ignoreCollisions = true;
    paths = [
      final.cproc
      final.musl
      final.mcpp
      final.gnumake
      final.mawk
      final.zlib
      final.binutils
      final.oksh
      final.sbase
    ];
  };

in
finalEnv
// {
  passthru = {
    inherit stage1 stage2 stage3 stage4 final;
    stages = [
      stage1
      stage2
      stage3
      stage4
    ];
  };
}
