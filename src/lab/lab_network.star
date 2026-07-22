blockscout = import_module("../blockscout/blockscout_launcher.star")
constants = import_module("../package_io/constants.star")
el_admin_node_info = import_module("../el/el_admin_node_info.star")
el_context = import_module("../el/el_context.star")
el_shared = import_module("../el/el_shared.star")
genesis = import_module("./genesis.star")
cl_config = import_module("./cl_config.star")
input_parser = import_module("../package_io/input_parser.star")
shared_utils = import_module("../shared_utils/shared_utils.star")
static_files = import_module("../static_files/static_files.star")

RPC_PORT_NUM = 8545
WS_PORT_NUM = 8546
DISCOVERY_PORT_NUM = 30303
ENGINE_RPC_PORT_NUM = 8551
METRICS_PORT_NUM = 9001
CL_P2P_PORT_NUM = 9000

EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER = "/data/geth/execution-data"
ENTRYPOINT_ARGS = ["sh", "-c"]
LAB_GENESIS_ARTIFACT_NAME = "lab-genesis"
LAB_CL_CONFIG_ARTIFACT_NAME = "lab-cl-config"
LAB_CL_CONFIG_MOUNTPOINT = "/config"
LAB_CL_CONFIG_PATH = LAB_CL_CONFIG_MOUNTPOINT + "/lab-cl.json"
LAB_CL_P2P_PORT_ID = "cl-p2p"


def _render_artifact(plan, filename, content, name):
    return plan.render_templates(
        {
            filename: shared_utils.new_template_and_data(
                content,
                {},
            ),
        },
        name=name,
    )


def _service_name(index):
    return "node-{0}-el".format(index + 1)


def _enode_with_service_ip(enode, ip_addr):
    return enode.replace("@127.0.0.1:", "@" + ip_addr + ":")


def _get_log_level(participant, global_log_level):
    levels = {
        constants.GLOBAL_LOG_LEVEL.error: "1",
        constants.GLOBAL_LOG_LEVEL.warn: "2",
        constants.GLOBAL_LOG_LEVEL.info: "3",
        constants.GLOBAL_LOG_LEVEL.debug: "4",
        constants.GLOBAL_LOG_LEVEL.trace: "5",
    }
    return input_parser.get_client_log_level_or_default(
        participant.el_log_level,
        global_log_level,
        levels,
    )


def _get_geth_config(
    plan,
    args_with_right_defaults,
    participant,
    participant_index,
    service_name,
    genesis_artifact,
    jwt_file,
    bootnode_enode,
):
    lab_chain = args_with_right_defaults.lab_chain
    port_publisher = args_with_right_defaults.port_publisher

    public_ports = {}
    public_ports_for_component = None
    if port_publisher.el_enabled:
        public_ports_for_component = shared_utils.get_public_ports_for_component(
            "el",
            port_publisher,
            participant_index,
        )
        public_ports = el_shared.get_general_el_public_port_specs(
            public_ports_for_component
        )
        public_ports.update(
            shared_utils.get_port_specs(
                {
                    constants.RPC_PORT_ID: public_ports_for_component[3],
                    constants.WS_PORT_ID: public_ports_for_component[4],
                }
            )
        )

    discovery_port = (
        public_ports_for_component[0]
        if public_ports_for_component
        else DISCOVERY_PORT_NUM
    )
    used_ports = shared_utils.get_port_specs(
        {
            constants.TCP_DISCOVERY_PORT_ID: discovery_port,
            constants.UDP_DISCOVERY_PORT_ID: discovery_port,
            constants.ENGINE_RPC_PORT_ID: ENGINE_RPC_PORT_NUM,
            constants.RPC_PORT_ID: RPC_PORT_NUM,
            constants.WS_PORT_ID: WS_PORT_NUM,
            constants.METRICS_PORT_ID: METRICS_PORT_NUM,
        }
    )

    cmd = [
        "geth",
        "--networkid={0}".format(lab_chain.chain_id),
        "--verbosity={0}".format(
            _get_log_level(participant, args_with_right_defaults.global_log_level)
        ),
        "--datadir={0}".format(EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER),
        "--http",
        "--http.addr=0.0.0.0",
        "--http.port={0}".format(RPC_PORT_NUM),
        "--http.vhosts=*",
        "--http.corsdomain=*",
        "--http.api=admin,net,eth,web3,debug,txpool,lab",
        "--ws",
        "--ws.addr=0.0.0.0",
        "--ws.port={0}".format(WS_PORT_NUM),
        "--ws.api=admin,net,eth,web3,debug,txpool,lab",
        "--ws.origins=*",
        "--authrpc.port={0}".format(ENGINE_RPC_PORT_NUM),
        "--authrpc.addr=0.0.0.0",
        "--authrpc.vhosts=*",
        "--authrpc.jwtsecret=" + constants.JWT_MOUNT_PATH_ON_CONTAINER,
        "--syncmode=full",
        "--rpc.allow-unprotected-txs",
        "--metrics",
        "--metrics.addr=0.0.0.0",
        "--metrics.port={0}".format(METRICS_PORT_NUM),
        "--discovery.port={0}".format(discovery_port),
        "--port={0}".format(discovery_port),
        "--nat=extip:" + constants.PRIVATE_IP_ADDRESS_PLACEHOLDER,
        "--miner.gasprice={0}".format(lab_chain.fees.min_gas_price),
        "--txpool.pricelimit={0}".format(lab_chain.fees.min_gas_price),
        "--miner.gaslimit={0}".format(lab_chain.fees.block_gas_limit),
    ]

    if bootnode_enode != "":
        cmd.append("--bootnodes=" + bootnode_enode)
    if len(participant.el_extra_params) > 0:
        cmd.extend([param for param in participant.el_extra_params])

    cmd_str = "geth init --datadir={0} {1}/genesis.json && exec {2}".format(
        EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER,
        constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER,
        " ".join(cmd),
    )

    files = {
        constants.GENESIS_DATA_MOUNTPOINT_ON_CLIENTS: genesis_artifact,
        constants.JWT_MOUNTPOINT_ON_CLIENTS: jwt_file,
    }
    if args_with_right_defaults.persistent:
        files[EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER] = Directory(
            persistent_key="data-{0}".format(service_name),
            size=(
                int(participant.el_volume_size)
                if int(participant.el_volume_size) > 0
                else constants.VOLUME_SIZE["devnets"]["geth_volume_size"]
            ),
        )

    node_selectors = input_parser.get_client_node_selectors(
        participant.node_selectors,
        args_with_right_defaults.global_node_selectors,
    )
    tolerations = shared_utils.get_tolerations(
        specific_container_tolerations=participant.el_tolerations,
        participant_tolerations=participant.tolerations,
        global_tolerations=args_with_right_defaults.global_tolerations,
    )
    labels = participant.el_extra_labels | {
        constants.NODE_INDEX_LABEL_KEY: str(participant_index + 1)
    }

    config_args = {
        "image": shared_utils.docker_cache_image_calc(
            args_with_right_defaults.docker_cache_params,
            participant.el_image,
        ),
        "ports": used_ports,
        "public_ports": public_ports,
        "publish_udp": port_publisher.el_enabled,
        "cmd": [cmd_str],
        "files": files,
        "entrypoint": ENTRYPOINT_ARGS,
        "private_ip_address_placeholder": constants.PRIVATE_IP_ADDRESS_PLACEHOLDER,
        "env_vars": participant.el_extra_env_vars,
        "labels": shared_utils.label_maker(
            client=constants.EL_TYPE.geth,
            client_type=constants.CLIENT_TYPES.el,
            image=participant.el_image[-constants.MAX_LABEL_LENGTH :],
            connected_client="lab-cl",
            extra_labels=labels,
        ),
        "tolerations": tolerations,
        "node_selectors": node_selectors,
    }

    if participant.el_min_cpu > 0:
        config_args["min_cpu"] = participant.el_min_cpu
    if participant.el_max_cpu > 0:
        config_args["max_cpu"] = participant.el_max_cpu
    if participant.el_min_mem > 0:
        config_args["min_memory"] = participant.el_min_mem
    if participant.el_max_mem > 0:
        config_args["max_memory"] = participant.el_max_mem
    if len(participant.el_devices) > 0:
        config_args["devices"] = participant.el_devices

    return ServiceConfig(**config_args)


def _get_cl_config(
    args_with_right_defaults,
    participant,
    participant_index,
    cl_config_artifact,
    jwt_file,
):
    node_id = "node-{0}".format(participant_index + 1)
    service_name = "{0}-cl".format(node_id)
    node_selectors = input_parser.get_client_node_selectors(
        participant.node_selectors,
        args_with_right_defaults.global_node_selectors,
    )
    tolerations = shared_utils.get_tolerations(
        specific_container_tolerations=participant.cl_tolerations,
        participant_tolerations=participant.tolerations,
        global_tolerations=args_with_right_defaults.global_tolerations,
    )
    labels = participant.cl_extra_labels | {
        constants.NODE_INDEX_LABEL_KEY: str(participant_index + 1)
    }

    config_args = {
        "image": shared_utils.docker_cache_image_calc(
            args_with_right_defaults.docker_cache_params,
            participant.cl_image,
        ),
        "cmd": [
            "--config={0}".format(LAB_CL_CONFIG_PATH),
            "--node-id={0}".format(node_id),
            "--engine-url=http://{0}-el:{1}".format(node_id, ENGINE_RPC_PORT_NUM),
            "--jwt={0}".format(constants.JWT_MOUNT_PATH_ON_CONTAINER),
        ],
        "ports": {
            LAB_CL_P2P_PORT_ID: shared_utils.new_port_spec(
                CL_P2P_PORT_NUM,
                shared_utils.TCP_PROTOCOL,
                wait=None,
            ),
        },
        "files": {
            LAB_CL_CONFIG_MOUNTPOINT: cl_config_artifact,
            constants.JWT_MOUNTPOINT_ON_CLIENTS: jwt_file,
        },
        "env_vars": participant.cl_extra_env_vars,
        "labels": shared_utils.label_maker(
            client=participant.cl_type,
            client_type=constants.CLIENT_TYPES.cl,
            image=participant.cl_image[-constants.MAX_LABEL_LENGTH :],
            connected_client=constants.EL_TYPE.geth,
            extra_labels=labels,
        ),
        "tolerations": tolerations,
        "node_selectors": node_selectors,
    }

    if participant.cl_min_cpu > 0:
        config_args["min_cpu"] = participant.cl_min_cpu
    if participant.cl_max_cpu > 0:
        config_args["max_cpu"] = participant.cl_max_cpu
    if participant.cl_min_mem > 0:
        config_args["min_memory"] = participant.cl_min_mem
    if participant.cl_max_mem > 0:
        config_args["max_memory"] = participant.cl_max_mem
    if len(participant.cl_devices) > 0:
        config_args["devices"] = participant.cl_devices

    return service_name, ServiceConfig(**config_args)


def _new_el_context(plan, service_name, service):
    enode, enr = el_admin_node_info.get_enode_enr_for_node(
        plan,
        service_name,
        constants.RPC_PORT_ID,
    )
    return el_context.new_el_context(
        client_name=constants.EL_TYPE.geth,
        enode=enode,
        dns_name=service.name,
        rpc_port_num=RPC_PORT_NUM,
        ws_port_num=WS_PORT_NUM,
        engine_rpc_port_num=ENGINE_RPC_PORT_NUM,
        rpc_http_url="http://{0}:{1}".format(service.name, RPC_PORT_NUM),
        ws_url="ws://{0}:{1}".format(service.name, WS_PORT_NUM),
        enr=enr,
        service_name=service_name,
        el_metrics_info=[],
        ip_addr=service.ip_address,
    )


def _validate_lab_inputs(args_with_right_defaults):
    if len(args_with_right_defaults.participants) == 0:
        fail(
            "lab_mode requires at least one participant; every participant is a validator"
        )

    for index, participant in enumerate(args_with_right_defaults.participants):
        if participant.el_type != constants.EL_TYPE.geth:
            fail(
                "lab_mode currently supports geth EL participants only; participant {0} uses {1}".format(
                    index + 1,
                    participant.el_type,
                )
            )
        if not participant.el_image_was_provided:
            fail("lab_mode requires explicit patched geth image")
        if "lab" not in participant.el_image:
            fail("lab_mode requires patched lab geth image")
        if participant.cl_image == "" or "lab" not in participant.cl_image:
            fail("lab_mode requires patched lab-cl image")

    for service in args_with_right_defaults.additional_services:
        if service != "blockscout":
            fail(
                "lab_mode currently supports only blockscout in additional_services, got {0}".format(
                    service
                )
            )


def launch_lab_network(plan, args_with_right_defaults):
    _validate_lab_inputs(args_with_right_defaults)

    lab_chain = args_with_right_defaults.lab_chain
    genesis_artifact = _render_artifact(
        plan,
        "genesis.json",
        genesis.render_genesis(lab_chain),
        LAB_GENESIS_ARTIFACT_NAME,
    )
    cl_config_artifact = _render_artifact(
        plan,
        "lab-cl.json",
        cl_config.render_cl_config(
            lab_chain,
            len(args_with_right_defaults.participants),
        ),
        LAB_CL_CONFIG_ARTIFACT_NAME,
    )
    jwt_file = plan.upload_files(
        src=static_files.JWT_PATH_FILEPATH,
        name="lab-jwt-file",
    )

    all_el_contexts = []
    all_cl_services = []
    bootnode_enode = ""
    for index, participant in enumerate(args_with_right_defaults.participants):
        service_name = _service_name(index)
        service = plan.add_service(
            service_name,
            _get_geth_config(
                plan,
                args_with_right_defaults,
                participant,
                index,
                service_name,
                genesis_artifact,
                jwt_file,
                bootnode_enode,
            ),
            force_update=participant.el_force_restart,
        )
        context = _new_el_context(plan, service_name, service)
        all_el_contexts.append(context)
        if index == 0:
            bootnode_enode = _enode_with_service_ip(context.enode, context.ip_addr)

        cl_service_name, cl_service_config = _get_cl_config(
            args_with_right_defaults,
            participant,
            index,
            cl_config_artifact,
            jwt_file,
        )
        all_cl_services.append(
            plan.add_service(
                cl_service_name,
                cl_service_config,
                force_update=participant.cl_force_restart,
            )
        )

    blockscout_url = None
    for index, service in enumerate(args_with_right_defaults.additional_services):
        if service == "blockscout":
            blockscout_url = blockscout.launch_blockscout(
                plan,
                all_el_contexts,
                args_with_right_defaults.persistent,
                args_with_right_defaults.global_node_selectors,
                args_with_right_defaults.global_tolerations,
                args_with_right_defaults.port_publisher,
                index,
                args_with_right_defaults.docker_cache_params,
                args_with_right_defaults.blockscout_params,
                struct(network_id=str(lab_chain.chain_id)),
                lab_chain=lab_chain,
            )

    plan.print(
        "Lab network launched: {0} ({1})".format(
            lab_chain.chain_name,
            lab_chain.chain_id,
        )
    )

    return struct(
        all_el_contexts=all_el_contexts,
        all_cl_services=all_cl_services,
        blockscout_url=blockscout_url,
        cl_config_artifact=cl_config_artifact,
        genesis_artifact=genesis_artifact,
        lab_chain=lab_chain,
    )
