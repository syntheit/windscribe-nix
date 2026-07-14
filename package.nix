{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
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

stdenv.mkDerivation rec {
  pname = "windscribe";
  version = "2.23.12";

  src = fetchurl {
    url = "https://github.com/Windscribe/Desktop-App/releases/download/v${version}/windscribe_${version}_amd64.deb";
    hash = "sha256-YySYUm5URisCVyO9RL+89gMkQn7C3nToVwujAfArIy4=";
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
    platforms = [ "x86_64-linux" ];
    mainProgram = "windscribe";
  };
}
