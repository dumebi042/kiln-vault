// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;
contract SimpleProxy {
    address public implementation;
    constructor(address _impl, bytes memory _data) {
        implementation = _impl;
        if (_data.length > 0) {
            (bool ok, ) = _impl.delegatecall(_data);
            require(ok, "init failed");
        }
    }
    fallback() external payable {
        address i = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let r := delegatecall(gas(), i, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(r) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}
