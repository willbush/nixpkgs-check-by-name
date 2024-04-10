let
  sources = import ./npins;
in
{
  system ? builtins.currentSystem,
  nixpkgs ? sources.nixpkgs,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config = {};
    overlays = [];
  };
  inherit (pkgs) lib;

  runtimeExprPath = ./src/eval.nix;
  testNixpkgsPath = ./tests/mock-nixpkgs.nix;
  nixpkgsLibPath = nixpkgs + "/lib";

  # Needed to make Nix evaluation work inside nix builds
  initNix = ''
    export TEST_ROOT=$(pwd)/test-tmp
    export NIX_CONF_DIR=$TEST_ROOT/etc
    export NIX_LOCALSTATE_DIR=$TEST_ROOT/var
    export NIX_LOG_DIR=$TEST_ROOT/var/log/nix
    export NIX_STATE_DIR=$TEST_ROOT/var/nix
    export NIX_STORE_DIR=$TEST_ROOT/store

    # Ensure that even if tests run in parallel, we don't get an error
    # We'd run into https://github.com/NixOS/nix/issues/2706 unless the store is initialised first
    nix-store --init
  '';


  results = {
    # We're using this value as the root result. By default, derivations expose all of their
    # internal attributes, which is very messy. We prevent this using lib.lazyDerivation
    build = lib.lazyDerivation {
      derivation = pkgs.callPackage ./package.nix {
        inherit nixpkgsLibPath initNix runtimeExprPath testNixpkgsPath;
      };
    };

    shell = pkgs.mkShell {
      env.NIX_CHECK_BY_NAME_EXPR_PATH = toString runtimeExprPath;
      env.NIX_PATH = "test-nixpkgs=${toString testNixpkgsPath}:test-nixpkgs/lib=${toString nixpkgsLibPath}";
      env.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
      inputsFrom = [ results.build ];
      nativeBuildInputs = with pkgs; [
        npins
        rust-analyzer
      ];
    };

    # Run regularly by CI and turned into a PR
    autoPrUpdate = pkgs.writeShellApplication {
      name = "auto-pr-update";
      runtimeInputs = with pkgs; [
        npins
        cargo
      ];
      text =
        let
          commands = {
            "npins changes" = ''
              npins update --directory "$REPO_ROOT/npins"'';
            "cargo changes" = ''
              cargo update --manifest-path "$REPO_ROOT/Cargo.toml"'';
          };
        in
        ''
          REPO_ROOT=$1
          echo "Run automated updates"
        ''
        + pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList (title: command: ''
          echo -e '<details><summary>${title}</summary>\n\n```'
          ${command} 2>&1
          echo -e '```\n</details>'
        '') commands);
    };

    # Tests the tool on the pinned Nixpkgs tree, this is a good sanity check
    nixpkgsCheck = pkgs.runCommand "test-nixpkgs-check-by-name" {
      nativeBuildInputs = [
        results.build
        pkgs.nix
      ];
      nixpkgsPath = nixpkgs;
    } ''
      ${initNix}
      nixpkgs-check-by-name --base "$nixpkgsPath" "$nixpkgsPath"
      touch $out
    '';
  };

in
results.build // results // {

  # Good for debugging
  inherit pkgs;

  # Built by CI
  ci = pkgs.linkFarm "ci" results;

}
