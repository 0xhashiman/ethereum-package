EL_RPC_PORT = 8545
EL_ENGINE_PORT = 8551
CL_P2P_PORT = 9000


def validator_entries(validator_count):
    entries = []
    for index in range(0, validator_count):
        node_id = "node-{0}".format(index + 1)
        el_service_name = "node-{0}-el".format(index + 1)
        cl_service_name = "node-{0}-cl".format(index + 1)
        entries.append(
            {
                "id": node_id,
                "engineUrl": "http://{0}:{1}".format(
                    el_service_name,
                    EL_ENGINE_PORT,
                ),
                "rpcUrl": "http://{0}:{1}".format(
                    el_service_name,
                    EL_RPC_PORT,
                ),
                "clP2PUrl": "{0}:{1}".format(
                    cl_service_name,
                    CL_P2P_PORT,
                ),
            }
        )
    return entries


def render_cl_config(lab_chain, validator_count):
    config = {
        "chainName": lab_chain.chain_name,
        "chainId": lab_chain.chain_id,
        "blockTimeSeconds": lab_chain.consensus.block_time_seconds,
        "validators": validator_entries(validator_count),
    }

    return json.indent(json.encode(config)) + "\n"
