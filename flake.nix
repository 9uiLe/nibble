{
  description = "nibble development and CI tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.hamio.url = "github:9uiLe/hamio";
  inputs.wts = {
    url = "github:9uiLe/wts/f1cb5dda3a52a757cba841e40ae806647c5b09b2";
    flake = false;
  };
  inputs.sim-use = {
    url = "file+https://github.com/lycorp-jp/sim-use/releases/download/v0.14.0/sim-use-v0.14.0.tar.gz";
    flake = false;
  };

  inputs.rive-cli = {
    url = "file+https://releases.rive.app/cli/v1.0.4/rive-macos-arm64.tar.gz";
    flake = false;
  };

  outputs =
    {
      nixpkgs,
      sim-use,
      rive-cli,
      hamio,
      wts,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # Include hamio only on systems for which the locked input provides a package.
      hamioFor =
        pkgs:
        pkgs.lib.optional (builtins.hasAttr pkgs.stdenv.hostPlatform.system hamio.packages)
          hamio.packages.${pkgs.stdenv.hostPlatform.system}.hamio;
      # Upstream currently exports a development shell, but no consumable package.
      # Run its unchanged source with locked Bun and its sole runtime dependency.
      wtsFor =
        pkgs:
        let
          manifest = builtins.fromJSON (builtins.readFile "${wts}/package.json");
          commander = pkgs.fetchurl {
            url = "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz";
            hash = "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==";
          };
        in
        assert manifest.dependencies == { commander = "15.0.0"; };
        pkgs.stdenvNoCC.mkDerivation {
          pname = "wts";
          version = "${manifest.version}-${builtins.substring 0 7 wts.rev}";
          src = wts;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontBuild = true;
          installPhase = ''
            mkdir -p "$out/lib/wts/node_modules/commander" "$out/bin"
            cp -R src skills package.json "$out/lib/wts/"
            tar -xzf ${commander} -C "$out/lib/wts/node_modules/commander" --strip-components=1
            makeWrapper ${pkgs.bun}/bin/bun "$out/bin/wts" \
              --add-flags "$out/lib/wts/src/cli.ts" \
              --prefix PATH : ${
                pkgs.lib.makeBinPath (
                  [
                    pkgs.git
                    pkgs.gh
                  ]
                  ++ hamioFor pkgs
                )
              }
          '';
          meta = {
            description = "Git Worktree Session";
            homepage = "https://github.com/9uiLe/wts";
            license = pkgs.lib.licenses.mit;
            platforms = [ "aarch64-darwin" ];
          };
        };
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
      riveCLIFor =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "rive-cli";
          version = "1.0.4";
          src = rive-cli;
          unpackPhase = ''tar -xzf "$src"'';
          dontBuild = true;
          dontFixup = true;
          installPhase = ''
            mkdir -p "$out/bin"
            cp -R rive docs samples "$out/bin/"
            chmod +x "$out/bin/rive"
          '';
          meta.platforms = [ "aarch64-darwin" ];
        };
      pythonFor =
        pkgs:
        pkgs.python3.withPackages (
          ps:
          [
            ps.pyyaml
            ps.tree-sitter-language-pack
          ]
          ++ (import ./tools/ui-design/python-packages.nix) ps
        );
      toolsFor =
        pkgs:
        [
          (pythonFor pkgs)
          pkgs.actionlint
          pkgs.shellcheck
          pkgs.gh
          pkgs.git
        ]
        ++ hamioFor pkgs
        ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ (simUseFor pkgs) ]
        ++ pkgs.lib.optionals (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") [
          (riveCLIFor pkgs)
          (wtsFor pkgs)
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
        rive-assets =
          pkgs.runCommand "nibble-rive-assets"
            {
              nativeBuildInputs = [ (pythonFor pkgs) ] ++ hamioFor pkgs;
              NIBBLE_UI_FORMAT = "json";
            }
            ''
              python3 ${./.}/scripts/rive_assets.py check --root ${./.}
              touch "$out"
            '';

        documentation =
          pkgs.runCommand "nibble-documentation"
            {
              nativeBuildInputs = [ (pythonFor pkgs) ] ++ hamioFor pkgs;
              NIBBLE_UI_FORMAT = "json";
            }
            ''
              python3 ${./.}/scripts/check_docs.py --root ${./.}
              touch "$out"
            '';
        swift-library-policy =
          pkgs.runCommand "nibble-swift-library-policy"
            {
              nativeBuildInputs = [ (pythonFor pkgs) ] ++ hamioFor pkgs;
              NIBBLE_UI_FORMAT = "json";
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
                pkgs.shellcheck
              ]
              ++ hamioFor pkgs
              ++ pkgs.lib.optionals (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") [
                (wtsFor pkgs)
              ];
              NIBBLE_UI_FORMAT = "json";
              NIBBLE_REQUIRE_HAMIO = if hamioFor pkgs == [ ] then "0" else "1";
            }
            ''
              cp -R ${./scripts} scripts
              cp ${./.wts.json} .wts.json
              mkdir -p tools
              cp -R ${./tools/ui-design} tools/ui-design
              chmod -R u+w scripts tools
              shellcheck scripts/deploy-testflight.sh
              python3 -m unittest discover -s scripts/tests -v
              touch "$out"
            '';
        ui-design =
          pkgs.runCommand "ui-design-contracts"
            {
              nativeBuildInputs = [ ((import ./tools/ui-design/default.nix) pkgs) ];
            }
            ''
              cp -R ${./tools/ui-design} toolkit
              chmod -R u+w toolkit
              python3 -m unittest discover -s toolkit/tests -v
              touch "$out"
            '';
        workflow-policy =
          pkgs.runCommand "nibble-workflow-policy"
            {
              nativeBuildInputs = toolsFor pkgs;
              NIBBLE_UI_FORMAT = "json";
            }
            ''
              mkdir -p .github scripts
              cp -R ${./.github/workflows} .github/workflows
              cp ${./scripts/check_workflows.py} scripts/check_workflows.py
              cp ${./scripts/script_ui.py} scripts/script_ui.py
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
              nixfmt --check ${./flake.nix} ${./tools/ui-design/default.nix} ${./tools/ui-design/python-packages.nix}
              touch "$out"
            '';
      });
    };
}
