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

        jdk = pkgs.jdk25;

        gradleWithJdk = pkgs.gradle_9.override {
          java = jdk;
          javaToolchains = [ jdk ];
        };

        backendName = "soloquybackend";
        backendVersion = "0.0.1-SNAPSHOT";

        backendJar = gradle2nix.builders.${system}.buildGradlePackage {
          pname = backendName;
          version = backendVersion;
          src = ./soloquybackend;
          lockFile = ./soloquybackend/gradle.lock;
          gradle = gradleWithJdk;
          buildJdk = jdk;
          nativeBuildInputs = [ jdk ];
          gradleBuildFlags = [ "--no-daemon" "build" "-x" "test" ];
          installPhase = ''
            mkdir -p $out/lib
            cp build/libs/${backendName}-${backendVersion}.jar $out/lib/
          '';
        };

        backend = pkgs.dockerTools.buildImage {
          name = backendName;
          tag = "latest";
          created = "1970-01-01T00:00:01Z";

          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ jdk backendJar ];
            pathsToLink = [ "/bin" "/lib" ];
          };

          extraCommands = ''
              mkdir -m 1777 tmp
          '';

          config = {
            Cmd = [ "/bin/java" "-jar" "/lib/${backendName}-${backendVersion}.jar" ];
            ExposedPorts = { "8080/tcp" = {}; };
          };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = (with pkgs; [
            docker
            nodejs_24
            pnpm_10
            terraform
          ]) ++ [ jdk ];
        };

        packages.backend = backend;
      });
}
