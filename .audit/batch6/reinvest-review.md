# Reinvest Security Review

## Connectors with Reinvest

- AaveV3Connector (claim → swap → supply)
- CompoundV3Connector (claim COMP → swap → supply)

## Common Pattern

1. Claim rewards via protocol rewards controller
2. `forceApprove(swapTarget, type(uint256).max)` — **persistent unlimited approval**
3. External `swapTarget.functionCall(payload)` — **arbitrary calldata**
4. `forceApprove(aave/comet, received)` — limited to received amount
5. Supply swapped assets

## Risks

| Risk                    | Details                                                                                        |
| ----------------------- | ---------------------------------------------------------------------------------------------- |
| **Unlimited approval**  | swapTarget retains max approval after reinvest. Can drain future reward tokens.                |
| **Arbitrary calldata**  | `payload` from CLAIM_MANAGER. Could instruct swapTarget to transfer assets.                    |
| **No min output check** | If swap returns 0, `received = 0` → `NothingToClaim` revert. But any non-zero amount accepted. |
| **No deadline**         | No swap deadline — transaction can be executed later at worse rate.                            |

## Classification

These are EXPECTED ADMIN POWER — swapTarget is immutable, CLAIM_MANAGER is a privileged role.
