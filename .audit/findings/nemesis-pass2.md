# Nemesis — Pass 2: State Inconsistency (Enriched by Pass 1)

## Enrichment from Pass 1

Pass 1 suspects integrated as extra state audit targets:

| Pass-1 Suspect                | Enriched State Audit Questions                                          |
| ----------------------------- | ----------------------------------------------------------------------- |
| S-01 forceWithdraw            | What state does forceWithdraw modify? Does it update ALL coupled state? |
| S-02 \_accrueRewardFee        | Does the offset violation affect totalSupply coupled pairs?             |
| S-03 \_accruedRewardFeeShares | Does trySub leaving lastTotalAssets stale create state desync?          |
| S-04 dispatchFees             | Does rounding dust affect the pending/strict invariant?                 |
| S-05 collectRewardFees        | Does burn-after-call create a state window?                             |
| S-07 claimAdditionalRewards   | Is lastTotalAssets coupled with connector TVL? Is it updated?           |

## Coupled State Dependency Map (Enriched)

```
┌────────────────────────────┬──────────────────────────────┬──────────────────────────────────────┐
│ State Variable             │ Coupled With                 │ Invariant                            │
├────────────────────────────┼──────────────────────────────┼──────────────────────────────────────┤
│ shares[user] (Vault)       │ totalSupply()                │ Σ shares = totalSupply (ERC20 inv.)  │
│ totalAssets()              │ _lastTotalAssets             │ Stale capture of TVL snapshot        │
│ _collectableRewardFeesShares│ _rewardFeeShares (computed) │ Sum of all reward fee shares         │
│ _depositPaused             │ maxDeposit()/maxMint()       │ Paused → returns 0                   │
│ _pendingDepositFee (FD)    │ vault.balanceOf(asset)       │ Fee must be backed by assets         │
│ _pendingRewardFee (FD)     │ vault.balanceOf(asset)       │ Fee must be backed by assets         │
│ _pendingDepositFee         │ recipient split sum          │ 100% = Σ splits (dispatch rounding)  │
│ _pendingRewardFee          │ recipient split sum          │ 100% = Σ splits (dispatch rounding)  │
│ _blockList[]               │ underlying OFAC sanctions    │ isBlocked checks both lists          │
│ connectorInfo[name].addr   │ connectorInfo[name].frozen   │ Frozen blocks update/remove          │
│ connectorInfo[name].addr   │ connectorInfo[name].pause    │ Paused blocks getOrRevert            │
├────────────────────────────┴──────────────────────────────┴──────────────────────────────────────┤
│ NEW pairs discovered via Pass 1 Feynman:                                                         │
├────────────────────────────┬──────────────────────────────┬──────────────────────────────────────┤
│ _offset                    │ totalSupply % 10^offset      │ Total supply must be aligned         │
│ _lastTotalAssets           │ future reward fee calc       │ Stale lastTA = wrong fee on yield    │
│ _collectableRewardFeesShares│ collectRewardFees burn      │ Shares burned must match minted      │
│ _feeDispatcher approval    │ vault asset balance          │ Approval must be sufficient          │
└────────────────────────────┴──────────────────────────────┴──────────────────────────────────────┘
```

## Mutation Matrix (Enriched)

### `_lastTotalAssets` — ALL mutation paths:

| Function                            | Effect                                    | Coupled Update?     |
| ----------------------------------- | ----------------------------------------- | ------------------- |
| `_deposit()`                        | Set to `totalAssets()` after delegatecall | ✅ Correct          |
| `_withdraw()`                       | Set to `totalAssets()` after delegatecall | ✅ Correct          |
| `collectRewardFees()`               | Set to `totalAssets()` after burn         | ✅ Correct          |
| `setRewardFee()`                    | Set to `_accrueRewardFee()` result        | ✅ Correct          |
| `claimAdditionalRewards()` Claim    | ❌ NOT updated                            | ❌ GAP              |
| `claimAdditionalRewards()` Reinvest | ❌ NOT updated                            | ❌ GAP              |
| `totalAssets()` decrease (external) | NOT updated (no mutation)                 | ❌ trySub returns 0 |

### `_collectableRewardFeesShares` — ALL mutation paths:

| Function              | Effect                         | Coupled Update? |
| --------------------- | ------------------------------ | --------------- |
| `_accrueRewardFee()`  | Incremented by rewardFeeShares | ✅              |
| `collectRewardFees()` | Reset to 0 after burn          | ✅              |

### `_pendingDepositFee[_pendingRewardFee]` — ALL mutation paths:

| Function                       | Effect                     | Coupled Update?             |
| ------------------------------ | -------------------------- | --------------------------- |
| `incrementPendingDepositFee()` | Added to (vault-scoped)    | ✅ (but no access control)  |
| `incrementPendingRewardFee()`  | Added to (vault-scoped)    | ✅ (but no access control)  |
| `dispatchFees()`               | Decremented by transferred | ❌ Rounding leaves residual |

## Desync Findings

### STATE-001: claimAdditionalRewards does NOT update \_lastTotalAssets (cross-feed from S-07)

**Coupled Pair**: `_lastTotalAssets` ↔ `totalAssets()` from connector
**Breaking Operation**: `claimAdditionalRewards()` — both Claim and Reinvest strategies
**Lines**: src/Vault.sol:952-994

**Enrichment from Feynman S-07**: "Why doesn't CLAIM_MANAGER update lastTotalAssets? The function reads totalAssets before and after. It has the data. It just doesn't save it."

**Scenario** (Claim strategy):

1. CLAIM_MANAGER claims reward tokens → totalAssets unchanged
2. \_lastTotalAssets is stale, but since Claim doesn't affect totalAssets → no desync

**Scenario** (Reinvest strategy):

1. CLAIM_MANAGER reinvests rewards → reward tokens swapped to asset → supplied to protocol
2. totalAssets INCREASES (reinvested rewards are now in protocol)
3. \_lastTotalAssets NOT updated
4. Next deposit/withdraw → \_accrueRewardFee() computes reward fee on total yield including reinvested amount
5. ✅ This is CORRECT — reward fee SHOULD capture all yield

**Verdict**: **FALSE POSITIVE** (GATE C — Intentional Design): The reward fee IS supposed to capture reinvested yield

### STATE-002: dispatchFees rounding dust (cross-feed from S-04)

**Coupled Pair**: `_pendingDepositFee` ↔ sum of dispatches to recipients
**Breaking Operation**: `dispatchFees()` — each cycle leaves residual

**Enrichment from Feynman Q5.2**: "What happens on the LAST dispatch? Can the accumulator drain to zero?"
→ No. mulDiv Floor rounding means the accumulator approaches 0 asymptotically.

**PoC Confirmed**: 1660 wei trapped after 1000 cycles with 3 recipients.

**Verdict**: **TRUE POSITIVE** — LOW (economically bounded)

### STATE-003: \_accruedRewardFeeShares high-water mark (cross-feed from S-03)

**Coupled Pair**: `_lastTotalAssets` ↔ computed reward fee
**Breaking Operation**: No operation reduces `_lastTotalAssets` on value decrease

**Scenario**:

1. totalAssets = 1,000,000 USDC, \_lastTotalAssets = 1,000,000
2. Connector suffers loss: totalAssets = 950,000
3. \_accruedRewardFeeShares(): trySub(950,000, 1,000,000) = (false, 0). \_reward = 0. No fee. lastTA = 1,000,000 (unchanged)
4. Depositor adds 100,000 → \_accrueRewardFee() called
5. reward = totalAssets() - lastTA = 1,050,000 - 1,000,000 = 50,000
6. Reward fee minted on 50,000 of "yield" — but 50,000 of that is recovery from the loss, not new yield

**Verdict**: **TRUE POSITIVE** — LOW (requires connector loss event)

### STATE-004: \_collectableRewardFeesShares + \_rewardFeeShares in collectRewardFees (cross-feed from S-05)

**Coupled Pair**: `_collectableRewardFeesShares` ↔ shares burned in collectRewardFees
**Breaking Operation**: `collectRewardFees()`

**Scenario**:

```
collectRewardFees():
1. (R', newTA) = _accruedRewardFeeShares()  ← R' is UNMINTED view-only shares
2. collectable = convertToAssets(C + R', Floor, newTA, supply + R')
   → Uses unminted R' in numerator AND denominator
3. connector.withdraw(asset, collectable)
4. incrementPendingRewardFee(actualReceived)
5. _burn(address(this), C)     ← burns only PREVIOUSLY minted shares
6. C = 0
```

If C = 0 and R' > 0:

- 5 burns 0 shares
- R' shares were NEVER minted
- The asset value of R' was withdrawn and sent to FeeDispatcher
- R' shares don't exist in totalSupply → they can't be burned later
- When the next yield cycle mints R'' shares, C only tracks R'', not R'

**Cross-feed from Feynman Q7.3**: "At the point of connector.withdraw, what state does the connector see?"
→ The connector sees full supply (no burn yet), but compute was done with virtual supply + R'

**Verdict**: **TRUE POSITIVE** — MEDIUM (share price distortion), needs PoC verification

---

## Pass 2 State Gaps (Feeds to Pass 3 — Feynman Re-interrogation)

| Gap  | Description                                                          | Source |
| ---- | -------------------------------------------------------------------- | ------ |
| G-01 | \_lastTotalAssets not updated on value loss                          | S-03   |
| G-02 | dispatchFees rounding dust permanently stuck                         | S-04   |
| G-03 | collectRewardFees: unminted R' used in conversion, not minted/burned | S-05   |
| G-04 | fee recipients reconfiguration redistributes pending fees            | New    |
| G-05 | FeeDispatcher functions have no access control (msg.sender-scoped)   | New    |
