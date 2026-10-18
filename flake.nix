{
  description = "nix-tree-modules: a strict tree of switchable NixOS-style modules (the `here` DSL)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      lib = import ./src { inherit (nixpkgs) lib; };
      extendedLib = baseLib: baseLib.extend (_: _: { nix-tree-modules = lib; });
    in
    {
      inherit lib;

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          results = import ./src/tests { lib = extendedLib pkgs.lib; };
          failed = builtins.filter (n: !results.${n}) (builtins.attrNames results);
        in
        {
          switch = pkgs.runCommand "nix-tree-modules-switch-test" { } (
            if failed == [ ] then
              "touch $out"
            else
              "echo 'nix-tree-modules switch test failures: ${builtins.concatStringsSep ", " failed}' >&2; exit 1"
          );
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellScriptBin "nixfmt-tree" ''
          files=()
          for f in "$@"; do
            case "$f" in
              *.nix) files+=("$f") ;;
            esac
          done
          [ ''${#files[@]} -eq 0 ] && exit 0
          exec ${pkgs.nixfmt}/bin/nixfmt "''${files[@]}"
        ''
      );
    };
}
