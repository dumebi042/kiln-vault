// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {SimpleProxy} from "../../../../src/test-helpers/SimpleProxy.sol";
import {ExternalAccessControl} from "../../../../src/ExternalAccessControl.sol";
import {BlockList} from "../../../../src/BlockList.sol";
import {ISanctionsList} from "../../../../src/interfaces/ISanctionsList.sol";

/// @notice Deploys contracts behind SimpleProxy for delegatecall context.
library DeployHelper {
    function deployEac(
        address admin,
        bytes32 role,
        address roleAccount,
        uint48 delay
    ) external returns (ExternalAccessControl) {
        ExternalAccessControl impl = new ExternalAccessControl();
        bytes memory initData = abi.encodeCall(
            ExternalAccessControl.initialize,
            ExternalAccessControl.InitializationParams({
                initialDefaultAdmin_: admin,
                initialRole_: ExternalAccessControl.InitialRole({
                    role: role,
                    account: roleAccount
                }),
                initialDelay_: delay
            })
        );
        SimpleProxy proxy = new SimpleProxy(address(impl), initData);
        return ExternalAccessControl(address(proxy));
    }

    function deployBlockList(
        address admin,
        address operator
    ) external returns (BlockList) {
        BlockList impl = new BlockList();
        bytes memory initData = abi.encodeCall(
            BlockList.initialize,
            BlockList.InitializationParams({
                underlyingSanctionsList_: ISanctionsList(address(0)),
                name_: "TestBL",
                initialDefaultAdmin_: admin,
                initialOperator_: operator,
                initialDelay_: 0
            })
        );
        SimpleProxy proxy = new SimpleProxy(address(impl), initData);
        return BlockList(address(proxy));
    }
}
