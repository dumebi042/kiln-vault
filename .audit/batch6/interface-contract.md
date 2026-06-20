# IConnector Interface Contract

## Required Semantics

| Function                                 | Required Behavior                                                                               | Return Value       |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------ |
| `deposit(asset, amount)`                 | Invest `amount` of `asset` into external protocol. Must accept exact amount. Revert on failure. | None               |
| `withdraw(asset, amount)`                | Withdraw `amount` of `asset` from protocol to vault. Must return exact amount or revert.        | None               |
| `totalAssets(asset)`                     | Return total recoverable value of `asset` for `msg.sender` (vault). Must be conservative.       | uint256            |
| `maxDeposit(asset)`                      | Return maximum deposit that will succeed. Must be conservative.                                 | uint256            |
| `maxWithdraw(asset)`                     | Return maximum withdrawable amount. Must be conservative.                                       | uint256            |
| `claim(asset, rewardsAsset, payload)`    | Claim and distribute rewards. Optional (revert if unsupported).                                 | uint256 (received) |
| `reinvest(asset, rewardsAsset, payload)` | Claim and reinvest rewards. Optional (revert if unsupported).                                   | None               |
