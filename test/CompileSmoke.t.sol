// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import {BlockList} from "../src/BlockList.sol";
import {BlockListFactory} from "../src/BlockListFactory.sol";
import {ConnectorRegistry} from "../src/ConnectorRegistry.sol";
import {ExternalAccessControl} from "../src/ExternalAccessControl.sol";
import {FeeDispatcher} from "../src/FeeDispatcher.sol";
import {Vault} from "../src/Vault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {AaveV3Connector} from "../src/connectors/AaveV3Connector.sol";
import {AngleSavingConnector} from "../src/connectors/AngleSavingConnector.sol";
import {CompoundV3Connector} from "../src/connectors/CompoundV3Connector.sol";
import {MetamorphoConnector} from "../src/connectors/MetamorphoConnector.sol";
import {SDAIConnector} from "../src/connectors/SDAIConnector.sol";
import {SUSDSConnector} from "../src/connectors/SUSDSConnector.sol";
import {BlockListBeaconProxy} from "../src/proxy/BlockListBeaconProxy.sol";
import {BlockListUpgradeableBeacon} from "../src/proxy/BlockListUpgradeableBeacon.sol";
import {VaultBeaconProxy} from "../src/proxy/VaultBeaconProxy.sol";
import {VaultUpgradeableBeacon} from "../src/proxy/VaultUpgradeableBeacon.sol";

contract CompileSmokeTest is Test {
    function test_reconstructedScopeCompiles() external pure {
        assertTrue(true);
    }
}
