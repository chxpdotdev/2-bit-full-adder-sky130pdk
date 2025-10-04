{
  description = "2-Bit-Full-Adder PHY project using SkyWater 130nm PDK";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nix-eda.url = "github:fossi-foundation/nix-eda";
    nix-eda.inputs.nixpkgs.follows = "nixpkgs";
    ciel.url = "github:fossi-foundation/ciel";
    ciel.inputs.nix-eda.follows = "nix-eda";
  };

  ## Add these to your Nix config if you want to use caches
  # nixConfig = {
  #   substituters = [
  #     "https://cache.nixos.org/"
  #     "https://nix-cache.fossi-foundation.org"
  #   ];
  #   trusted-public-keys = [
  #     "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  #     "nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs="
  #   ];
  # };

  outputs = {
    self,
    nixpkgs,
    nix-eda,
    ciel,
    ...
  }: let
    systems = ["x86_64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs {inherit system;}));
  in {
    devShells = forAllSystems (
      pkgs: let
        eda = nix-eda.packages.${pkgs.system};
        cielPkg = ciel.packages.${pkgs.system}.default;
        pdkRoot = ".pdk";
      in {
        default = pkgs.mkShell {
          packages = [
            cielPkg
            eda.magic
            eda.netgen
            eda.klayout
            eda.ngspice
            eda.xschem
            eda.yosysFull

            pkgs.gtkwave
            pkgs.xterm
            pkgs.gaw
          ];

          shellHook = ''
            export PDK_ROOT="$PWD/${pdkRoot}"
            export PDK=sky130A
            mkdir -p "$PDK_ROOT"

            # ---- Magic wiring ----
            _ciel_set_magic_vars() {
                MAGIC_TECH=$(find "$PDK_ROOT" -type f -path "*/sky130A/libs.tech/magic/sky130A.tech" | head -n1 || true)
                if [ -n "$MAGIC_TECH" ]; then
                    export MAGIC_TECH
                    export MAGTYPE=mag
                fi
            }

            # --- Build xschem library search path (no custom xschemrc) ---
            _ciel_set_xschem_vars() {
                base="$PDK_ROOT/$PDK/libs.tech/xschem"
                libs=""

                add_path() {
                    if [ -d "$1" ]; then
                        if [ -z "$libs" ]; then libs="$1"; else libs="$libs:$1"; fi
                    fi
                }

                add_path "$base"
                add_path "$base/sky130_fd_pr"
                add_path "$base/sky130_fd_sc_hd"
                add_path "$base/sky130_fd_sc_hs"
                add_path "$base/sky130_fd_sc_hdll"
                add_path "$base/sky130_fd_sc_lp"
                add_path "$base/sky130_fd_io"

                # Optional user symbols
                if [ -d "$HOME/xschem" ]; then
                    if [ -z "$libs" ]; then libs="$HOME/xschem"; else libs="$libs:$HOME/xschem"; fi
                fi

                if [ -n "$libs" ]; then
                    export XSCHEM_LIBRARY_PATH="$libs"
                    export XSCHEM_SYMBOLS="$libs"
                fi
            }

            # --- Fetch/activate a specific open_pdks build into ./.pdk ---
            ciel-use() {
                if [ -z "$1" ]; then
                    echo "usage: ciel-use <open_pdks_commit_hash>" 1>&2
                    echo "hint:   ciel ls-remote --pdk-family sky130" 1>&2
                    return 2
                fi
                mkdir -p "$PDK_ROOT"
                ciel enable --pdk-family sky130 "$1" --pdk-root "$PDK_ROOT"
                _ciel_set_magic_vars
                _ciel_set_xschem_vars
            }

            _ciel_set_magic_vars
            _ciel_set_xschem_vars

            # --- Convenience wrappers ---
            magic() {
                if [ -z "$MAGIC_TECH" ]; then
                    echo "MAGIC_TECH not set. Run: ciel-use <open_pdks_hash>" 1>&2
                    return 1
                fi
                command magic -T "$MAGIC_TECH" "$@"
            }

            # Wrapper: keep system rc (stock libs), then append PDK libs from env
            xschem() {
              if [ -n "$XSCHEM_LIBRARY_PATH" ] || [ -n "$XSCHEM_SYMBOLS" ]; then
                command xschem --tcl 'if {[info exists ::env(XSCHEM_LIBRARY_PATH)] && $::env(XSCHEM_LIBRARY_PATH) ne ""} {
                    # Append env-provided PDK paths to whatever the system rc already set
                    if {[info exists XSCHEM_LIBRARY_PATH] && $XSCHEM_LIBRARY_PATH ne ""} {
                      set XSCHEM_LIBRARY_PATH "$XSCHEM_LIBRARY_PATH:$::env(XSCHEM_LIBRARY_PATH)"
                    } else {
                      set XSCHEM_LIBRARY_PATH $::env(XSCHEM_LIBRARY_PATH)
                    }
                    # Keep env in sync (some flows read from ::env)
                    set ::env(XSCHEM_LIBRARY_PATH) $XSCHEM_LIBRARY_PATH
                  }
                  if {[info exists ::env(XSCHEM_SYMBOLS)] && $::env(XSCHEM_SYMBOLS) ne ""} {
                    if {[info exists XSCHEM_SYMBOLS] && $XSCHEM_SYMBOLS ne ""} {
                      set XSCHEM_SYMBOLS "$XSCHEM_SYMBOLS:$::env(XSCHEM_SYMBOLS)"
                    } else {
                      set XSCHEM_SYMBOLS $::env(XSCHEM_SYMBOLS)
                    }
                    set ::env(XSCHEM_SYMBOLS) $XSCHEM_SYMBOLS
                  }' "$@"
              else
                command xschem "$@"
              fi
            }

            echo
            echo "🔧 SKY130 dev shell"
            echo "  PDK_ROOT: $PDK_ROOT"
            if [ -n "$MAGIC_TECH" ]; then echo "  MAGIC_TECH: $MAGIC_TECH"; else echo "  MAGIC_TECH: <not set>"; fi
            if [ -n "$XSCHEM_LIBRARY_PATH" ]; then
              echo "  XSCHEM_LIBRARY_PATH:"
              printf '    - %s\n' $(echo "$XSCHEM_LIBRARY_PATH" | tr ':' ' ')
            else
              echo "  XSCHEM_LIBRARY_PATH: <empty>"
            fi
            echo
            echo "Try:"
            echo "  ciel ls-remote --pdk-family sky130"
            echo "  ciel-use <open_pdks_commit_hash>"
            echo "  magic"
            echo "  xschem"
            echo
          '';
        };
      }
    );
  };
}
