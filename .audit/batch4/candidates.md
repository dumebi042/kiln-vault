# Batch 4 — Deposit, Withdrawal & Connector Audit Candidates

## Summary

| ID     | Title                                                                  | Classification             |
| ------ | ---------------------------------------------------------------------- | -------------------------- |
| B4-001 | Shares minted before connector deposit                                 | **EXPECTED BEHAVIOR**      |
| B4-002 | Short withdrawal: shares burned for full value, connector returns less | **NEEDS PRODUCTION CHECK** |
| B4-003 | Connector replacement with incompatible market                         | **EXPECTED ADMIN POWER**   |
| B4-004 | Deposit fee idle balance                                               | **EXPECTED BEHAVIOR**      |
| B4-005 | Fee-on-transfer tokens                                                 | **OUT OF SCOPE**           |
| B4-006 | Connector delegatecall storage collision                               | **EXPECTED ADMIN POWER**   |
| B4-007 | swapTarget persistent approval                                         | **EXPECTED ADMIN POWER**   |
| B4-008 | Connector naming collision                                             | **FALSE POSITIVE**         |

---

## B4-001: Shares minted before connector deposit

| Classification | **EXPECTED BEHAVIOR** |
| -------------- | --------------------- |

The Vault calls `safeTransferFrom` (user→vault), then `_mint`, then `connector.delegatecall`. The ERC777 hook occurs during `safeTransferFrom`, BEFORE `_mint`. The `nonReentrant` modifier blocks reentrant state-changing calls. The vault's `_deposit` is called within the user's initial `deposit()` call, which is protected by `nonReentrant`.

---

## B4-002: Short withdrawal — shares burned, connector returns less

| Classification | **NEEDS PRODUCTION CHECK** |
| -------------- | -------------------------- |

### Root Cause

The Vault's `_withdraw` function (Vault.sol L656) burns shares for the FULL requested amount, then transfers only the actual balance increase from the connector:

```solidity
_burn(owner, shares);
uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
_connector.functionDelegateCall(abi.encodeCall(IConnector.withdraw, (IERC20(asset()), assets)));
SafeERC20.safeTransfer(IERC20(asset()), receiver, IERC20(asset()).balanceOf(address(this)) - balanceBefore);
```

If the connector returns less than requested (without reverting), the withdrawing user receives fewer assets while their full shares are already burned. The shortfall is a windfall for remaining shareholders.

### Numerical Proof

**Scenario: Connector returns 50%**

| Metric                                                 | Value                    |
| ------------------------------------------------------ | ------------------------ |
| Alice deposit                                          | 100,000 USDC             |
| Bob deposit                                            | 100,000 USDC             |
| Total assets                                           | 200,000 USDC             |
| Alice previewRedeem (fair value)                       | 100,000 USDC             |
| Alice redeemed (returned by vault.redeem)              | 100,000 USDC (requested) |
| Alice actually received (after connector returned 50%) | **50,000 USDC**          |
| Alice shortfall                                        | **50,000 USDC**          |
| Alice shares after                                     | **0 (burned)**           |
| Bob withdrawable value after                           | 149,999.999999 USDC      |
| Bob windfall from Alice shortfall                      | **49,999.999999 USDC**   |

**Scenario: Connector returns 0%**

| Metric         | Value          |
| -------------- | -------------- |
| Alice received | **0 USDC**     |
| Alice shares   | **0 (burned)** |
| Bob now owns   | ~200,000 USDC  |

### Production Applicability

**This is only exploitable if a production connector can succeed while returning less than the requested withdrawal amount.** Each connector:

- **Aave V3**: `withdraw()` returns actual amount withdrawn. If liquidity is insufficient, Aave reverts. If `amount = type(uint256).max`, Aave withdraws max available (returns actual). **No short return without revert.**
- **Compound V3**: `withdraw()` reverts on insufficient liquidity. **No short return.**
- **MetaMorpho**: ERC4626 `withdraw()` reverts if assets cannot be provided. `maxWithdraw` reflects available liquidity. **No short return.**
- **sDAI/sUSDS**: ERC4626 `withdraw()` guarantees exact DAI/USDS output. **No short return.**
- **Angle**: Same as sDAI/sUSDS. **No short return.**

### Conclusion

The vulnerability is **theoretically valid** (shares burned > assets delivered) but **cannot be triggered by any in-scope production connector**. All connectors either revert on failure or return exactly the requested amount. A malicious connector (requiring CONNECTOR_MANAGER role) could exploit this.

**NEEDS PRODUCTION CHECK**: Verify that no production connector can succeed while returning less than requested. If confirmed impossible for all 6 connectors, reclassify as EXPECTED BEHAVIOR.

---

## B4-003: Connector replacement with incompatible market

| Classification | **EXPECTED ADMIN POWER** |
| -------------- | ------------------------ |

Replacing a connector with one pointing to a different protocol could:

- Leave receipt tokens (aTokens, MetaMorpho shares) in the vault, unreadable by the new connector
- Report zero `totalAssets()` (new connector reads different protocol)
- Prevent withdrawal of old positions

However, this requires CONNECTOR_MANAGER role (admin power). Old receipt tokens remain in the vault and could be recovered by restoring the old connector.

---

## B4-004: Deposit fee idle balance

| Classification | **EXPECTED BEHAVIOR** |

---

## B4-005: Fee-on-transfer tokens

| Classification | **OUT OF SCOPE** |

---

## B4-006: Connector delegatecall storage collision

| Classification | **EXPECTED ADMIN POWER** |

Connectors that use storage state variables would corrupt vault storage during delegatecall. All production connectors use only immutables.

---

## B4-007: swapTarget persistent approval

| Classification | **EXPECTED ADMIN POWER** |

The `reinvest()` functions leave `forceApprove(swapTarget, type(uint256).max)` for the reward token. If swapTarget is compromised, reward tokens can be drained. swapTarget is immutable and controlled during deployment.

---

## B4-008: Connector naming collision

| Classification | **FALSE POSITIVE** |

Normal registry validation — duplicate names revert as expected.
