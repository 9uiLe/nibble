{
  description = "nibble development and CI tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.sim-use = {
    url = "file+https://github.com/lycorp-jp/sim-use/releases/download/v0.14.0/sim-use-v0.14.0.tar.gz";
    flake = false;
  };

  outputs =
    { nixpkgs, sim-use, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      simUseFor =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "sim-use";
          version = "0.14.0";
          src = sim-use;
          unpackPhase = ''tar -xzf "$src"'';
          dontBuild = true;
          # Preserve the upstream Mach-O signature and sibling resource bundles.
          dontFixup = true;
          installPhase = ''
            mkdir -p "$out/bin"
            cp -R sim-use SimUse_*.bundle "$out/bin/"
            chmod +x "$out/bin/sim-use"
          '';
          meta = {
            description = "Observe and operate iOS Simulators";
            homepage = "https://github.com/lycorp-jp/sim-use";
            license = pkgs.lib.licenses.asl20;
            platforms = pkgs.lib.platforms.darwin;
          };
        };
      pythonFor =
        pkgs:
        pkgs.python3.withPackages (ps: [
          ps.pyyaml
          ps.cryptography
          ps.markdown-it-py
          ps.tree-sitter-language-pack
        ]);
      toolsFor =
        pkgs:
        [
          (pythonFor pkgs)
          pkgs.actionlint
          pkgs.shellcheck
          pkgs.gh
          pkgs.git
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ (simUseFor pkgs) ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = toolsFor pkgs;
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      checks = forAllSystems (pkgs: {
        documentation =
          pkgs.runCommand "nibble-documentation"
            {
              nativeBuildInputs = [ (pythonFor pkgs) ];
            }
            ''
              python3 ${./scripts}/check_docs.py --root ${./.}
              touch "$out"
            '';
        swift-library-policy =
          pkgs.runCommand "nibble-swift-library-policy"
            {
              nativeBuildInputs = [ (pythonFor pkgs) ];
            }
            ''
              python3 ${./scripts}/check_swift_policy.py --root ${./.}
              touch "$out"
            '';
        ios-tooling =
          pkgs.runCommand "nibble-ios-tooling"
            {
              nativeBuildInputs = [
                (pythonFor pkgs)
                pkgs.git
              ];
            }
            ''
              cp -R ${./scripts} scripts
              chmod -R u+w scripts
              python3 -m unittest discover -s scripts/tests -v
              touch "$out"
            '';
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
