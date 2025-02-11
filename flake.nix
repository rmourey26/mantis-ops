{
  description = "Bitte for Mantis";

  inputs = {
    bitte.url = "github:input-output-hk/bitte";
    bitte.inputs.bitte-cli.url = "github:input-output-hk/bitte-cli/v0.3.5";
    nixpkgs.follows = "bitte/nixpkgs";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    terranix.follows = "bitte/terranix";
    utils.follows = "bitte/utils";
    ops-lib.url = "github:input-output-hk/ops-lib/zfs-image?dir=zfs";
    morpho-node.url = "github:input-output-hk/ECIP-Checkpointing";
    mantis.url =
      "github:input-output-hk/mantis?rev=d6cada089a10e3d9988e27d695259a216f6e21f8";
    mantis-explorer.url = "github:input-output-hk/mantis-explorer";
    mantis-faucet-web.url = "github:input-output-hk/mantis-faucet-web";
  };

  outputs = { self, nixpkgs, utils, ops-lib, bitte, ... }@inputs:
    bitte.lib.simpleFlake {
      inherit nixpkgs;
      systems = [ "x86_64-linux" ];

      preOverlays = [
        bitte.overlay
      ];

      overlay = import ./overlay.nix inputs;

      packages =
        { generate-mantis-keys
        , mantis-faucet-nginx
        , mantis-explorer-nginx
        , restic-backup
        , mantis-faucet-server
        , checkFmt
        , devShellPath
        }@pkgs: pkgs;

      devShell = { bitteShellCompat, cue }: bitteShellCompat {
        inherit self;
        extraPackages = [ cue ];
        cluster = "mantis-testnet";
        profile = "mantis";
        region = self.clusters."mantis-testnet".proto.config.cluster.region;
        domain = "mantis.ws";
        nixConfig = ''
          extra-substituters = https://hydra.mantis.ist
          extra-trusted-public-keys = hydra.mantis.ist-1:4LTe7Q+5pm8+HawKxvmn2Hx0E3NbkYjtf1oWv+eAmTo=
        '';
      };

      extraOutputs =
        let hashiStack = bitte.lib.mkHashiStack {
          flake = self;
          domain = "mantis.ws";
        };
        in
        {
          inherit (hashiStack) clusters nixosConfigurations consulTemplates;
        } // bitte.lib.mkDeploy { inherit self; };

      hydraJobs =
        { bitte
        , cfssl
        , consul
        , cue
        , devShellPath
        , grafana
        , grafana-loki
        , haproxy
        , nixFlakes
        , nomad
        , sops
        , terraform-with-plugins
        , vault-bin
        , victoriametrics
        , generate-mantis-keys
        , mantis
        , mantis-staging
        , mantis-faucet-web
        , mantis-faucet-nginx
        , mantis-faucet-server
        , mantis-explorer
        , mantis-explorer-nginx
        , morpho-node
        , morpho-node-entrypoint
        }@jobs: jobs // (builtins.mapAttrs (_: v: v.config.system.build.toplevel)
          self.nixosConfigurations);
    };
}
