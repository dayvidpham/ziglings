{
  description = "Minimal Nix flake template to provision a Zig environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig.url = "github:silversquirl/zig-flake/compat";
    zig.inputs.nixpkgs.follows = "nixpkgs";
    zls.url = "github:zigtools/zls";
    zls.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.zig-flake.follows = "zig";
  };

  outputs =
    { nixpkgs
    , nixpkgs-stable
    , nixpkgs-unstable
    , flake-utils
    , zig
    , zls
    , ...
    }@inputs:
    let
      # ----------------------------------------------------------
      # You configure ...
      # ----------------------------------------------------------
      pname = "my-cool-project";
      version = "0.0.1";

      # default channel to source all packages
      nixpkgs-channel = nixpkgs;

      # The core language packages (e.g., zig, zig_0_15)
      # Set to null to use the default zig version from nixpkgs
      zigAttr = null; # stringly-typed
      zigPackage = pkgs:
        if zigAttr != null
        then pkgs.${zigAttr}
        else pkgs.zig_nightly
      ;

      # Vendor hash for buildGoModule (run `nix build` once with
      # lib.fakeHash to get the real hash from the error message)
      vendorHash = null; # null = vendored in repo; otherwise sha256 string

      # Extra CLI tools available in the dev shell
      devTools = pkgs: with pkgs; [
        (zigPackage pkgs)
        zls_nightly
        zig-zlint
      ];


      # POSIX shell hook executed upon devShell entry
      shellHook = ''
        echo "Zig compiler version: $(zig version)"
        echo "zls version: $(zls --version)"
        echo "zlint version: $(zlint --version)"
      '';


      # Native build dependencies (C libraries, system packages)
      nativeBuildDeps = pkgs: with pkgs;
        [ (zigPackage pkgs) ]
        ++ [
          # pkg-config
          # openssl
          # sqlite
        ];

      # Extra check commands run during `nix build` after go test
      customCheckPhase = ''
        # go vet ./...
        # staticcheck ./...
      '';

      # Files to install alongside the binary (relative to src)
      extraPostInstallPhase = ''
        # mkdir -p $out/share/policies
        # cp authz/policies/*.rego $out/share/policies/
      '';

      # ==========================================================
      # IMPLEMENTATION — you shouldn't need to edit below here
      # ==========================================================


      # ----------------------------------------------------------
      # FLows into outputs generator
      # ----------------------------------------------------------
      mkOutputs = nixpkgs-channel:
        flake-utils.lib.eachDefaultSystem (system:
          let
            overlays = [
              (prev: final: {
                zig_nightly = zig.packages.${system}.nightly;
                zls_nightly = zls.packages.${system}.zls;
              })
            ];
            pkgs = import nixpkgs-channel {
              inherit
                system
                overlays
                ;
              config.allowUnfree = true;
            };

            # ----------------------------------------------------------
            # Build
            # ----------------------------------------------------------

            package = pkgs.zigStdenv.mkDerivation {
              inherit pname version;
              src = ./.;
              inherit vendorHash;

              nativeBuildInputs = nativeBuildDeps pkgs;

              checkPhase = ''
                runHook preCheck
                ${customCheckPhase}
                runHook postCheck
              '';

              postInstall = ''
                runHook prePostInstall
                ${extraPostInstallPhase}
                runHook postPostInstall
              '';
            };

            # ----------------------------------------------------------
            # Development Shell
            # ----------------------------------------------------------

            devShell = pkgs.mkShell {
              name = "${pname}-devShell";
              inputsFrom = [ package ];
              packages = (devTools pkgs);

              inherit shellHook;
            };

          in
          {
            packages.default = package;
            packages.${pname} = package;

            devShells.default = devShell;

            # Quick check: nix flake check
            checks.build = package;
          }
        );
    in
    mkOutputs nixpkgs-channel;
}
