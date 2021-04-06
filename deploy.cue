package bitte

import (
	"github.com/input-output-hk/mantis-ops/pkg/schemas/nomad:types"
	jobDef "github.com/input-output-hk/mantis-ops/pkg/jobs:jobs"
	"list"
)

#defaultJobs: {
}

_Namespace: [Name=_]: {
	vars: {
		namespace: =~"^mantis-[a-z-]+$"
		namespace: Name
		let datacenter = "eu-central-1" | "us-east-2" | "eu-west-1"
		datacenters: list.MinItems(1) | [...datacenter] | *["eu-central-1", "us-east-2"]
		#fqdn:       "mantis.ws"
	}
	jobs: [string]: types.#stanza.job
}

#namespaces: _Namespace

#defaults: {
	mantisOpsRev: "97dfa8601097e8e0cf52d2f62d2f57b5ddb8cd81"
	mantisRev:    "fdeb1c33f6e0fc24680e256fe1b8d920b04950a8"
	morphoRev:    "b4335fb4e764d5441445179d0e8d9e3e596e7d94"
}

#faucet: jobDef.#Faucet & {
	#mantisOpsRev: #defaults.mantisOpsRev
}

#explorer: jobDef.#Explorer & {
	#mantisOpsRev: #defaults.mantisOpsRev
}

#miner: jobDef.#Mantis & {
	#role:      "miner"
	#mantisRev: #defaults.mantisRev
}

#passive: jobDef.#Mantis & {
	#role:      "passive"
	#mantisRev: #defaults.mantisRev
}

#morpho: jobDef.#Morpho & {
	#morphoRev: #defaults.morphoRev
	#mantisRev: #defaults.mantisRev
}

#namespaces: {
	"mantis-unstable": {
		vars: {
			#networkConfig: """
				mantis.blockchains.testnet-internal-nomad.bootstrap-nodes = [
				  "enode://f92aa66337ab1993cc7269d4295d296aefe6199b34e900eac08c514c947ec7340d46a5648ffc2da10325dbaba16bdf92aa9c0b5e51d97a7818c3f495d478ddad@mantis-testnet-0.mantis.ws:9001?discport=9501",
				  "enode://d8a010f019db37dcaf2e1fb98d4fcbf1f57dbd7e2a7f065e92fbe77dca8b9120d6e79f1617e98fa6134e6af8858ac8f3735b1e70a5708eb14f228080356eb0a7@mantis-testnet-1.mantis.ws:9002?discport=9502",
				  "enode://442e2bd50eece65f90dee0d5c6075da4e1b4bc62e36b261a52e7f393dae6a68241e4dbad868c7ecc14fed277ed72e99a289a811b6172f35fb18bdca0b7a5602c@mantis-testnet-2.mantis.ws:9003?discport=9503",
				  "enode://ff86741b7b35087b2b53f44a612b233336490d5fae10b1434619b7714fe2d5346c71427a5e126cd27b9422a4d4376c1534ef66e88c5e62d6441d2541f63de0cf@mantis-testnet-3.mantis.ws:9004?discport=9504",
				  "enode://af97643f364b805d5b0e32b5356578a16afcc4fb9d1b6622998e9441eeb7795e8daf8e6b0ff3330da9879034112be56954f9269164513ece0f7394b805be3633@mantis-testnet-4.mantis.ws:9005?discport=9505",
				]
				"""
		}
		jobs: {
			explorer: #explorer
			faucet:   #faucet
			miner:    #miner & {#count:   5}
			passive:  #passive & {#count:   5}
			morpho:   #morpho & {#count:   5}
		}
	}
	"mantis-testnet": {
		vars: {
			#networkConfig: """
				mantis.blockchains.testnet-internal-nomad.bootstrap-nodes = [
				  "enode://f92aa66337ab1993cc7269d4295d296aefe6199b34e900eac08c514c947ec7340d46a5648ffc2da10325dbaba16bdf92aa9c0b5e51d97a7818c3f495d478ddad@mantis-testnet-0.mantis.ws:9001?discport=9501",
				  "enode://d8a010f019db37dcaf2e1fb98d4fcbf1f57dbd7e2a7f065e92fbe77dca8b9120d6e79f1617e98fa6134e6af8858ac8f3735b1e70a5708eb14f228080356eb0a7@mantis-testnet-1.mantis.ws:9002?discport=9502",
				  "enode://442e2bd50eece65f90dee0d5c6075da4e1b4bc62e36b261a52e7f393dae6a68241e4dbad868c7ecc14fed277ed72e99a289a811b6172f35fb18bdca0b7a5602c@mantis-testnet-2.mantis.ws:9003?discport=9503",
				  "enode://ff86741b7b35087b2b53f44a612b233336490d5fae10b1434619b7714fe2d5346c71427a5e126cd27b9422a4d4376c1534ef66e88c5e62d6441d2541f63de0cf@mantis-testnet-3.mantis.ws:9004?discport=9504",
				  "enode://af97643f364b805d5b0e32b5356578a16afcc4fb9d1b6622998e9441eeb7795e8daf8e6b0ff3330da9879034112be56954f9269164513ece0f7394b805be3633@mantis-testnet-4.mantis.ws:9005?discport=9505",
				]
				"""
		}

		jobs: {
			explorer: #explorer
			faucet:   #faucet
			miner:    #miner & {#count:   5}
			passive:  #passive & {#count: 5}
			morpho:   #morpho & {#count:  5}
		}
	}
	"mantis-staging": {
		vars: {
			#networkConfig: """
				mantis.blockchains.testnet-internal-nomad.bootstrap-nodes = [
				  "enode://cbd80c7f72a889101b7f23d51be2de7e3f1f46ad3b25c438e959e24e08f03bd9fe833460e84b60174d4eb120af3b127389c4606f81c842943c4922cab384a234@mantis-staging-0.mantis.ws:33000?discport=33500",
				  "enode://0e63642be49c5a092569aa01663fcda1505362cd0ac41e24ff9296ab80c97af135fb6fb247273631a3a11257774f39ed882d72a20fd45131e53e9015adf6b9e5@mantis-staging-1.mantis.ws:33001?discport=33501",
				  "enode://3ee3641a25cfc611ba54a898260af7768ecf0643f06aefedf853864ed433d5ad6265eeb24abcc4d6f6ee90a1eac6c1fbf157fc05fd8e28e194dfc864cb56058e@mantis-staging-2.mantis.ws:33002?discport=33502",
				  "enode://907842e336fc757bbfde70368aef329714aa627e72e5da687f31b097fa71a59f36404aebbc83885c9b515270042e025a6788b700c314ee8bc68099dcff32afcd@mantis-staging-3.mantis.ws:33003?discport=33503",
				  "enode://92958d370442cfbf3efc46b37a0a1608298d8118013bf86868aaa49305a58991e006857552a88ac3349c5da43b00df44e685b39982f61c2fdeb3582daecac476@mantis-staging-4.mantis.ws:33004?discport=33504",
				]
				"""
		}
		jobs: {
			explorer: #explorer
			faucet:   #faucet
			miner:    #miner & {#count:   5}
			passive:  #passive & {#count: 5}
			morpho:   #morpho & {#count:   5}
		}
	}
	// "mantis-iele": jobs:        #defaultJobs
	// "mantis-qa-load": jobs:     #defaultJobs
	// "mantis-qa-fastsync": jobs: #defaultJobs
}

for nsName, nsValue in #namespaces {
	rendered: "\(nsName)": {
		for jName, jValue in nsValue.jobs {
			"\(jName)": Job: types.#toJson & {
				#jobName: jName
				#job:     jValue & nsValue.vars
			}
		}
	}
}

for nsName, nsValue in #namespaces {
	// output is alphabetical, so better errors show at the end.
	zchecks: "\(nsName)": {
		for jName, jValue in nsValue.jobs {
			"\(jName)": jValue & nsValue.vars
		}
	}
}
