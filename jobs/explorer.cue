package jobs

import (
	"github.com/input-output-hk/mantis-ops/pkg/schemas/nomad:types"
	"github.com/input-output-hk/mantis-ops/pkg/jobs/tasks:tasks"
	"list"
)

#Explorer: types.#stanza.job & {
	#args: {
		datacenters:  list.MinItems(1)
		namespace:    string
		fqdn:         string
		mantisOpsRev: string
		network:      string
	}

	#fqdn:      #args.fqdn
	#name:      "\(namespace)-explorer"
	#namespace: #args.namespace

	datacenters: #args.datacenters
	namespace:   #args.namespace
	type:        "service"

	update: {
		max_parallel:      1
		health_check:      "checks"
		min_healthy_time:  "1m"
		healthy_deadline:  "10m"
		progress_deadline: "11m"
		auto_revert:       true
		auto_promote:      true
		canary:            1
		stagger:           "1m"
	}

	group: explorer: {
		service: "\(#name)": {
			address_mode: "host"
			port:         "explorer"

			tags: [namespace, #name, "ingress", "explorer",
				"traefik.enable=true",
				"traefik.http.routers.\(namespace)-explorer.rule=Host(`\(namespace)-explorer.\(#fqdn)`)",
				"traefik.http.routers.\(namespace)-explorer.entrypoints=https",
				"traefik.http.routers.\(namespace)-explorer.tls=true",
			]

			check: explorer: {
				type:     "http"
				path:     "/"
				port:     "explorer"
				timeout:  "3s"
				interval: "30s"
				check_restart: {
					limit: 0
					grace: "60s"
				}
			}
		}

		network: {
			mode: "host"
			port: explorer: {}
		}

		task: explorer: tasks.#Explorer & {
			#taskArgs: {
				upstreamServiceName: "\(namespace)-mantis-passive-rpc"
				mantisOpsRev:        #args.mantisOpsRev
			}
		}
	}
}
