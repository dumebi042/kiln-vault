# N E M E S I S - Verified Findings

Date: 2026-06-19

## Scope

- Language: Solidity / EVM.
- Bounty document read: yes.
- Deployed-source matching requirement: applied before reporting.
- Modules analyzed: `Vault`, `VaultFactory`, `FeeDispatcher`, `BlockList`, `BlockListFactory`, `ExternalAccessControl`.
- Excluded from findings: ConnectorRegistry and connector-specific claims whose deployed source was not proven matched in this run.
- Nemesis loop iterations: 2, then convergence.

## Source Match Boundary

The verified-source boundary used for this report is:

- `extracted/Vault.sol`
- `extracted/VaultFactory.sol`
- `extracted/FeeDispatcher.sol`
- `extracted/BlockList.sol`
- `extracted/BlockListFactory.sol`
- `extracted/ExternalAccessControl.sol`

Earlier deployed-code checks established exact local-body matches for the core contracts available through Sourcify and on-chain proxy/beacon checks. The active Vault beacon implementation differs from the bounty-doc implementation address but was checked to have matching executable logic with only metadata/IPFS suffix differences observed.

## Verification Summary

| ID | Source | Coupled pair / concern | Breaking op | Severity | Verdict |
| --- | --- | --- | --- | --- | --- |
| NM-H01 | Feynman -> State | withdrawal shares vs assets | `Vault.withdraw` | C/H if in scope | False positive for bounty: rounding + known issue |
| NM-H02 | State -> Feynman | reward fee shares vs stored fee shares | `Vault.collectRewardFees` | Medium hypothesis | False positive |
| NM-H03 | Feynman -> State | FeeDispatcher caller bucket vs pending fees | `incrementPending*`, `setFeeRecipients` | Medium hypothesis | False positive |
| NM-H04 | State -> Feynman | `_lastTotalAssets` vs additional rewards | `claimAdditionalRewards` | Medium hypothesis | False positive |
| NM-H05 | State -> Feynman | connector registry vs connector name | `VaultFactory.upgradeVault` | Medium hypothesis | Not eligible: privileged migration/configuration |
| NM-H06 | Feynman | forced exit authorization | `Vault.forceWithdraw` | Medium hypothesis | False positive |

## Verified Findings

No verified, bounty-eligible Critical/High/Medium findings were found in the deployed-source-matched core contracts.

## False Positives Eliminated

### NM-H01: `withdraw` can round required shares to zero

Verdict: false positive for bounty submission.

Evidence:

- `Vault.withdraw` computes shares, checks zero, then rounds down partial shares at `extracted/Vault.sol:515`.
- `_roundDownPartialShares` floors by the offset granularity at `extracted/Vault.sol:798`.
- The arithmetic trace is real under nonzero `_offset`, but the bounty explicitly excludes rounding errors and the partial-share behavior is covered by a prior Sigma Prime DeFi Integrations issue/mitigation discussion.

Do not submit.

### NM-H02: `collectRewardFees` does not mint/burn newly accrued fee shares

Verdict: false positive.

Evidence:

- New fee shares are calculated virtually at `extracted/Vault.sol:864`.
- `_collectable` includes stored plus newly accrued fee shares at `extracted/Vault.sol:866`.
- Only stored fee shares are burned at `extracted/Vault.sol:880` because only stored shares were previously minted to the vault by `_accrueRewardFee` at `extracted/Vault.sol:759`.

Minting then immediately burning the new virtual shares would have no net supply effect for this collection path.

### NM-H03: FeeDispatcher public setters and increments are unguarded

Verdict: false positive.

Evidence:

- FeeDispatcher storage is keyed by `msg.sender` at `extracted/FeeDispatcher.sol:16`.
- Pending fee reads and recipient reads use `msg.sender` at `extracted/FeeDispatcher.sol:99` and `extracted/FeeDispatcher.sol:154`.
- Public increments write only the caller bucket at `extracted/FeeDispatcher.sol:182` and `extracted/FeeDispatcher.sol:189`.
- Dispatch transfers from `msg.sender` to recipients at `extracted/FeeDispatcher.sol:115` and `extracted/FeeDispatcher.sol:127`.

An arbitrary caller can only mutate or dispatch its own bucket, not another vault's pending fees.

### NM-H04: Additional rewards reinvest does not update `_lastTotalAssets`

Verdict: false positive.

Evidence:

- `claimAdditionalRewards` checks that total assets do not decrease and emits the gained amount at `extracted/Vault.sol:899` through `extracted/Vault.sol:931`.
- `_lastTotalAssets` is intentionally used by `_accruedRewardFeeShares` to charge reward fees on positive yield at `extracted/Vault.sol:768`.
- The function comment says additional rewards are considered yield where reward fees can apply at `extracted/Vault.sol:890`.

No unprivileged stale-state exploit was found.

### NM-H05: Registry can change without connector-name revalidation

Verdict: not eligible.

Evidence:

- The registry change path is through factory/vault upgrade logic gated by `DEPLOYER_ROLE` at `extracted/VaultFactory.sol:217`.
- `_setConnectorRegistry` validates code length but not the current connector name at `extracted/Vault.sol:1047`.
- Any harmful outcome requires privileged migration/configuration. The bounty excludes attacks requiring privileged roles.

### NM-H06: `forceWithdraw` is public

Verdict: false positive.

Evidence:

- `forceWithdraw` is public at `extracted/Vault.sol:956`.
- It only proceeds for an internally blocked, not OFAC-sanctioned user at `extracted/Vault.sol:958`.
- It requires the user's full balance to be redeemable at `extracted/Vault.sol:970`.
- Assets are withdrawn to `blockedUser`, not to the caller, at `extracted/Vault.sol:977`.

This is an intended compliance exit path, not a theft or griefing primitive in the matched core.

## Duplicate / Eligibility Notes

- The Krait rounding candidate remains killed.
- No Nemesis finding duplicates a known report because no finding survived verification.
- Connector and ConnectorRegistry ideas were not promoted without deployed-source match evidence.

## Summary

- Verified true positives: 0.
- Final Critical: 0.
- Final High: 0.
- Final Medium: 0.
- Final Low: 0.
