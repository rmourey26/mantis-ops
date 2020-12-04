{ mkNomadJob, lib, mantis, mantis-source, mantis-faucet, mantis-faucet-source, morpho-node
, morpho-source, dockerImages, mantis-explorer }:
let
  # NOTE: Copy this file and change the next line if you want to start your own cluster!
  namespace = "mantis-testnet";

  vault = {
    policies = [ "nomad-cluster" ];
    changeMode = "noop";
  };

  genesisJson = {
    data = ''
      {{- with secret "kv/nomad-cluster/${namespace}/genesis" -}}
      {{.Data.data | toJSON }}
      {{- end -}}
    '';
    changeMode = "restart";
    destination = "local/genesis.json";
  };

  amountOfMorphoNodes = 5;

  morphoNodes = lib.forEach (lib.range 1 amountOfMorphoNodes) (n: {
    name = "obft-node-${toString n}";
    nodeNumber = n;
  });

  mkMorpho = { name, nodeNumber, nbNodes }: {
    services = {
      "${namespace}-morpho-node" = {
        addressMode = "host";
        portLabel = "morpho";

        tags = [ "morpho" namespace name morpho-source.rev ];
        meta = {
          inherit name;
          nodeNumber = builtins.toString nodeNumber;
        };
      };
    };

    networks = [{
      ports = {
        metrics.to = 7000;
        rpc.to = 8000;
        server.to = 9000;
        morpho.to = 3000;
        morphoPrometheus.to = 6000;
      };
    }];

    tasks.${name} = {
      inherit name vault;
      driver = "docker";
      env = { REQUIRED_PEER_COUNT = builtins.toString nbNodes; };
      # TODO manveru: port mapping??

      templates = [
        {
          data = ''
            ApplicationName: morpho-checkpoint
            ApplicationVersion: 1
            CheckpointInterval: 4
            FedPubKeys:
            {{- range service "${namespace}-morpho-node" -}}
            {{- with secret (printf "kv/data/nomad-cluster/${namespace}/%s/obft-public-key" .ServiceMeta.Name) }}
                - {{ .Data.data.value -}}
                {{- end -}}
            {{- end }}
            LastKnownBlockVersion-Major: 0
            LastKnownBlockVersion-Minor: 2
            LastKnownBlockVersion-Alt: 0
            NetworkMagic: 12345
            NodeId: {{ index (split "-" "${name}") 2 }}
            NodePrivKeyFile: {{ env "NOMAD_SECRETS_DIR" }}/morpho-private-key
            NumCoreNodes: {{ len (service "${namespace}-morpho-node") }}
            PoWBlockFetchInterval: 5000000
            PoWNodeRpcUrl: http://{{ env "NOMAD_ADDR_rpc" }}
            PrometheusPort: {{ env "NOMAD_PORT_morphoPrometheus" }}
            Protocol: MockedBFT
            RequiredMajority: {{ len (service "${namespace}-morpho-node") | divide 2 | add 1 }}
            RequiresNetworkMagic: RequiresMagic
            SecurityParam: 5
            SlotDuration: 5
            SnapshotsOnDisk: 60
            SnapshotInterval: 60
            SystemStart: "2020-11-17T00:00:00Z"
            TurnOnLogMetrics: True
            TurnOnLogging: True
            ViewMode: SimpleView
            minSeverity: Debug
            TracingVerbosity: NormalVerbosity
            setupScribes:
              - scKind: StdoutSK
                scFormat: ScText
                scName: stdout
            defaultScribes:
              - - StdoutSK
                - stdout
            setupBackends:
              - KatipBK
            defaultBackends:
              - KatipBK
            options:
              mapBackends:
          '';
          destination = "local/morpho-config.yaml";
        }
        {
          data = ''
            {{- with secret "kv/data/nomad-cluster/${namespace}/${name}/obft-secret-key" -}}
            {{- .Data.data.value -}}
            {{- end -}}
          '';
          destination = "secrets/morpho-private-key";
        }
        {
          data = ''
            [
              {{- range $index1, $service1 := service "${namespace}-morpho-node" -}}
              {{ if ne $index1 0 }},{{ end }}
                {
                  "nodeAddress": {
                  "addr": "{{ .Address }}",
                  "port": {{ .Port }},
                  "valency": 1
                  },
                  "nodeId": {{- index (split "-" .ServiceMeta.Name) 2 -}},
                  "producers": [
                  {{- range $index2, $service2 := service "${namespace}-morpho-node" -}}
                  {{ if ne $index2 0 }},{{ end }}
                    {
                        "addr": "{{ .Address }}",
                        "port": {{ .Port }},
                        "valency": 1
                    }
                  {{- end -}}
                  ]}
              {{- end }}
              ]
          '';
          destination = "local/morpho-topology.json";
          changeMode = "noop";
        }
      ];

      config = {
        image = dockerImages.morpho.id;
        args = [ ];
        labels = [{
          inherit namespace name;
          imageTag = dockerImages.morpho.image.imageTag;
        }];

        logging = {
          type = "journald";
          config = [{
            tag = name;
            labels = "name,namespace,imageTag";
          }];
        };
      };

      restartPolicy = {
        interval = "30m";
        attempts = 10;
        delay = "1m";
        mode = "delay";
      };
    };

    tasks.telegraf = {
      driver = "docker";

      inherit vault;

      resources = {
        cpu = 100; # mhz
        memoryMB = 128;
      };

      config = {
        image = dockerImages.telegraf.id;
        args = [ "-config" "local/telegraf.config" ];

        labels = [{
          inherit namespace name;
          imageTag = dockerImages.telegraf.image.imageTag;
        }];

        logging = {
          type = "journald";
          config = [{
            tag = "${name}-telegraf";
            labels = "name,namespace,imageTag";
          }];
        };
      };

      templates = [{
        data = ''
          [agent]
          flush_interval = "10s"
          interval = "10s"
          omit_hostname = false

          [global_tags]
          client_id = "${name}"
          namespace = "${namespace}"

          [inputs.prometheus]
          metric_version = 1

          urls = [ "http://{{ env "NOMAD_ADDR_morphoPrometheus" }}" ]

          [outputs.influxdb]
          database = "telegraf"
          urls = ["http://{{with node "monitoring" }}{{ .Node.Address }}{{ end }}:8428"]
        '';

        destination = "local/telegraf.config";
      }];
    };
  };

  mkMantis = { name, resources, count ? 1, templates, serviceName, tags ? [ ]
    , meta ? { }, requiredPeerCount, services ? { } }: {
      inherit count;

      networks = [{
        ports = {
          metrics.to = 7000;
          rpc.to = 8000;
          server.to = 9000;
        };
      }];

      ephemeralDisk = {
        sizeMB = 10 * 1000;
        migrate = true;
        sticky = true;
      };

      reschedulePolicy = {
        attempts = 0;
        unlimited = true;
      };

      tasks.telegraf = {
        driver = "docker";

        inherit vault;

        resources = {
          cpu = 100; # mhz
          memoryMB = 128;
        };

        config = {
          image = dockerImages.telegraf.id;
          args = [ "-config" "local/telegraf.config" ];

          labels = [{
            inherit namespace name;
            imageTag = dockerImages.telegraf.image.imageTag;
          }];

          logging = {
            type = "journald";
            config = [{
              tag = "${name}-telegraf";
              labels = "name,namespace,imageTag";
            }];
          };
        };

        templates = [{
          data = ''
            [agent]
            flush_interval = "10s"
            interval = "10s"
            omit_hostname = false

            [global_tags]
            client_id = "${name}"
            namespace = "${namespace}"

            [inputs.prometheus]
            metric_version = 1

            urls = [ "http://{{ env "NOMAD_ADDR_metrics" }}" ]

            [outputs.influxdb]
            database = "telegraf"
            urls = ["http://{{with node "monitoring" }}{{ .Node.Address }}{{ end }}:8428"]
          '';

          destination = "local/telegraf.config";
        }];
      };

      services = lib.recursiveUpdate {
        "${serviceName}-prometheus" = {
          addressMode = "host";
          portLabel = "metrics";
          tags = [ "prometheus" namespace serviceName name mantis-source.rev ];
        };

        "${serviceName}-rpc" = {
          addressMode = "host";
          portLabel = "rpc";
          tags = [ "rpc" namespace serviceName name mantis-source.rev ];
        };

        ${serviceName} = {
          addressMode = "host";
          portLabel = "server";

          tags = [ "server" namespace serviceName mantis-source.rev ] ++ tags;

          meta = {
            inherit name;
            publicIp = "\${attr.unique.platform.aws.public-ipv4}";
          } // meta;

          checks = [{
            type = "http";
            path = "/healthcheck";
            portLabel = "rpc";

            checkRestart = {
              limit = 5;
              grace = "300s";
              ignoreWarnings = false;
            };
          }];
        };
      } services;

      tasks.${name} = {
        inherit name resources templates;
        driver = "docker";
        inherit vault;

        config = {
          image = dockerImages.mantis.id;
          args = [ "-Dconfig.file=running.conf" ];
          ports = [ "rpc" "server" "metrics" ];
          labels = [{
            inherit namespace name;
            imageTag = dockerImages.mantis.image.imageTag;
          }];

          logging = {
            type = "journald";
            config = [{
              tag = name;
              labels = "name,namespace,imageTag";
            }];
          };
        };

        restartPolicy = {
          interval = "30m";
          attempts = 10;
          delay = "1m";
          mode = "fail";
        };

        env = { REQUIRED_PEER_COUNT = toString requiredPeerCount; };
      };
    };

  mkMiner = { name, publicPort, requiredPeerCount ? 0, instanceId ? null }:
    lib.nameValuePair name (mkMantis {
      resources = {
        # For c5.2xlarge in clusters/mantis/testnet/default.nix, the url ref below
        # provides 3.4 GHz * 8 vCPU = 27.2 GHz max.
        # Mantis mainly uses only one core.
        # Allocating by vCPU or core quantity not yet available.
        # Ref: https://github.com/hashicorp/nomad/blob/master/client/fingerprint/env_aws.go
        cpu = 3400;
        memoryMB = 5 * 1024;
      };

      inherit name requiredPeerCount;
      templates = [
        {
          data = ''
            include "${mantis}/conf/testnet-internal-nomad.conf"

            logging.json-output = true
            logging.logs-file = "logs"

            mantis.blockchains.testnet-internal-nomad.bootstrap-nodes = [
              {{ range service "${namespace}-mantis-miner" -}}
                "enode://  {{- with secret (printf "kv/data/nomad-cluster/${namespace}/%s/enode-hash" .ServiceMeta.Name) -}}
                  {{- .Data.data.value -}}
                  {{- end -}}@{{ .Address }}:{{ .Port }}",
              {{ end -}}
            ]

            mantis.blockchains.testnet-internal-nomad.checkpoint-public-keys = [
              ${lib.concatMapStringsSep "," (x: ''
                {{- with secret "kv/data/nomad-cluster/${namespace}/obft-node-${toString x}/obft-public-key" -}}"{{- .Data.data.value -}}"{{end}}
              '') (lib.range 1 5)}
            ]

            mantis.consensus.mining-enabled = true
            mantis.client-id = "${name}"
            mantis.consensus.coinbase = "{{ with secret "kv/data/nomad-cluster/${namespace}/${name}/coinbase" }}{{ .Data.data.value }}{{ end }}"
            mantis.node-key-file = "{{ env "NOMAD_SECRETS_DIR" }}/secret-key"
            mantis.datadir = "/local/mantis"
            mantis.ethash.ethash-dir = "/local/ethash"
            mantis.metrics.enabled = true
            mantis.metrics.port = {{ env "NOMAD_PORT_metrics" }}
            mantis.network.rpc.http.interface = "0.0.0.0"
            mantis.network.rpc.http.port = {{ env "NOMAD_PORT_rpc" }}
            mantis.network.server-address.port = {{ env "NOMAD_PORT_server" }}
            mantis.blockchains.testnet-internal-nomad.custom-genesis-file = "{{ env "NOMAD_TASK_DIR" }}/genesis.json"

            mantis.blockchains.testnet-internal-nomad.ecip1098-block-number = 0
            mantis.blockchains.testnet-internal-nomad.ecip1097-block-number = 0
          '';
          destination = "local/mantis.conf";
          changeMode = "noop";
        }
        {
          data = let
            secret = key:
              ''{{ with secret "${key}" }}{{.Data.data.value}}{{end}}'';
          in ''
            ${secret "kv/data/nomad-cluster/${namespace}/${name}/secret-key"}
            ${secret "kv/data/nomad-cluster/${namespace}/${name}/enode-hash"}
          '';
          destination = "secrets/secret-key";
        }
        genesisJson
      ];

      serviceName = "${namespace}-mantis-miner";

      tags = [ "ingress" namespace name ];

      meta = {
        ingressHost = "${name}.mantis.ws";
        ingressPort = toString publicPort;
        ingressBind = "*:${toString publicPort}";
        ingressMode = "tcp";
        ingressServer = "_${namespace}-mantis-miner._${name}.service.consul";
      };
    });

  mkPassive = count:
    let name = "${namespace}-mantis-passive";
    in mkMantis {
      inherit name;
      serviceName = name;
      resources = {
        # For c5.2xlarge in clusters/mantis/testnet/default.nix, the url ref below
        # provides 3.4 GHz * 8 vCPU = 27.2 GHz max.  80% is 21760 MHz.
        # Allocating by vCPU or core quantity not yet available.
        # Ref: https://github.com/hashicorp/nomad/blob/master/client/fingerprint/env_aws.go
        cpu = 500;
        memoryMB = 5 * 1024;
      };

      tags = [ namespace "passive" ];

      inherit count;

      requiredPeerCount = builtins.length miners;

      services."${name}-rpc" = {
        addressMode = "host";
        tags = [ "rpc" namespace name mantis-source.rev ];
        portLabel = "rpc";
      };

      templates = [
        {
          data = ''
            include "${mantis}/conf/testnet-internal-nomad.conf"

            logging.json-output = true
            logging.logs-file = "logs"

            mantis.blockchains.testnet-internal-nomad.bootstrap-nodes = [
              {{ range service "${namespace}-mantis-miner" -}}
                "enode://  {{- with secret (printf "kv/data/nomad-cluster/${namespace}/%s/enode-hash" .ServiceMeta.Name) -}}
                  {{- .Data.data.value -}}
                  {{- end -}}@{{ .Address }}:{{ .Port }}",
              {{ end -}}
            ]

            mantis.blockchains.testnet-internal-nomad.checkpoint-public-keys = [
              ${lib.concatMapStringsSep "," (x: ''
                {{- with secret "kv/data/nomad-cluster/${namespace}/obft-node-${toString x}/obft-public-key" -}}"{{- .Data.data.value -}}"{{end}}
              '') (lib.range 1 5)}
            ]

            mantis.client-id = "${name}"
            mantis.consensus.mining-enabled = false
            mantis.datadir = "/local/mantis"
            mantis.ethash.ethash-dir = "/local/ethash"
            mantis.metrics.enabled = true
            mantis.metrics.port = {{ env "NOMAD_PORT_metrics" }}
            mantis.network.rpc.http.interface = "0.0.0.0"
            mantis.network.rpc.http.port = {{ env "NOMAD_PORT_rpc" }}
            mantis.network.server-address.port = {{ env "NOMAD_PORT_server" }}
            mantis.blockchains.testnet-internal-nomad.custom-genesis-file = "{{ env "NOMAD_TASK_DIR" }}/genesis.json"

            mantis.blockchains.testnet-internal-nomad.ecip1098-block-number = 0
            mantis.blockchains.testnet-internal-nomad.ecip1097-block-number = 0
          '';
          changeMode = "noop";
          destination = "local/mantis.conf";
        }
        genesisJson
      ];
    };

  amountOfMiners = 5;

  miners = lib.forEach (lib.range 1 amountOfMiners) (num: {
    name = "mantis-${toString num}";
    requiredPeerCount = num - 1;
    publicPort = 9000 + num; # routed through haproxy/ingress
  });

  explorer = let name = "${namespace}-explorer";
  in {
    services."${name}" = {
      addressMode = "host";
      portLabel = "explorer";

      tags = [ "ingress" namespace "explorer" name ];

      meta = {
        inherit name;
        publicIp = "\${attr.unique.platform.aws.public-ipv4}";
        ingressHost = "${name}.mantis.ws";
        ingressMode = "http";
        ingressBind = "*:443";
        ingressServer = "_${name}._tcp.service.consul";
        ingressBackendExtra = ''
          http-response set-header X-Server %s
        '';
      };

      checks = [{
        type = "http";
        path = "/";
        portLabel = "explorer";

        checkRestart = {
          limit = 5;
          grace = "300s";
          ignoreWarnings = false;
        };
      }];
    };

    networks = [{ ports = { explorer.to = 8080; }; }];

    tasks.explorer = {
      inherit name;
      driver = "docker";

      resources = {
        cpu = 100; # mhz
        memoryMB = 128;
      };

      config = {
        image = dockerImages.mantis-explorer-server.id;
        args = [ "nginx" "-c" "/local/nginx.conf" ];
        ports = [ "explorer" ];
        labels = [{
          inherit namespace name;
          imageTag = dockerImages.mantis-explorer-server.image.imageTag;
        }];

        logging = {
          type = "journald";
          config = [{
            tag = name;
            labels = "name,namespace,imageTag";
          }];
        };
      };

      templates = [{
        data = ''
          user nginx nginx;
          error_log /dev/stderr info;
          pid /dev/null;
          events {}
          daemon off;

          http {
            access_log /dev/stdout;

            upstream backend {
              least_conn;
              {{ range service "mantis-1.${namespace}-mantis-miner-rpc" }}
                server {{ .Address }}:{{ .Port }};
              {{ end }}
            }

            server {
              listen 8080;

              location / {
                root /mantis-explorer;
                index index.html;
                try_files $uri $uri/ /index.html;
              }

              location /rpc/node {
                proxy_pass http://backend/;
              }

              location /sockjs-node {
                proxy_pass http://backend/;
              }
            }
          }
        '';
        changeMode = "restart";
        destination = "local/nginx.conf";
      }];
    };
  };

  faucetName = "${namespace}-mantis-faucet";
  faucet = {
    networks = [{
      ports = {
        metrics.to = 7000;
        rpc.to = 8000;
        faucet-web.to = 8080;
      };
    }];

    services = {
      "${faucetName}" = {
        addressMode = "host";
        portLabel = "rpc";
        task = "faucet";

        tags =
          [ "ingress" namespace "faucet" faucetName mantis-faucet-source.rev ];

        meta = {
          name = faucetName;
          publicIp = "\${attr.unique.platform.aws.public-ipv4}";
          ingressHost = "${faucetName}.mantis.ws";
          ingressBind = "*:443";
          ingressMode = "http";
          ingressServer = "_${faucetName}._tcp.service.consul";
        };

        # FIXME: this always returns FaucetUnavailable
        # checks = [{
        #   taskName = "faucet";
        #   type = "script";
        #   name = "faucet_health";
        #   command = "healthcheck";
        #   interval = "60s";
        #   timeout = "5s";
        #   portLabel = "rpc";

        #   checkRestart = {
        #     limit = 5;
        #     grace = "300s";
        #     ignoreWarnings = false;
        #   };
        # }];
      };

      "${faucetName}-prometheus" = {
        addressMode = "host";
        portLabel = "metrics";
        tags = [
          "prometheus"
          namespace
          "faucet"
          faucetName
          mantis-faucet-source.rev
        ];
      };

      "${faucetName}-web" = {
        addressMode = "host";
        portLabel = "faucet-web";
        tags = [
          "ingress" namespace "faucet" faucetName mantis-faucet-source.rev
        ];
        meta = {
          name = faucetName;
          publicIp = "\${attr.unique.platform.aws.public-ipv4}";
          ingressHost = "${faucetName}-web.mantis.ws";
          ingressBind = "*:443";
          ingressMode = "http";
          ingressServer = "_${faucetName}-web._tcp.service.consul";
        };
      };
    };

    tasks.faucet = {
      name = "faucet";
      driver = "docker";

      inherit vault;

      resources = {
        cpu = 100;
        memoryMB = 1024;
      };

      config = {
        image = dockerImages.mantis-faucet.id;
        args = [ "-Dconfig.file=running.conf" ];
        ports = [ "rpc" "metrics" ];
        labels = [{
          inherit namespace;
          name = "faucet";
          imageTag = dockerImages.mantis-faucet.image.imageTag;
        }];

        logging = {
          type = "journald";
          config = [{
            tag = "faucet";
            labels = "name,namespace,imageTag";
          }];
        };
      };

      templates = let
        secret = key: ''{{ with secret "${key}" }}{{.Data.data.value}}{{end}}'';
      in [
        {
          data = ''
            faucet {
              # Base directory where all the data used by the faucet is stored
              datadir = "/local/mantis-faucet"

              # Wallet address used to send transactions from
              wallet-address =
                {{- with secret "kv/nomad-cluster/${namespace}/mantis-1/coinbase" -}}
                  "{{.Data.data.value}}"
                {{- end }}

              # Password to unlock faucet wallet
              wallet-password = ""

              # Path to directory where wallet key is stored
              keystore-dir = {{ env "NOMAD_SECRETS_DIR" }}/keystore

              # Transaction gas price
              tx-gas-price = 20000000000

              # Transaction gas limit
              tx-gas-limit = 90000

              # Transaction value
              tx-value = 1000000000000000000

              rpc-client {
                # Address of Ethereum node used to send the transaction
                rpc-address = {{- range service "mantis-1.${namespace}-mantis-miner-rpc" -}}
                    "http://{{ .Address }}:{{ .Port }}"
                  {{- end }}

                # certificate of Ethereum node used to send the transaction when use HTTP(S)
                certificate = null
                #certificate {
                # Path to the keystore storing the certificates (used only for https)
                # null value indicates HTTPS is not being used
                #  keystore-path = "tls/mantisCA.p12"

                # Type of certificate keystore being used
                # null value indicates HTTPS is not being used
                #  keystore-type = "pkcs12"

                # File with the password used for accessing the certificate keystore (used only for https)
                # null value indicates HTTPS is not being used
                #  password-file = "tls/password"
                #}

                # Response time-out from rpc client resolve
                timeout = 3.seconds
              }

              # How often can a single IP address send a request
              min-request-interval = 1.minute

              # Response time-out to get handler actor
              handler-timeout = 1.seconds

              # Response time-out from actor resolve
              actor-communication-margin = 1.seconds

              # Supervisor with BackoffSupervisor pattern
              supervisor {
                min-backoff = 3.seconds
                max-backoff = 30.seconds
                random-factor = 0.2
                auto-reset = 10.seconds
                attempts = 4
                delay = 0.1
              }

              # timeout for shutting down the ActorSystem
              shutdown-timeout = 15.seconds
            }

            logging {
              # Flag used to switch logs to the JSON format
              json-output = true

              # Logs directory
              #logs-dir = /local/mantis-faucet/logs

              # Logs filename
              logs-file = "logs"
            }

            mantis {
              network {
                rpc {
                  http {
                    # JSON-RPC mode
                    # Available modes are: http, https
                    # Choosing https requires creating a certificate and setting up 'certificate-keystore-path' and
                    # 'certificate-password-file'
                    # See: https://github.com/input-output-hk/mantis/wiki/Creating-self-signed-certificate-for-using-JSON-RPC-with-HTTPS
                    mode = "http"

                    # Whether to enable JSON-RPC HTTP(S) endpoint
                    enabled = true

                    # Listening address of JSON-RPC HTTP(S) endpoint
                    interface = "0.0.0.0"

                    # Listening port of JSON-RPC HTTP(S) endpoint
                    port = {{ env "NOMAD_PORT_rpc" }}

                    certificate = null
                    #certificate {
                    # Path to the keystore storing the certificates (used only for https)
                    # null value indicates HTTPS is not being used
                    #  keystore-path = "tls/mantisCA.p12"

                    # Type of certificate keystore being used
                    # null value indicates HTTPS is not being used
                    #  keystore-type = "pkcs12"

                    # File with the password used for accessing the certificate keystore (used only for https)
                    # null value indicates HTTPS is not being used
                    #  password-file = "tls/password"
                    #}

                    # Domains allowed to query RPC endpoint. Use "*" to enable requests from
                    # any domain.
                    cors-allowed-origins = "*"

                    # Rate Limit for JSON-RPC requests
                    # Limits the amount of request the same ip can perform in a given amount of time
                    rate-limit {
                      # If enabled, restrictions are applied
                      enabled = true

                      # Time that should pass between requests
                      min-request-interval = 10.seconds

                      # Size of stored timestamps for requests made from each ip
                      latest-timestamp-cache-size = 1024
                    }
                  }

                  ipc {
                    # Whether to enable JSON-RPC over IPC
                    enabled = false

                    # Path to IPC socket file
                    socket-file = "/local/mantis-faucet/faucet.ipc"
                  }

                  # Enabled JSON-RPC APIs over the JSON-RPC endpoint
                  apis = "faucet"
                }
              }
            }
          '';
          changeMode = "restart";
          destination = "local/faucet.conf";
        }
        {
          data = ''
            {{- with secret "kv/data/nomad-cluster/${namespace}/mantis-1/account" -}}
            {{.Data.data | toJSON }}
            {{- end -}}
          '';
          destination = "secrets/account";
        }
        {
          data = ''
            COINBASE={{- with secret "kv/data/nomad-cluster/${namespace}/mantis-1/coinbase" -}}{{ .Data.data.value }}{{- end -}}
          '';
          destination = "secrets/env";
          env = true;
        }
        genesisJson
      ];
    };

    tasks.faucet-web = {
      name = "faucet-web";
      driver = "docker";
      resources = {
        cpu = 100;
        memoryMB = 128;
      };
      config = {
        image = dockerImages.mantis-faucet-web.id;
        args = [ "nginx" "-c" "/local/nginx.conf" ];
        ports = [ "faucet-web" ];
        labels = [{
          inherit namespace;
          name = "faucet-web";
          imageTag = dockerImages.mantis-faucet-web.image.imageTag;
        }];

        logging = {
          type = "journald";
          config = [{
            tag = "faucet-web";
            labels = "name,namespace,imageTag";
          }];
        };
      };
      templates = [{
        data = ''
          user nginx nginx;
          error_log /dev/stdout info;
          pid /dev/null;
          events {}
          daemon off;

          http {
            access_log /dev/stdout;

            types {
              text/css         css;
              text/javascript  js;
              text/html        html htm;
            }

            server {
              listen 8080;

              location / {
                root /mantis-faucet-web;
                index index.html;
                try_files $uri $uri/ /index.html;
              }

              {{ range service "${namespace}-mantis-faucet" -}}
              # https://github.com/input-output-hk/mantis-faucet-web/blob/nix-build/flake.nix#L14
              # TODO: the above FAUCET_NODE_URL should point to this
              location /rpc/node {
                proxy_pass  "http://{{ .Address }}:{{ .Port }}";
              }
              {{- end }}
            }
          }
        '';
        changeMode = "noop"; # TODO, make it signal when the above proxy_pass is used
        changeSignal = "SIGHUP";
        destination = "local/nginx.conf";
      }];
    };

    tasks.telegraf = {
      driver = "docker";

      inherit vault;

      resources = {
        cpu = 100; # mhz
        memoryMB = 128;
      };

      config = {
        image = dockerImages.telegraf.id;
        args = [ "-config" "local/telegraf.config" ];

        labels = [{
          inherit namespace;
          name = "faucet";
          imageTag = dockerImages.telegraf.image.imageTag;
        }];

        logging = {
          type = "journald";
          config = [{
            tag = "faucet-telegraf";
            labels = "name,namespace,imageTag";
          }];
        };
      };

      templates = [{
        data = ''
          [agent]
          flush_interval = "10s"
          interval = "10s"
          omit_hostname = false

          [global_tags]
          client_id = "faucet"
          namespace = "${namespace}"

          [inputs.prometheus]
          metric_version = 1

          urls = [ "http://{{ env "NOMAD_ADDR_metrics" }}" ]

          [outputs.influxdb]
          database = "telegraf"
          urls = ["http://{{with node "monitoring" }}{{ .Node.Address }}{{ end }}:8428"]
        '';

        destination = "local/telegraf.config";
      }];
    };
  };
in {
  "${namespace}-mantis" = mkNomadJob "mantis" {
    datacenters = [ "us-east-2" "eu-central-1" ];
    type = "service";
    inherit namespace;

    update = {
      maxParallel = 1;
      # healthCheck = "checks"
      minHealthyTime = "30s";
      healthyDeadline = "5m";
      progressDeadline = "10m";
      autoRevert = false;
      autoPromote = false;
      canary = 0;
      stagger = "30s";
    };

    taskGroups = let
      minerTaskGroups = lib.listToAttrs (map mkMiner miners);
      passiveTaskGroups = { passive = mkPassive 3; };
    in minerTaskGroups // passiveTaskGroups;
  };

  "${namespace}-morpho" = mkNomadJob "morpho" {
    datacenters = [ "us-east-2" "eu-central-1" ];
    type = "service";
    inherit namespace;

    taskGroups = let
      generateMorphoTaskGroup = nbNodes: node:
        lib.nameValuePair node.name (lib.recursiveUpdate (mkPassive 1)
          (mkMorpho (node // { inherit nbNodes; })));
      morphoTaskGroups =
        map (generateMorphoTaskGroup (builtins.length morphoNodes)) morphoNodes;
    in lib.listToAttrs morphoTaskGroups;
  };

  "${namespace}-explorer" = mkNomadJob "explorer" {
    datacenters = [ "us-east-2" "eu-central-1" ];
    type = "service";
    inherit namespace;

    taskGroups.explorer = explorer;
  };

  "${faucetName}" = mkNomadJob "faucet" {
    datacenters = [ "us-east-2" "eu-central-1" ];
    type = "service";
    inherit namespace;

    taskGroups.faucet = faucet;
  };
}

// (import ./mantis-active-gen.nix {
  inherit mkNomadJob dockerImages namespace;
})
