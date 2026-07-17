{
  description = "Soloquy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    gradle2nix = {
      url = "github:tadfisher/gradle2nix/v2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, gradle2nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        graalvm = pkgs.graalvmPackages.graalvm-oracle_25 // {
          # gradle2nix expects a .home attribute on the JDK
          home = graalvm;
        };

        gradleWithJdk = pkgs.gradle_9.override {
          java = graalvm;
          javaToolchains = [ graalvm ];
        };

        backendName = "soloquybackend";
        backendVersion = "0.0.1-SNAPSHOT";

        backendNative = gradle2nix.builders.${system}.buildGradlePackage {
          pname = backendName;
          version = backendVersion;
          src = ./soloquybackend;
          lockFile = ./soloquybackend/gradle.lock;
          gradle = gradleWithJdk;
          buildJdk = graalvm;
          GRAALVM_HOME = graalvm;
          nativeBuildInputs = with pkgs; [
            graalvm
          ];
          gradleBuildFlags = [ "--no-daemon" "nativeCompile" ];
          installPhase = ''
            mkdir -p $out/bin
            cp build/native/nativeCompile/${backendName} $out/bin/
          '';
        };

        backend = pkgs.dockerTools.buildImage {
          name = backendName;
          tag = "latest";
          created = "1970-01-01T00:00:01Z";

          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ backendNative ];
            pathsToLink = [ "/bin" ];
          };

          extraCommands = ''
              mkdir -m 1777 tmp
          '';

          config = {
            Cmd = [ "/bin/${backendName}" ];
            ExposedPorts = { "8080/tcp" = {}; };
          };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          shellHook = ''
            export GRAALVM_HOME=${graalvm}
          '';
          packages = (with pkgs; [
            docker
            nodejs_24
            oci-cli
            pnpm_10
            terraform
          ]) ++ [ graalvm ];
        };

        packages.backend = backend;
      });
}
