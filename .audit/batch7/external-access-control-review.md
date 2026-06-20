# Batch 7 — ExternalAccessControl and SPENDER_ROLE Review

## Function

`ExternalAccessControl` is a shared contract that stores a single `SPENDER_ROLE`. This role is checked by Vault's `_checkTransferability()` when the Vault is in non-transferable mode.

## Logic (`Vault.sol:281-291`)

```solidity
function _checkTransferability(address target) internal view {
    if (
        !_getVaultStorage()._transferable && target != _msgSender()
            && (
                !_externalAccessControl.hasRole(SPENDER_ROLE, _msgSender())
                    && !_externalAccessControl.hasRole(SPENDER_ROLE, target)
            )
    ) {
        revert NotTransferable();
    }
}
```

## Key Properties

| Property                          | Value                                                                     |
| --------------------------------- | ------------------------------------------------------------------------- |
| Checked for sender?               | Yes (`_msgSender()`)                                                      |
| Checked for receiver?             | Yes (`target`)                                                            |
| Checked for operator?             | Yes (in transferFrom via `from` parameter)                                |
| Allowance required?               | **Yes** — SPENDER_ROLE only bypasses transferability, NOT ERC20 allowance |
| Blocklist still checked?          | **Yes** — notBlocked modifiers still apply                                |
| SPENDER can move others' shares?  | Only with allowance                                                       |
| SPENDER can route to non-SPENDER? | **Yes** — if target has SPENDER or Vault is transferable                  |
| Revocation immediate?             | **Yes** — `hasRole` is checked at call time                               |

## Test Results

| Scenario                                              | Result                                   |
| ----------------------------------------------------- | ---------------------------------------- |
| SPENDER transfers own shares (non-transferable vault) | **OK**                                   |
| SPENDER transfers another's shares WITH allowance     | **OK**                                   |
| SPENDER transfers another's shares WITHOUT allowance  | **Reverts** (ERC20InsufficientAllowance) |
| SPENDER sends to blocked address                      | **Reverts** (AddressBlocked)             |
| Non-SPENDER transfers in non-transferable vault       | **Reverts** (NotTransferable)            |
| Revoke SPENDER then transfer                          | **Reverts** (NotTransferable)            |

## Conclusion

SPENDER_ROLE correctly bypasses ONLY the `_transferable` flag. It does NOT bypass allowance, blocklist, or ownership checks.
