#!/bin/bash
# Fetch all Kiln OmniVault source codes from Etherscan using cast source
set -e

source .env

mkdir -p src

fetch_contract() {
    local address=$1
    local name=$2
    local output_file="src/${name}.sol"
    
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        echo "Skipping $name (already exists)"
        return
    fi
    
    echo "Fetching $name ($address)..."
    cast source "$address" --etherscan-api-key "$ETHERSCAN_API_KEY" > "$output_file" 2>&1
    lines=$(wc -l < "$output_file")
    echo "  Saved: $output_file ($lines lines)"
}

# Core Contracts
fetch_contract "0x869855168858364368e62A5D1D092cc1dbD31f5a" "Vault"
fetch_contract "0x15f7f910e5a8c86e609fd11c58f7342d86d3a25c" "VaultUpgradeableBeacon"
fetch_contract "0xdE63817c82e93499357aE198518f90Ac1bE93A72" "ConnectorRegistry"
fetch_contract "0x4A1Ede66750e8e44a1569A4Af3F53fb31De3Dd32" "VaultFactory"
fetch_contract "0x533DD3A719968Dba0cf454C2B2a692d196DF3605" "ExternalAccessControl"
fetch_contract "0x637F9D0E032EFb98fe8Ae55C6D798FD54060Be04" "FeeDispatcher"
fetch_contract "0x7e7F84Da187117e06AbB03E1454E07Af42D0E4BE" "BlockList"
fetch_contract "0x0d87F2834b4766CAf25aD5dBE193BEd70f5D9458" "BlockListFactory"
fetch_contract "0xB58700939159Db7a47b64FF74cF98150AccBF904" "BlockListUpgradeableBeacon"

# Connector Implementations
fetch_contract "0x08c28e1c82C09487DCB15a3e0839e8C888EeE3CD" "AaveV3Connector"
fetch_contract "0xbeaa30DCB697CFFB64E319A3Fc4b0688Be5aE790" "CompoundV3Connector"
fetch_contract "0x22Fc700401FABbB7de1872461E8733d74e02f88a" "SDAIConnector"
fetch_contract "0xDa5FfFCF097A95E0aE6e6eC9b966da5ba89844f2" "MetamorphoConnector"
fetch_contract "0x3443Ea9BcC9E1E515e567a278bDae103e7324d1d" "AngleSavingConnector"
fetch_contract "0xe68c8E20C4E469800A13ABeBF0Dfd094CC2C4DE2" "SUSDSConnector"

echo ""
echo "=== Fetch complete ==="
echo "Files in src/:"
ls -la src/*.sol 2>/dev/null | awk '{print $5, $NF}'
