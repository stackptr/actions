{
  description = "Shared GitHub Actions for stackptr repos";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: rec {
      # The same script the action runs, for services on rc hosts.
      slack-notify = pkgs.writeShellApplication {
        name = "slack-notify";
        runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
        text = builtins.readFile ./slack-notify/notify.sh;
      };
      default = slack-notify;
    });

    checks = forAllSystems (pkgs: {
      # writeShellApplication runs shellcheck on notify.sh as it builds.
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.slack-notify;

      shellcheck = pkgs.runCommand "shellcheck" {nativeBuildInputs = [pkgs.shellcheck];} ''
        shellcheck ${./slack-notify}/*.sh ${./slack-notify/test/run.sh}
        touch $out
      '';

      # Every fixture's dry-run payload, plus response handling with curl stubbed.
      payloads =
        pkgs.runCommand "payloads" {
          nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.curl pkgs.diffutils pkgs.gnused pkgs.jq];
        } ''
          bash ${./slack-notify/test/run.sh} ${./slack-notify}
          touch $out
        '';
    });

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
