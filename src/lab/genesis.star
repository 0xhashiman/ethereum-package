ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000"
HEX_DIGITS = "0123456789abcdef"


def parse_display_amount(amount, symbol, conversion):
    suffix = symbol
    if not amount.endswith(suffix):
        fail("amount must end with token symbol, e.g. 1000%s" % symbol)

    whole = amount[: len(amount) - len(suffix)]
    if whole == "":
        fail("amount must include a whole token amount before %s" % symbol)
    if "." in whole:
        fail("MVP only supports whole token amounts")

    return str(int(whole) * int(conversion))


def normalize_balance(balance, symbol, conversion):
    if type(balance) == "int":
        return str(balance)
    if type(balance) != "string":
        fail("prefund balance must be a string or int, got {0}".format(type(balance)))
    if balance.endswith(symbol):
        return parse_display_amount(balance, symbol, conversion)
    return balance


def render_alloc(lab_chain):
    symbol = lab_chain.native_token.symbol
    conversion = lab_chain.native_token.conversion
    alloc = {}

    for address, account in lab_chain.accounts.prefund.items():
        if type(account) == "dict":
            if "balance" not in account:
                fail("prefund account {0} must include a balance".format(address))
            alloc_account = {}
            for key, value in account.items():
                alloc_account[key] = value
            alloc_account["balance"] = normalize_balance(
                account["balance"],
                symbol,
                conversion,
            )
            alloc[address] = alloc_account
        else:
            alloc[address] = {
                "balance": normalize_balance(account, symbol, conversion),
            }

    return alloc


def render_genesis(lab_chain):
    fees = lab_chain.fees
    native_token = lab_chain.native_token

    genesis = {
        "config": {
            "chainId": lab_chain.chain_id,
            "homesteadBlock": 0,
            "eip150Block": 0,
            "eip155Block": 0,
            "eip158Block": 0,
            "byzantiumBlock": 0,
            "constantinopleBlock": 0,
            "petersburgBlock": 0,
            "istanbulBlock": 0,
            "berlinBlock": 0,
            "londonBlock": 0,
            "shanghaiTime": 0,
            "cancunTime": 0,
            "terminalTotalDifficulty": 0,
            "terminalTotalDifficultyPassed": True,
            "blobSchedule": {
                "cancun": {
                    "target": 3,
                    "max": 6,
                    "baseFeeUpdateFraction": 3338477,
                },
            },
            "lab": {
                "chainName": lab_chain.chain_name,
                "nativeToken": {
                    "name": native_token.name,
                    "symbol": native_token.symbol,
                    "decimals": native_token.decimals,
                    "baseUnit": native_token.base_unit,
                    "displayUnit": native_token.display_unit,
                    "conversion": native_token.conversion,
                },
                "fees": {
                    "minGasPrice": str(fees.min_gas_price),
                    "blockGasLimit": str(fees.block_gas_limit),
                },
                "consensus": {
                    "blockTimeSeconds": lab_chain.consensus.block_time_seconds,
                },
            },
        },
        "nonce": "0x0",
        "timestamp": "0x0",
        "extraData": "0x",
        "gasLimit": fees.block_gas_limit,
        "difficulty": "0x0",
        "mixHash": ZERO_HASH,
        "coinbase": ZERO_ADDRESS,
        "alloc": render_alloc(lab_chain),
        "baseFeePerGas": fees.min_gas_price,
    }

    return json.indent(json.encode(genesis)) + "\n"
