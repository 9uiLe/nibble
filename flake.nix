{
  description = "nibble development and CI tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      toolsFor = pkgs: [
        (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
        pkgs.actionlint
        pkgs.shellcheck
      ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = toolsFor pkgs;
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      checks = forAllSystems (pkgs: {
        workflow-policy =
          pkgs.runCommand "nibble-workflow-policy"
            {
              nativeBuildInputs = toolsFor pkgs;
            }
            ''
              mkdir -p .github scripts
              cp -R ${./.github/workflows} .github/workflows
              cp ${./scripts/check_workflows.py} scripts/check_workflows.py
              python3 scripts/check_workflows.py
              shopt -s nullglob
              actionlint .github/workflows/*.yml .github/workflows/*.yaml
              touch "$out"
            '';

        nix-format =
          pkgs.runCommand "nibble-nix-format"
            {
              nativeBuildInputs = [ pkgs.nixfmt ];
            }
            ''
              nixfmt --check ${./flake.nix}
              touch "$out"
            '';
      });
    };
}
