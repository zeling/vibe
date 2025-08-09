{
  description = "A Zig project to render text to framebuffer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zig-pkgs = pkgs.zig.pkgs;
      in
      {
        devShell = pkgs.mkShell {
          packages = with pkgs; [
            zig
            git
          ];
          # Add any environment variables or shell hooks here if needed
        };

        packages.framebuffer = pkgs.stdenv.mkDerivation {
          pname = "framebuffer";
          version = "0.1.0";
          src = self;

          nativeBuildInputs = [ pkgs.zig ];

          buildPhase = ''
            zig build -Drelease-small
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/framebuffer $out/bin/framebuffer
          '';
        };

        dockerImage = pkgs.dockerTools.buildImage {
          name = "framebuffer-renderer";
          tag = "latest";
          from = pkgs.dockerTools.pullImage {
            imageName = "scratch";
            imageDigest = "sha256:5c11a6303a648f549f065475560057906800740482a50c72772929419a007101"; # scratch image digest
          };
          contents = [
            self.packages.${system}.framebuffer
          ];
          config = {
            Entrypoint = [ "/bin/framebuffer" ];
            Cmd = [ ];
          };
        };
      }
    );
}
