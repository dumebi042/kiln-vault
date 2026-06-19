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

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    AddressZero,
    EmptyArray,
    FeeRecipientDoesNotExist,
    FeeRecipientNotUnique,
    NotDelegateCall,
    WrongDepositFeeSplit,
    WrongRewardFeeSplit
} from "./libraries/Errors.sol";
import {IFeeDispatcher} from "./interfaces/IFeeDispatcher.sol";
import {_MAX_PERCENT} from "./libraries/Constants.sol";

/// @title FeeDispatcher.
/// @notice Dispatches Vaults pending deposit and reward fees to the fee recipients.
/// @dev Using ERC-7201 standard.
/// @author maximebrugel @ Kiln.
contract FeeDispatcher is IFeeDispatcher, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation (regardless of the context).
    address internal immutable _self = address(this);

    /* -------------------------------------------------------------------------- */
    /*                               STORAGE (proxy)                              */
    /* -------------------------------------------------------------------------- */

    /// @notice The storage layout of the contract.
    /// @param _dispatches Mapping of all the dispatches with the vaults.
    struct FeeDispatcherStorage {
        mapping(address => IFeeDispatcher.Dispatch) _dispatches;
    }

    function _getFeeDispatcherStorage() private pure returns (FeeDispatcherStorage storage $) {
        assembly {
            $.slot := FeeDispatcherStorageLocation
        }
    }

    /// @dev The storage slot of the FeeDispatcherStorage struct in the proxy contract.
    ///      keccak256(abi.encode(uint256(keccak256("kiln.storage.feedispatcher")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FeeDispatcherStorageLocation =
        0xfdd5e928c3467d3da929a44639dde8d54e0576a04fec4ff333caa67a6f243300;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when the pending deposit fee is dispatched to a recipient.
    /// @param vault The vault from which the deposit fee is dispatched.
    /// @param recipient The recipient of the deposit fee.
    /// @param depositFee The amount of the deposit fee dispatched.
    event DepositFeeDispatched(address indexed vault, address indexed recipient, uint256 depositFee);

    /// @dev Emitted when the pending reward fee is dispatched to a recipient.
    /// @param vault The vault from which the reward fee is dispatched.
    /// @param recipient The recipient of the reward fee.
    /// @param rewardFee The amount of the reward fee dispatched.
    event RewardFeeDispatched(address indexed vault, address indexed recipient, uint256 rewardFee);

    /// @dev Emitted when the fee recipients are set.
    /// @param vault The vault for which the fee recipients are set.
    /// @param feeRecipients The fee recipients (array of structs).
    event FeeRecipientsSet(address indexed vault, IFeeDispatcher.FeeRecipient[] feeRecipients);

    /// @dev Emitted reward fees are collected.
    /// @param vault The vault from which the reward fees are collected.
    /// @param rewardFeeAmount The amount of reward fees collected.
    event RewardFeesCollected(address indexed vault, uint256 rewardFeeAmount);

    /// @dev Emitted deposit fees are collected.
    /// @param vault The vault from which the deposit fees are collected.
    /// @param depositFeeAmount The amount of deposit fees collected.
    event DepositFeesCollected(address indexed vault, uint256 depositFeeAmount);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Throws if the call is not a delegate call.
    ///      Allow to check if the contract is called from a proxy.
    modifier onlyDelegateCall() {
        if (address(this) == _self) revert NotDelegateCall();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                              INITIALIZE LOGIC                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Initializes the contract in the proxy context.
    function initialize() public initializer onlyDelegateCall {
        _initialize();
    }

    /// @dev Internal logic to initialize the contract in the proxy context.
    function _initialize() internal {
        __ReentrancyGuard_init();
    }

    /* -------------------------------------------------------------------------- */
    /*                            FEE DISPATCHER LOGIC                            */
    /* -------------------------------------------------------------------------- */

    /// @dev Dispatch the pending deposit/reward fee to the fee recipients.
    /// @param asset The asset to dispatch the fees in.
    /// @param underlyingDecimals The number of decimals of the underlying asset.
    function dispatchFees(IERC20 asset, uint8 underlyingDecimals) external nonReentrant {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();

        uint256 _pendingDepositFee = $._dispatches[msg.sender]._pendingDepositFee;
        uint256 _pendingRewardFee = $._dispatches[msg.sender]._pendingRewardFee;
        uint256 _depositFeeTransferred;
        uint256 _rewardFeeTransferred;

        uint256 _recipientsLength = $._dispatches[msg.sender]._feeRecipients.length;
        IFeeDispatcher.FeeRecipient memory currentRecipient;
        for (uint256 i; i < _recipientsLength; i++) {
            currentRecipient = $._dispatches[msg.sender]._feeRecipients[i];

            if (_pendingDepositFee > 0) {
                // Compute the deposit fee amount for the current recipient (based on the deposit
                // fee split between all recipients).
                uint256 _depositFeeAmount =
                    _pendingDepositFee.mulDiv(currentRecipient.depositFeeSplit, _MAX_PERCENT * 10 ** underlyingDecimals);
                if (_depositFeeAmount > 0) {
                    asset.safeTransferFrom(msg.sender, currentRecipient.recipient, _depositFeeAmount);
                    _depositFeeTransferred += _depositFeeAmount;
                    emit DepositFeeDispatched(msg.sender, currentRecipient.recipient, _depositFeeAmount);
                }
            }

            if (_pendingRewardFee > 0) {
                // Compute the reward fee amount for the current recipient (based on the reward
                // fee split between all recipients).
                uint256 _rewardFeeAmount =
                    _pendingRewardFee.mulDiv(currentRecipient.rewardFeeSplit, _MAX_PERCENT * 10 ** underlyingDecimals);
                if (_rewardFeeAmount > 0) {
                    asset.safeTransferFrom(msg.sender, currentRecipient.recipient, _rewardFeeAmount);
                    _rewardFeeTransferred += _rewardFeeAmount;
                    emit RewardFeeDispatched(msg.sender, currentRecipient.recipient, _rewardFeeAmount);
                }
            }
        }
        $._dispatches[msg.sender]._pendingDepositFee = _pendingDepositFee - _depositFeeTransferred;
        $._dispatches[msg.sender]._pendingRewardFee = _pendingRewardFee - _rewardFeeTransferred;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IFeeDispatcher
    function pendingDepositFee() public view returns (uint256) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._pendingDepositFee;
    }

    /// @inheritdoc IFeeDispatcher
    function pendingRewardFee() public view returns (uint256) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._pendingRewardFee;
    }

    /// @inheritdoc IFeeDispatcher
    function feeRecipients() public view returns (IFeeDispatcher.FeeRecipient[] memory) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._feeRecipients;
    }

    /// @inheritdoc IFeeDispatcher
    function feeRecipient(address recipient) public view returns (IFeeDispatcher.FeeRecipient memory) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        uint256 _recipientsLength = $._dispatches[msg.sender]._feeRecipients.length;
        for (uint256 i; i < _recipientsLength; i++) {
            if ($._dispatches[msg.sender]._feeRecipients[i].recipient == recipient) {
                return $._dispatches[msg.sender]._feeRecipients[i];
            }
        }
        revert FeeRecipientDoesNotExist(recipient);
    }

    /// @inheritdoc IFeeDispatcher
    function feeRecipientAt(uint256 index) public view returns (IFeeDispatcher.FeeRecipient memory) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._feeRecipients[index];
    }

    /* -------------------------------------------------------------------------- */
    /*                                   SETTERS                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IFeeDispatcher
    function incrementPendingDepositFee(uint256 amount) external {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        $._dispatches[msg.sender]._pendingDepositFee += amount;
        emit DepositFeesCollected(msg.sender, amount);
    }

    /// @inheritdoc IFeeDispatcher
    function incrementPendingRewardFee(uint256 amount) external {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        $._dispatches[msg.sender]._pendingRewardFee += amount;
        emit RewardFeesCollected(msg.sender, amount);
    }

    /// @dev Set the fee recipients.
    ///      The fee recipients must be unique and the total fee splits must be 100 * 10 ** underlyingDecimal (representing 100%).
    /// @param recipients The new fee recipients.
    /// @param underlyingDecimal The number of decimals of the underlying asset.
    function setFeeRecipients(IFeeDispatcher.FeeRecipient[] memory recipients, uint8 underlyingDecimal) external {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();

        if (recipients.length == 0) {
            revert EmptyArray();
        }

        delete $._dispatches[msg.sender]._feeRecipients;

        uint256 _totalDepositFeeSplit;
        uint256 _totalRewardFeeSplit;
        uint256 _recipientsLength = recipients.length;
        for (uint256 i; i < _recipientsLength; i++) {
            _totalDepositFeeSplit += recipients[i].depositFeeSplit;
            _totalRewardFeeSplit += recipients[i].rewardFeeSplit;

            if (recipients[i].recipient == address(0)) {
                revert AddressZero();
            }

            for (uint256 j = i + 1; j < _recipientsLength; j++) {
                if (recipients[i].recipient == recipients[j].recipient) {
                    revert FeeRecipientNotUnique(recipients[i].recipient);
                }
            }
            $._dispatches[msg.sender]._feeRecipients.push(recipients[i]);
        }
        if (_totalDepositFeeSplit != _MAX_PERCENT * 10 ** underlyingDecimal) {
            revert WrongDepositFeeSplit(_totalDepositFeeSplit);
        }
        if (_totalRewardFeeSplit != _MAX_PERCENT * 10 ** underlyingDecimal) {
            revert WrongRewardFeeSplit(_totalRewardFeeSplit);
        }
        emit FeeRecipientsSet(msg.sender, $._dispatches[msg.sender]._feeRecipients);
    }
}
