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

import {
    AddressNotContract, AlreadyRegistered, ArrayMismatch, EmptyArray, InvalidAsset
} from "../../libraries/Errors.sol";

/// @title Market Registry.
/// @author maximebrugel @ Kiln.
/// @notice List of all markets (cToken, vToken, Comet,...) with their associated underlying asset.
contract MarketRegistry {
    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Mapping of underlying asset to the market address.
    mapping(address => address) internal _markets;

    /// @notice Name of the registry.
    /// @dev Since we are deploying multiple registries (Compound V2, V3, Venus,...), we are exposing a name.
    string public name;

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    constructor(string memory _name, address[] memory _underlyingAssets, address[] memory _marketsAddresses) {
        if (_underlyingAssets.length == 0) revert EmptyArray();
        if (_underlyingAssets.length != _marketsAddresses.length) revert ArrayMismatch();
        for (uint256 i = 0; i < _underlyingAssets.length; i++) {
            address _underlyingAsset = _underlyingAssets[i];
            address _marketAddress = _marketsAddresses[i];

            if (_underlyingAsset.code.length == 0) revert AddressNotContract(_underlyingAsset);
            if (_marketAddress.code.length == 0) revert AddressNotContract(_marketAddress);
            if (_markets[_underlyingAsset] != address(0)) revert AlreadyRegistered(_underlyingAsset);
            _markets[_underlyingAsset] = _marketAddress;
        }
        name = _name;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    VIEWS                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Get the market address for a given asset.
    /// @param asset The underlying asset address.
    function getMarket(address asset) external view returns (address) {
        address _market = _markets[asset];
        if (_market.code.length == 0) revert InvalidAsset(asset);
        return _market;
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC20Metadata.sol)

pragma solidity ^0.8.20;

import {IERC20Metadata} from "../token/ERC20/extensions/IERC20Metadata.sol";

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

/// @dev Represents the maximum percentage value in calculations.
///      This constant is used as a scaling factor for percentage-based computations.
uint256 constant _MAX_PERCENT = 100;

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
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

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";

import {AddressZero, AmountZero, ArrayMismatch, WrongSplit} from "./Errors.sol";
import {_MAX_PERCENT} from "./Constants.sol";

/// @title Multisend library
/// @notice Send token to multiple recipients based on a split.
library MultisendLib {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Send a token to multiple recipients.
    /// @param token The token to send.
    /// @param recipients The array of recipients to send to.
    /// @param splits The split of the token to send to each recipient (%).
    /// @param total The total amount of the token to send.
    function multisend(address token, address[] memory recipients, uint256[] memory splits, uint256 total) internal {
        if (recipients.length != splits.length) revert ArrayMismatch();
        if (total == 0) revert AmountZero();

        uint256 _scaledMaxPercent = _MAX_PERCENT * 10 ** IERC20Metadata(token).decimals();
        uint256 _totalSplit = 0;

        // Check total split
        for (uint256 i; i < splits.length; i++) {
            _totalSplit += splits[i];
        }
        if (_totalSplit != _scaledMaxPercent) revert WrongSplit(_totalSplit);

        // Send tokens
        for (uint256 i; i < recipients.length; i++) {
            address _recipient = recipients[i]; // tmp
            uint256 _split = splits[i]; // tmp
            if (_recipient == address(0)) revert AddressZero();
            if (_split == 0) revert AmountZero();
            IERC20(token).safeTransfer(_recipient, total.mulDiv(_split, _scaledMaxPercent));
        }
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

import {Address} from "@openzeppelin/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, InvalidRewardsAsset, NothingToClaim} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";
import {MarketRegistry} from "./utils/MarketRegistry.sol";
import {MultisendLib} from "../libraries/MultisendLib.sol";

/// @dev Compound interface.
interface IComet {
    function balanceOf(address account) external view returns (uint256);
    function supply(IERC20 asset, uint256 amount) external;
    function withdraw(IERC20 asset, uint256 amount) external;
    function isSupplyPaused() external view returns (bool);
    function isWithdrawPaused() external view returns (bool);
}

/// @title Compound v3 Rewards interface.
/// @notice Hold and claim token rewards
interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;
}

/// @title Compound V3 Connector.
/// @author maximebrugel @ Kiln.
contract CompoundV3Connector is IConnector {
    using Address for address;
    using SafeERC20 for IERC20;
    using MultisendLib for address;

    /// @notice Compound Market Registry address.
    MarketRegistry public immutable compoundMarketRegistry;

    /// @notice Compound V3 comet rewards contract.
    ICometRewards public immutable cometRewards;

    /// @notice Swap Target (aggregator or DEX)
    /// @dev If set to address(0), no swap will be performed
    address public immutable swapTarget;

    /// @notice COMP ERC20 address.
    IERC20 public immutable comp;

    constructor(address _compoundMarketRegistry, address _cometRewards, address _swapTarget, address _comp) {
        if (_cometRewards.code.length == 0) revert AddressNotContract(_cometRewards);
        if (_swapTarget.code.length == 0) revert AddressNotContract(_swapTarget);
        if (_comp.code.length == 0) revert AddressNotContract(_comp);
        if (_compoundMarketRegistry.code.length == 0) revert AddressNotContract(_compoundMarketRegistry);
        cometRewards = ICometRewards(_cometRewards);
        swapTarget = _swapTarget;
        comp = IERC20(_comp);
        compoundMarketRegistry = MarketRegistry(_compoundMarketRegistry);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20 asset) external view returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        return _comet.balanceOf(msg.sender);
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        asset.forceApprove(address(_comet), amount);
        _comet.supply(asset, amount);
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20 asset, uint256 amount) external {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        _comet.withdraw(asset, amount);
    }

    /// @inheritdoc IConnector
    function claim(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override returns (uint256) {
        if (rewardsAsset != comp) revert InvalidRewardsAsset(address(rewardsAsset));

        address _comet = compoundMarketRegistry.getMarket(address(asset));

        // Claim COMP
        uint256 _balanceBefore = rewardsAsset.balanceOf(address(this));
        cometRewards.claim(_comet, address(this), true);
        uint256 _received = rewardsAsset.balanceOf(address(this)) - _balanceBefore;

        if (_received == 0) revert NothingToClaim();

        (address[] memory recipients, uint256[] memory splits) = abi.decode(payload, (address[], uint256[]));
        address(rewardsAsset).multisend(recipients, splits, _received);

        return _received;
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override {
        if (rewardsAsset != comp) revert InvalidRewardsAsset(address(rewardsAsset));

        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        uint256 _balanceBefore = asset.balanceOf(address(this));

        // Claim COMP
        cometRewards.claim(address(_comet), address(this), true);

        // Approve the swap target
        rewardsAsset.forceApprove(address(swapTarget), type(uint256).max);

        // Swap the COMP to the underlying asset
        swapTarget.functionCall(payload);

        uint256 _received = asset.balanceOf(address(this)) - _balanceBefore;
        if (_received == 0) revert NothingToClaim();

        asset.forceApprove(address(_comet), _received);
        _comet.supply(asset, _received);
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20 asset) external view override returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        if (_comet.isSupplyPaused()) return 0;
        return type(uint256).max;
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20 asset) external view override returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        if (_comet.isWithdrawPaused()) return 0;
        return asset.balanceOf(address(_comet));
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/Math.sol)

pragma solidity ^0.8.20;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Muldiv operation overflow.
     */
    error MathOverflowedMulDiv();

    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            return a / b;
        }

        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
     * denominator == 0.
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0 = x * y; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            if (denominator <= prod1) {
                revert MathOverflowedMulDiv();
            }

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";
import {IERC20Permit} from "../extensions/IERC20Permit.sol";
import {Address} from "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev An operation with an ERC20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool))) && address(token).code.length > 0;
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

/* --------------------------------- Common --------------------------------- */

/// @dev Error emitted when the address is zero.
error AddressZero();

/// @dev Error emitted when the address is not a contract.
/// @param addr The address that was attempted to be used as a contract.
error AddressNotContract(address addr);

/// @dev Error emitted when a given amount is zero.
error AmountZero();

/// @dev Error emitted when two array lengths do not match.
error ArrayMismatch();

/// @dev Error emitted when the array is empty.
error EmptyArray();

/// @dev Error emitted when the duration to pause for is invalid
///      (before the current pauseTimestamp).
/// @param timestamp The timestamp to pause for.
error InvalidDuration(uint256 timestamp, uint256 currentTimestamp);

/// @dev Error emitted when the claim function is not available on the connector or
///      no additional rewards to claim at the moment.
error NothingToClaim();

/// @dev Error emitted when the reinvest function is not available on the connector or
///      no additional rewards to compound at the moment.
error NothingToReinvest();

/* ----------------------- VaultUpgradeableBeacon.sol ----------------------- */

/// @dev The `implementation` of the beacon is invalid.
/// @param implementation The address of the implementation that was attempted to be set.
error BeaconInvalidImplementation(address implementation);

/// @dev Error emitted when an operation is attempted on a paused contract.
error isPaused();

/// @dev Error emitted when an operation is attempted on a not paused contract.
error isNotPaused();

/// @dev Error emitted when an operation is attempted on a frozen contract.
error isFrozen();

/* -------------------------------- Vault.sol ------------------------------- */

/// @dev Error emitted when the ERC4626 is not transferable.
error NotTransferable();

/// @dev Error emitted when the deposit fee over 100%.
error WrongDepositFee(uint256 depositFee);

/// @dev Error emitted when the reward fee over 100%.
error WrongRewardFee(uint256 rewardFee);

/// @dev Error emitted when the connector name is invalid (not existing on the registry).
error InvalidConnectorName(bytes32 name);

/// @dev Error emitted when no rewards could be collected.
error NothingToCollect();

/// @dev Error emitted when a call is not a delegate call.
error NotDelegateCall();

/// @dev Error emitted when the preview result is zero (shares or assets).
error PreviewZero();

/// @dev Error emitted when the given address is on the blocklist.
error AddressBlocked(address addr);

/// @dev Error emitted when the total assets decreased.
error TotalAssetsDecreased(uint256 totalAssets, uint256 newTotalAssets);

/// @dev Error emitted when no additional rewards claimed (using the claim function).
error NoAdditionalRewardsClaimed();

/// @dev Error emitted when the deposit is paused.
error DepositPaused();

/// @dev Error emitted when the offset set is too high.
error OffsetTooHigh(uint8 offset);

/// @dev Error emitted when the remainder of transferred shares is not zero.
error RemainderNotZero(uint256 shares);

/// @dev Error emitted when the minimum totalSupply is not met after a deposit.
error MinimumTotalSupplyNotReached();

/// @dev Error emitted when the caller does not have the spender role.
error UnauthorizedSpender();

/// @dev Error emitted when no additional rewards strategy is set.
error NoAdditionalRewardsStrategy();

/// @dev Error emitted when the given address is not only in the internal sanction list.
/// @param addr The address was checked.
error AddressNotInternallySanctionedOnly(address addr);

/// @dev Error emitted when trying to forceWithdraw a user, but there is not enough liquidity.
error InsufficientLiquidity();

/// @dev Error emitted when the vault is not configured for the factory.
error VaultMisconfigured();

/// @dev Error emitted when a confirured factory reserved interaction is attempted by another.
/// @param addr The address attempting to interact.
error NotConfiguredFactory(address addr);

/* --------------------------- ConnectorRegistry.sol ------------------------- */

/// @dev Error emitted when the connector already exists.
/// @param name The name of the connector.
/// @param connector The address of the connector.
error ConnectorAlreadyExists(bytes32 name, address connector);

/// @dev Error emitted when the connector does not exist.
/// @param name The name of the connector.
error ConnectorDoesNotExist(bytes32 name);

/// @dev Error emitted when the connector is frozen.
/// @param name The name of the connector.
error ConnectorFrozen(bytes32 name);

/// @dev Error emitted when the connector is paused.
/// @param name The name of the connector.
error ConnectorPaused(bytes32 name);

/// @dev Error emitted when the connector is not paused.
/// @param name The name of the connector.
error ConnectorNotPaused(bytes32 name);

/* ---------------------------- FeeDispatcher.sol --------------------------- */

/// @dev Error emitted when a given fee recipient does not exist.
/// @param recipient The address of the given fee recipient.
error FeeRecipientDoesNotExist(address recipient);

/// @dev Error emitted when the total deposit fee split between the fee recipients is not 100%.
/// @param totalSplit The total deposit fee split.
error WrongDepositFeeSplit(uint256 totalSplit);

/// @dev Error emitted when the total reward fee split between the fee recipients is not 100%.
/// @param totalSplit The total reward fee split.
error WrongRewardFeeSplit(uint256 totalSplit);

/// @dev Error emitted when a fee recipient address is not unique (in the given array of fee recipients).
/// @param recipient The address of the fee recipient.
error FeeRecipientNotUnique(address recipient);

/* ---------------------------- VaultFactory.sol ---------------------------- */

/// @dev Error emitted when the deployer already exists.
/// @param deployer The address of the deployer.
error DeployerAlreadyExists(address deployer);

/// @dev Error emitted when the caller is not a deployer.
/// @param caller The address of the caller.
error NotDeployer(address caller);

/// @dev Error emitted when the deployer does not exist.
/// @param deployer The address of the deployer.
error InvalidDeployer(address deployer);

/// @dev Error emitted when the index is not matching the Vault address.
/// @param index The index of the Vault.
/// @param vault The address of the Vault.
error InvalidVaultIndex(uint256 index, address vault);

/* ------------------------------ Connector.sol ----------------------------- */

/// @dev Error emitted when the given rewards asset is invalid.
/// @param asset The address of the invalid rewards asset.
error InvalidRewardsAsset(address asset);

/// @dev Error emitted when the given address is an invalid 4626.
/// @param addr The address of the invalid 4626.
error Invalid4626(address addr);

/* --------------------------- VenusConnector.sol --------------------------- */

/// @dev Error emitted when the mint function fails.
error MintFailed();

/// @dev Error emitted when the redeem function fails.
error RedeemFailed();

/* --------------------------- MarketRegistry.sol --------------------------- */

/// @dev Error emitted when the market for a specific asset does not exist.
error InvalidAsset(address asset);

/// @dev Error emitted when an asset is already registered.
/// @param asset The address of the asset.
error AlreadyRegistered(address asset);

/* ----------------------- blockList.sol ----------------------- */

/// @dev Error emitted when the address removed is not blocked.
/// @param addr The address that was attempted to be removed.
error AddressNotBlocked(address addr);

/* ------------------------------ Multisend.sol ----------------------------- */

/// @dev Error emitted when the total split between the recipients is not 100%.
error WrongSplit(uint256 totalSplit);

/* ----------------------------- PauserProxy.sol ---------------------------- */

/// @dev Error emitted when an uint256 value overflows a uint88.
error Uint88Overflow(uint256 value);

/// @dev Error emitted when the caller is not the pauser.
error PauserUnauthorizedAccount(address account);

// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: 2024 Kiln <contact@kiln.fi>
//
// ██╗  ██╗██╗██╗     ███╗   ██╗
// ██║ ██╔╝██║██║     ████╗  ██║
// ██╔═██╗ ██║██║     ██║╚██╗██║
// ██║  ██╗██║███████╗██║ ╚████║
// ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
//
pragma solidity 0.8.22;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/// @title Interface for connectors.
/// @author maximebrugel @ Kiln.
interface IConnector {
    /// @notice Get the total balance (deposit + rewards).
    /// @param asset The asset to get the balance of.
    /// @dev Always called using `.call` (use `msg.sender` and not `address(this)`).
    function totalAssets(IERC20 asset) external view returns (uint256);

    /// @notice Deposit the asset in the underlying protocol.
    /// @param asset The asset to deposit.
    /// @param amount The amount to deposit.
    /// @dev Always called using `.delegatecall` (use `address(this)` and not `msg.sender`).
    function deposit(IERC20 asset, uint256 amount) external;

    /// @notice Withdraw the asset from the underlying protocol.
    /// @param asset The asset to withdraw.
    /// @param amount The amount to withdraw.
    /// @dev Always called using `.delegatecall` (use `address(this)` and not `msg.sender`).
    function withdraw(IERC20 asset, uint256 amount) external;

    /// @notice Claim additional rewards from the underlying protocol and transfer them.
    /// @param asset The vault underlying asset.
    /// @param rewardsAsset The rewards asset to claim.
    function claim(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external returns (uint256);

    /// @notice Claim additional rewards from the underlying protocol and send them back to the vault.
    /// @param asset The vault underlying asset.
    /// @param rewardsAsset The rewards asset to claim.
    function reinvest(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external;

    /// @notice Get the maximum amount that can be deposited.
    /// @param asset The asset to get the maximum deposit amount of.
    function maxDeposit(IERC20 asset) external view returns (uint256);

    /// @notice Get the maximum amount that can be withdrawn (by the vault, not a specific user).
    /// @param asset The asset to get the maximum withdraw amount of.
    function maxWithdraw(IERC20 asset) external view returns (uint256);
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Permit.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * ==== Security Considerations
 *
 * There are two important considerations concerning the use of `permit`. The first is that a valid permit signature
 * expresses an allowance, and it should not be assumed to convey additional meaning. In particular, it should not be
 * considered as an intention to spend the allowance in any specific way. The second is that because permits have
 * built-in replay protection and can be submitted by anyone, they can be frontrun. A protocol that uses permits should
 * take this into consideration and allow a `permit` call to fail. Combining these two aspects, a pattern that may be
 * generally recommended is:
 *
 * ```solidity
 * function doThingWithPermit(..., uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
 *     try token.permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
 *     doThing(..., value);
 * }
 *
 * function doThing(..., uint256 value) public {
 *     token.safeTransferFrom(msg.sender, address(this), value);
 *     ...
 * }
 * ```
 *
 * Observe that: 1) `msg.sender` is used as the owner, leaving no ambiguity as to the signer intent, and 2) the use of
 * `try/catch` allows the permit to fail and makes the code tolerant to frontrunning. (See also
 * {SafeERC20-safeTransferFrom}).
 *
 * Additionally, note that smart contract wallets (such as Argent or Safe) are not able to produce permit signatures, so
 * contracts should have entry points that don't rely on permit.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     * CAUTION: See Security Considerations above.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

