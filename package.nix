{
  lib,
  stdenv,
  fetchurl,
  fetchpatch,
  dpkg,
  autoPatchelfHook,
  buildPackages,
  makeWrapper,
  # GUI dependencies (linked)
  dbus,
  glib,
  brotli,
  libdrm,
  libxcb,
  libx11,
  libxcb-wm,
  libxcb-image,
  libxcb-keysyms,
  libxcb-render-util,
  libxcb-cursor,
  libxcb-util,
  libxkbcommon,
  wayland,
  libglvnd,
  harfbuzz,
  freetype,
  fontconfig,
  zstd,
  pcre2,
  # OpenVPN dependencies
  libnl,
  libcap_ng,
  acl,
  # Helper/GUI libraries added in 2.24
  nftables,
  systemdLibs,
  # Runtime tools used by helper scripts
  iptables,
  iproute2,
  systemd,
  util-linux,
  kmod,
  gnused,
  gawk,
  gnugrep,
  coreutils,
  e2fsprogs,
  wireguard-tools,
}:

let
  # Upstream ships per-arch .deb builds under identical layouts. The GUI, CLI,
  # helper and openvpn binaries are dynamically linked on both arches (aarch64
  # uses /lib/ld-linux-aarch64.so.1; amd64 uses /lib64/ld-linux-x86-64.so.2 —
  # nix-ld provides both). The bundled Go binaries are dynamically linked on
  # amd64 (so restoreGoBinaries below matters) and statically linked on
  # aarch64 (autoPatchelf ignores them; the restore is a harmless no-op).
  sources = {
    x86_64-linux = {
      urlArch = "amd64";
      hash = "sha256-eanxf898hY6NKzHM2umrfabjhA+8kKl0AQTLCsvOGZE=";
    };
    aarch64-linux = {
      urlArch = "arm64";
      hash = "sha256-pvbcsQ4Uz51bDmdvoE69l3E7/ivf7OFGWB5Psoi8Fls=";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "windscribe: unsupported system ${stdenv.hostPlatform.system}");

  # windscribeopenvpn is a non-PIE ET_EXEC that upstream already ran through
  # patchelf (RUNPATH /opt/windscribe/lib, extra header LOAD below 0x400000).
  # patchelf 0.19.2 aborts in shiftFile (Assertion `splitIndex == -1') when
  # autoPatchelf grows its interpreter and then rewrites its RPATH.
  # patchelfUnstable (0.18.0-unstable-2025-08-13) aborts the same way; 0.15.2
  # and patchelf master both work. Carry the upstream fix (NixOS/patchelf#672,
  # unreleased; see also NixOS/patchelf#583 and #675) until nixpkgs ships a
  # patchelf newer than 0.19.2, then drop this and the PATH override below.
  # The patch targets 0.19.2 only; any other patchelf is used as-is. Only
  # src/ is patched: the tests/ hunks touch Makefile.am, which would make the
  # release tarball's generated Makefiles try to rerun automake.
  patchelfFixed =
    let
      inherit (buildPackages) patchelf; # runs at build time
    in
    if patchelf.version == "0.19.2" then
      patchelf.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (fetchpatch {
            name = "patchelf-fix-executable-header-load-overlap.patch";
            url = "https://github.com/NixOS/patchelf/commit/59acc3d98b4961cfddf02090d9426ac735603218.patch";
            includes = [ "src/*" ];
            hash = "sha256-rQWWZlCa4IRrcPcxMD2xrTTD4nLOsWfdZLOk9UoIOIs=";
          })
        ];
      })
    else
      patchelf;
in
stdenv.mkDerivation rec {
  pname = "windscribe";
  version = "2.24.13";

  src = fetchurl {
    url = "https://github.com/Windscribe/Desktop-App/releases/download/v${version}/windscribe_${version}_${source.urlArch}.deb";
    inherit (source) hash;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    glib
    brotli
    libdrm
    libxcb
    libx11
    libxcb-wm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-cursor
    libxcb-util
    libxkbcommon
    wayland
    libglvnd
    harfbuzz
    freetype
    fontconfig
    zstd
    pcre2
    libnl
    libcap_ng
    acl
    nftables # libnftables.so.1 (helper)
    systemdLibs # libudev.so.1 (GUI)
    stdenv.cc.cc.lib
  ];

  # Qt loads libdbus-1 via dlopen() - not detected by autoPatchelfHook
  runtimeDependencies = [
    (lib.getLib dbus)
  ];

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase =
    let
      scriptPath = lib.makeBinPath [
        iptables
        iproute2
        systemd
        util-linux
        kmod
        gnused
        gawk
        gnugrep
        coreutils
        e2fsprogs
        wireguard-tools
      ];
    in
    ''
      runHook preInstall

      mkdir -p $out/opt
      cp -r opt/windscribe $out/opt/

      # Save original Go binaries BEFORE any patching. autoPatchelf corrupts
      # them (segfault in ld-linux) - we restore the originals in postFixup.
      mkdir -p $TMPDIR/go-originals
      for bin in windscribewstunnel windscribeamneziawg windscribectrld; do
        cp "opt/windscribe/$bin" "$TMPDIR/go-originals/" 2>/dev/null || true
      done

      # Inject PATH into helper scripts so they find iptables, ip, wg, etc.
      for script in $out/opt/windscribe/scripts/*; do
        if [ -f "$script" ] && head -1 "$script" | grep -q "^#!"; then
          sed -i "2i export PATH=\"${scriptPath}:\$PATH\"" "$script"
        fi
      done

      # Replace self-update script (calls apt/dnf/pacman which don't exist on NixOS)
      cat > $out/opt/windscribe/scripts/install-update << 'EOF'
      #!/bin/bash
      echo "Windscribe updates on NixOS are managed through the windscribe-nix flake."
      echo "Update the flake input and rebuild your system."
      exit 0
      EOF
      chmod +x $out/opt/windscribe/scripts/install-update

      # Desktop entry and icons
      mkdir -p $out/share/applications
      cp usr/share/applications/windscribe.desktop $out/share/applications/
      substituteInPlace $out/share/applications/windscribe.desktop \
        --replace-fail "/opt/windscribe/Windscribe" "windscribe"
      cp -r usr/share/icons $out/share/

      # Autostart entry (app checks /etc/windscribe/autostart/ for "Launch on Startup")
      mkdir -p $out/etc/xdg/autostart
      cp etc/windscribe/autostart/windscribe.desktop $out/etc/xdg/autostart/
      substituteInPlace $out/etc/xdg/autostart/windscribe.desktop \
        --replace-fail "/opt/windscribe/Windscribe" "windscribe"

      # CLI and GUI wrappers
      mkdir -p $out/bin
      makeWrapper $out/opt/windscribe/Windscribe $out/bin/windscribe \
        --prefix PATH : "${scriptPath}"
      makeWrapper $out/opt/windscribe/windscribe-cli $out/bin/windscribe-cli \
        --prefix PATH : "${scriptPath}"

      runHook postInstall
    '';

  # Bundled libs (libwsnet, libcrypto, libssl) live in $out/opt/windscribe/lib
  preFixup = ''
    # auto-patchelf runs `patchelf` from PATH; put the fixed one first (see
    # patchelfFixed above). Also covers the --shrink-rpath pass in fixupPhase.
    export PATH="${lib.getBin patchelfFixed}/bin:$PATH"

    addAutoPatchelfSearchPath $out/opt/windscribe/lib

    # Register a hook that runs AFTER autoPatchelf (which is also a
    # postFixupHook). This restores the original Go binaries from the .deb
    # that were saved during installPhase. autoPatchelf corrupts Go binaries
    # (segfault in ld-linux), so we overwrite them with the unpatched originals.
    restoreGoBinaries() {
      for bin in "$TMPDIR/go-originals"/*; do
        cp "$bin" "$out/opt/windscribe/$(basename "$bin")"
      done
    }
    postFixupHooks+=(restoreGoBinaries)
  '';

  meta = with lib; {
    description = "Windscribe VPN client";
    homepage = "https://windscribe.com";
    license = licenses.gpl2;
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames sources;
    mainProgram = "windscribe";
  };
}
