{
  description = "actions-batch - run batch jobs on GitHub Actions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      version = self.shortRev or self.dirtyShortRev or "dev";
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.buildGoModule {
            pname = "actions-batch";
            inherit version;
            src = ./.;
            vendorHash = "sha256-MlkEWbyJk8AHEeA9OoekMz5p6X3wqmrl6aX5R+QKFHM=";
            ldflags = [
              "-s"
              "-w"
              "-X github.com/alexellis/actions-batch/pkg.Version=${version}"
              "-X github.com/alexellis/actions-batch/pkg.GitCommit=${self.rev or "dirty"}"
            ];
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go
              gopls
              gotools
            ];
          };
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/actions-batch";
        };
      });
    };
}
