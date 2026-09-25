{
  description = "nibble development and CI tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.hamio.url = "github:9uiLe/hamio";
  inputs.sim-use = {
    url = "file+https://github.com/lycorp-jp/sim-use/releases/download/v0.14.0/sim-use-v0.14.0.tar.gz";
    flake = false;
  };

  inputs.rive-cli = {
    url = "file+https://releases.rive.app/cli/v1.0.4/rive-macos-arm64.tar.gz";
    flake = false;
  };

  # Rive rendering foundation sources; build definitions live in runtime/rive.
  inputs.rive-ios-source = {
    url = "github:rive-app/rive-ios/4c42e5839167a06a56d336e80813578bac018dde";
    flake = false;
  };
  inputs.rive-core-source = {
    url = "github:rive-app/rive-runtime/1af8ccbefdf906ea5c33e80845360c62b43bafb3";
    flake = false;
  };
  inputs.rive-harfbuzz = {
    url = "github:rive-app/harfbuzz/rive_13.1.1";
    flake = false;
  };
  inputs.rive-sheenbidi = {
    url = "github:Tehreer/SheenBidi/v2.6";
    flake = false;
  };
  inputs.rive-yoga = {
    url = "github:rive-app/yoga/rive_changes_v2_0_1_3_grid";
    flake = false;
  };
  inputs.rive-miniaudio = {
    url = "github:rive-app/miniaudio/rive_changes_5";
    flake = false;
  };
  inputs.rive-luau = {
    url = "github:luigi-rosso/luau/rive_0_734";
    flake = false;
  };
  inputs.rive-libhydrogen = {
    url = "github:luigi-rosso/libhydrogen/rive_0_2";
    flake = false;
  };
  inputs.rive-ply = {
    url = "github:dabeaz/ply/3.11";
    flake = false;
  };

  outputs =
    {
      nixpkgs,
      sim-use,
      rive-cli,
      hamio,
      ...
    }@inputs:
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
          pkgs.firebase-tools
          pkgs.premake5
        ]
        ++ hamioFor pkgs
        ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ (simUseFor pkgs) ]
        ++ pkgs.lib.optionals (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") [ (riveCLIFor pkgs) ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = toolsFor pkgs;
          NIBBLE_RIVE_SOURCES = pkgs.linkFarm "nibble-rive-sources" [
            {
              name = "rive-ios";
              path = inputs.rive-ios-source;
            }
            {
              name = "rive-runtime";
              path = inputs.rive-core-source;
            }
            {
              name = "rive-app_harfbuzz_rive_13.1.1";
              path = inputs.rive-harfbuzz;
            }
            {
              name = "Tehreer_SheenBidi_v2.6";
              path = inputs.rive-sheenbidi;
            }
            {
              name = "rive-app_yoga_rive_changes_v2_0_1_3_grid";
              path = inputs.rive-yoga;
            }
            {
              name = "rive-app_miniaudio_rive_changes_5";
              path = inputs.rive-miniaudio;
            }
            {
              name = "luigi-rosso_luau_rive_0_734";
              path = inputs.rive-luau;
            }
            {
              name = "luigi-rosso_libhydrogen_rive_0_2";
              path = inputs.rive-libhydrogen;
            }
            {
              name = "dabeaz_ply_3.11";
              path = inputs.rive-ply;
            }
          ];
        };
        ci = pkgs.mkShellNoCC {
          packages = [
            pkgs.python3
            pkgs.gh
          ];
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
              ++ hamioFor pkgs;
              NIBBLE_UI_FORMAT = "json";
              NIBBLE_REQUIRE_HAMIO = if hamioFor pkgs == [ ] then "0" else "1";
            }
            ''
              cp -R ${./scripts} scripts
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
