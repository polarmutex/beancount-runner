{
  description = "Beancount pipeline system with multi-language plugin support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };

        # Zig master version (latest)
        zigpkgs = zig.packages.${system};

        # Python environment with protobuf
        pythonEnv = pkgs.python3.withPackages (ps:
          with ps; [
            protobuf
            setuptools
          ]);
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "beancount-runner";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [
            zigpkgs.master
            pkgs.protobuf
            pkgs.rustc
            pkgs.cargo
            pythonEnv
          ];

          buildPhase = ''
            # Generate protobuf code for all languages
            mkdir -p generated/zig generated/rust generated/python

            # Generate Zig protobuf code (requires protobuf-zig plugin)
            # Note: Will need custom protoc plugin for Zig

            # Generate Rust protobuf code
            protoc --rust_out=generated/rust \
              --proto_path=proto \
              proto/*.proto

            # Generate Python protobuf code
            protoc --python_out=generated/python \
              --proto_path=proto \
              proto/*.proto

            # Build Zig core
            zig build-exe src/main.zig \
              -O ReleaseFast \
              --name beancount-runner

            # Build Rust parser plugin (when ready)
            # cd plugins/parser-lima
            # cargo build --release
            # cd ../..
          '';

          installPhase = ''
            mkdir -p $out/bin $out/lib/plugins $out/share
            cp beancount-runner $out/bin/

            # Install plugins when ready
            # cp plugins/parser-lima/target/release/parser-lima $out/lib/plugins/

            cp -r plugins/auto-balance $out/lib/plugins/
            cp pipeline.toml $out/share/
            cp -r proto $out/share/
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Core toolchains
            zigpkgs.master
            pkgs.protobuf
            pkgs.rustc
            pkgs.cargo
            pythonEnv

            # Language servers for development
            pkgs.zls # Zig language server
            pkgs.rust-analyzer # Rust language server
            pkgs.python3Packages.python-lsp-server

            # Build tools
            pkgs.pkg-config
            pkgs.llvmPackages.bintools

            # Utilities
            pkgs.grpcurl # Testing protobuf
            pkgs.jq # JSON manipulation
            pkgs.protoc-gen-go # Protobuf tooling example
          ];

          shellHook = ''
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "🚀 Beancount Runner Development Environment"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📦 Zig:     $(zig version)"
            echo "🦀 Rust:    $(rustc --version)"
            echo "🐍 Python:  $(python --version)"
            echo "📋 Protoc:  $(protoc --version)"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Available commands:"
            echo "  zig build-exe src/main.zig    # Build core"
            echo "  protoc --python_out=...       # Generate proto code"
            echo "  cargo build                   # Build plugins"
            echo ""

            # Generate protobuf code if needed
            if [ ! -d "generated" ]; then
              echo "📝 Generating protobuf code..."
              mkdir -p generated/{zig,rust,python}

              protoc --rust_out=generated/rust \
                --proto_path=proto \
                proto/*.proto 2>/dev/null || echo "⚠️  Rust proto generation skipped"

              protoc --python_out=generated/python \
                --proto_path=proto \
                proto/*.proto

              echo "✅ Protobuf code generated"
            fi

            export PROTO_PATH="$PWD/proto"
            export GENERATED_PATH="$PWD/generated"
          '';
        };
      }
    );
}
