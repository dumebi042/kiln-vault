contract BlockListFactory is AccessControlDefaultAdminRules {
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The role code for the deployer role.
    bytes32 public constant DEPLOYER_ROLE = bytes32("DEPLOYER");

    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The beacon used to create new blocklists.
    address public immutable blockListBeacon;

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice The list of deployed blocklists.
    BlockList[] public deployedBlockLists;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when a new blocklist is created.
    /// @param blockList The address of the new blocklist.
    /// @param name The name of the new blocklist.
    event BlockListCreated(address indexed blockList, string name);

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    constructor(address _initialAdmin, address _initialDeployer, uint48 _initialDelay, address _blockListBeacon)
        AccessControlDefaultAdminRules(_initialDelay, _initialAdmin)
    {
        if (_blockListBeacon.code.length == 0) revert AddressNotContract(_blockListBeacon);
        blockListBeacon = _blockListBeacon;

        _grantRole(DEPLOYER_ROLE, _initialDeployer);
    }

    /* -------------------------------------------------------------------------- */
    /*                                FACTORY LOGIC                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Parameters for the `initialize()` function.
    struct CreateBlockListParams {
        string name_;
        ISanctionsList underlyingSanctionsList_;
        address initialDefaultAdmin_;
        address initialOperator_;
        uint48 initialDelay_;
    }

    /// @notice Creates a new blocklist.
    /// @param params The parameters to initialize the blocklist.
    /// @param salt The salt for the blocklist deployment with CREATE2.
    /// @return The address of the new blocklist.
    function createBlockList(CreateBlockListParams calldata params, bytes32 salt)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address)
    {
        BlockList.InitializationParams memory initializationParams = BlockList.InitializationParams({
            name_: params.name_,
            underlyingSanctionsList_: params.underlyingSanctionsList_,
            initialDefaultAdmin_: params.initialDefaultAdmin_,
            initialOperator_: params.initialOperator_,
            initialDelay_: params.initialDelay_
        });
        bytes memory _initCalldata = abi.encodeCall(BlockList.initialize, initializationParams);

        address _newBlockList = Create2.deploy(
            0,
            salt,
            abi.encodePacked(type(BlockListBeaconProxy).creationCode, abi.encode(blockListBeacon, _initCalldata))
        );

        deployedBlockLists.push(BlockList(_newBlockList));
        emit BlockListCreated(_newBlockList, initializationParams.name_);
        return _newBlockList;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */

    function getDeployedBlockLists() public view returns (BlockList[] memory) {
        return deployedBlockLists;
    }
}

// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: 2024 Kiln <contact@kiln.fi>
//
// ██╗  ██╗██╗██╗     ███╗   ██╗
// ██║ ██╔╝██║██║     ████╗  ██║
// █████╔╝ ██║██║     ██╔██╗ ██║
// ██╔═██╗ ██║██║     ██║╚██╗██║
// ██║  ██╗██║███████╗██║ ╚████║
// ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
//
pragma solidity 0.8.22;

/// @title Sanctions List Interface.
/// @notice Interface for the sanctions list contract from Chainalysis.
