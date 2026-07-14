{ lib, ... }:

{
  name = "windscribe";

  meta.maintainers = with lib.maintainers; [ syntheit ];

  nodes.machine = {
    services.windscribe.enable = true;
  };

  testScript = ''
    machine.wait_for_unit("windscribe-helper.service")
    machine.wait_for_file("/var/run/windscribe/helper.sock")

    # The bundled OpenVPN binary must actually load and run - this exercises
    # the autoPatchelf'd interpreter, rpath, and the bundled libcrypto/libssl
    # in $out/opt/windscribe/lib.
    machine.succeed("/opt/windscribe/windscribeopenvpn --version")

    # The Go wstunnel is intentionally unpatched and relies on nix-ld for
    # /lib64/ld-linux-x86-64.so.2. Regression check for the segfault that
    # autoPatchelf would otherwise introduce in the Go runtime.
    machine.succeed("/opt/windscribe/windscribewstunnel --version")

    # The CLI wrapper resolves through security.wrappers (setcap'd copy in
    # /run/wrappers/bin). --help exits 0 without requiring an account or display.
    machine.succeed("windscribe-cli --help")
  '';
}
