# Nemesis — Pass 1: Feynman Full Interrogation

## Phase 0: Nemesis Recon

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 0 — NEMESIS RECON                                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ LANGUAGE: Solidity 0.8.22                                    │
│                                                              │
│ ATTACK GOALS:                                                │
│   1. Drain vault assets by exploiting fee rounding           │
│   2. Force-close user positions permissionlessly             │
│   3. Inflate totalSupply without corresponding assets        │
│   4. Manipulate share price via donation / flash deposit     │
│   5. Bypass pause/blocklist restrictions                     │
│                                                              │
│ NOVEL CODE (highest bug density):                            │
│   - Vault.sol — delegatecall-based connector integration     │
│   - FeeDispatcher.sol — split-based fee distribution math    │
│   - VaultStorage struct — custom ERC-7201 diamond storage    │
│                                                              │
│ VALUE STORES + INITIAL COUPLING HYPOTHESIS:                  │
│   - Vault holds: user deposits (ERC20 tokens)                │
│     Outflows: withdraw, redeem, forceWithdraw                │
│     Coupled: shares[user] ↔ totalSupply, totalAssets ↔      │
│              _lastTotalAssets                                 │
│   - FeeDispatcher tracks: pending deposit/reward fees        │
│     Outflows: dispatchFees (safeTransferFrom)                │
│     Coupled: _pendingDepositFee ↔ split validation total     │
│   - BlockList stores: sanctioned addresses                   │
│     Coupled: blockList ↔ underlying OFAC list                │
│                                                              │
│ COMPLEX PATHS:                                               │
│   - deposit → safeTransferFrom → _mint → delegatecall(conn)  │
│   - collectRewardFees → delegatecall(withdraw) → burn        │
│   - claimAdditionalRewards → delegatecall(claim/reinvest)    │
│                                                              │
│ PRIORITY ORDER:                                              │
│   1. Vault.forceWithdraw — appears in GOALS[2], STORES[1]    │
│   2. FeeDispatcher.dispatchFees — appears in GOALS[1]        │
│   3. Vault._accrueRewardFee — appears in GOALS[3], STORES[1] │
│   4. Vault.collectRewardFees — appears in GOALS[1], PATH[2]  │
│   5. Vault._deposit/_withdraw — appears in PATH[1]           │
└─────────────────────────────────────────────────────────────┘
```

## Phase 1: Dual Mapping

### 1A: Function-State Matrix

| Contract          | Function                   | Reads                                                       | Writes                                                         | Guards                                                               | External Calls                                                                 |
| ----------------- | -------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Vault             | deposit                    | totalAssets, totalSupply, offset, depositFee, blockList     | shares, lastTotalAssets, pendingDepositFee                     | nonReentrant, checkTransferability, notBlocked, whenDepositNotPaused | safeTransferFrom, delegatecall(connector.deposit), delegatecall(feeDispatcher) |
| Vault             | mint                       | same as deposit                                             | same as deposit                                                | same as deposit                                                      | same as deposit                                                                |
| Vault             | withdraw                   | same + allowances                                           | shares, lastTotalAssets                                        | nonReentrant, checkTransferability, notBlocked                       | delegatecall(connector.withdraw), safeTransfer                                 |
| Vault             | redeem                     | same as withdraw                                            | same as withdraw                                               | same as withdraw                                                     | same as withdraw                                                               |
| Vault             | forceWithdraw              | blockList, balances, totalSupply, totalAssets               | shares, lastTotalAssets                                        | nonReentrant                                                         | delegatecall(connector.withdraw), safeTransfer                                 |
| Vault             | collectRewardFees          | totalAssets, lastTotalAssets, collectableRewards, rewardFee | collectableRewardFeesShares, lastTotalAssets, pendingRewardFee | nonReentrant, onlyRole(FEE_COLLECTOR)                                | delegatecall(connector.withdraw), delegatecall(feeDispatcher)                  |
| Vault             | dispatchFees               | feeDispatcher                                               | pendingFees (via feeDispatcher)                                | nonReentrant                                                         | delegatecall(feeDispatcher.dispatchFees)                                       |
| Vault             | claimAdditionalRewards     | additionalRewardsStrategy, totalAssets                      | totalAssets (via reinvest)                                     | nonReentrant, onlyRole(CLAIM_MANAGER)                                | delegatecall(connector.claim/reinvest)                                         |
| Vault             | transfer                   | transferable, blockList                                     | shares                                                         | checkTransferability, notBlocked                                     | —                                                                              |
| Vault             | \_accrueRewardFee          | totalAssets, lastTotalAssets, rewardFee, totalSupply        | shares (mint), collectableRewardFeesShares                     | internal                                                             | —                                                                              |
| FeeDispatcher     | dispatchFees               | pendingDepositFee, pendingRewardFee, recipients             | pendingDepositFee, pendingRewardFee                            | nonReentrant                                                         | safeTransferFrom                                                               |
| FeeDispatcher     | incrementPendingDepositFee | —                                                           | pendingDepositFee                                              | none                                                                 | —                                                                              |
| FeeDispatcher     | setFeeRecipients           | —                                                           | recipients                                                     | none                                                                 | —                                                                              |
| ConnectorRegistry | getOrRevert                | connectorInfo                                               | —                                                              | whenNotPaused, exists                                                | —                                                                              |
| ConnectorRegistry | add/update/remove          | connectorInfo                                               | connectorInfo                                                  | onlyRole(CONNECTOR_MANAGER)                                          | —                                                                              |
| BlockList         | isBlocked                  | underlyingSanctionsList, blockList                          | —                                                              | —                                                                    | underlyingSanctionsList.isSanctioned                                           |
| BlockList         | addToBlockList             | —                                                           | blockList                                                      | onlyRole(OPERATOR)                                                   | —                                                                              |

### 1B: Coupled State Dependency Map

```
┌────────────────────────────┬──────────────────────────────┬──────────────────────────────────────┐
│ State Variable             │ Coupled With                 │ Invariant                            │
├────────────────────────────┼──────────────────────────────┼──────────────────────────────────────┤
│ shares[user] (Vault)       │ totalSupply()                │ Σ shares = totalSupply (ERC20 inv.)  │
│ totalAssets()              │ _lastTotalAssets             │ _lastTotalAssets tracks TVL snapshot │
│ _collectableRewardFeesShares│ _rewardFeeShares (computed) │ Sum of all reward fee shares         │
│ _depositPaused             │ maxDeposit()/maxMint()       │ Paused → deposit/mint return 0       │
│ _pendingDepositFee (FD)    │ Σ feeRecipients[].deposit    │ Total dispatched = pending (ideally)  │
│ _pendingRewardFee (FD)     │ Σ feeRecipients[].reward     │ Total dispatched = pending (ideally)  │
│ connectorInfo[name].addr   │ connectorInfo[name].paused   │ Paused connector blocks getOrRevert  │
│ _blockList[]               │ underlying OFAC sanctions    │ isBlocked() checks both              │
└────────────────────────────┴──────────────────────────────┴──────────────────────────────────────┘
```

### 1C: Cross-Reference — GAPS

| Coupled Pair                                          | Functions Writing A                           | Functions Writing B                                    | Mismatches                                                       |
| ----------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------- |
| shares[user] ↔ totalSupply                            | \_mint, \_burn, \_transfer                    | \_mint, \_burn, \_transfer (OZ)                        | ✅ All covered by ERC20                                          |
| totalAssets ↔ \_lastTotalAssets                       | connector.deposit/withdraw (via delegatecall) | \_deposit, \_withdraw, collectRewardFees, setRewardFee | ❌ GAP: claimAdditionalRewards does NOT update \_lastTotalAssets |
| \_pendingDepositFee ↔ total dispatch                  | incrementPendingDepositFee                    | dispatchFees (decrement)                               | ❌ GAP: rounding leaves dust                                     |
| \_collectableRewardFeesShares ↔ totalSupply           | \_accrueRewardFee (mint + add)                | collectRewardFees (burn + reset)                       | ✅ Covered                                                       |
| connectorInfo[name].addr ↔ connectorInfo[name].frozen | add, update, remove                           | freeze                                                 | ✅ All update paths check frozen                                 |

## Phase 2: Feynman Deep Interrogation

### [FF-001] Vault.forceWithdraw — Q3.1 Guard Consistency Gap

**Lines**: src/Vault.sol:1015-1045
**Guards on function**: `nonReentrant` ONLY

**Q3.1**: If every other sensitive Vault function has `onlyRole()` —

```
collectRewardFees → onlyRole(FEE_COLLECTOR_ROLE)
pauseDeposit     → onlyRole(PAUSER_ROLE)
setFeeRecipients → onlyRole(FEE_MANAGER_ROLE)
setBlockList     → onlyRole(SANCTIONS_MANAGER_ROLE)
```

Why does `forceWithdraw` have NOTHING? It force-closes a user's position!

**Q2.1**: What if `forceWithdraw` is called between a deposit and its connector call?
→ The blocked user's position is closed mid-flow. While atomicity prevents fund loss, the ordering can be abused.

**Q4.1**: What does this assume about the caller?
→ "Only authorized operators will call this" — but there's NO access control.

**Verdict**: **VULNERABLE** — missing caller authorization on core lifecycle function

### [FF-002] FeeDispatcher.dispatchFees — Q5.2 Last Call / Dust Trapping

**Lines**: src/FeeDispatcher.sol:145-167

**Q1.1**: Why does the post-loop subtraction exist?
→ To decrement pending fees by the amount transferred

**Q5.2**: What happens on the LAST dispatch? Can the accumulator reach zero?
→ Each `mulDiv` rounds DOWN, leaving residual. Accumulator approaches zero asymptotically but never reaches it.

**PoC**: `test/PoCTests.t.sol:FeeDispatcherRoundingPoCTest` confirms 1 wei/cycle dust on 50/50 splits, 1660 wei after 1000 cycles.

**Verdict**: **VULNERABLE** — permanent dust trapping in fee accumulator

### [FF-003] Vault.\_accrueRewardFee — Q3.1 Sibling Function Consistency

**Lines**: src/Vault.sol:814-822

**Q3.1**: Why doesn't `_accrueRewardFee` call `_roundDownPartialShares` when:

```
transfer()        → calls _checkPartialShares()     ✓
transferFrom()    → calls _checkPartialShares()     ✓
_previewDeposit() → calls _roundDownPartialShares() ✓
_previewMint()   → calls _roundDownPartialShares() ✓
redeem()         → calls _checkPartialShares()      ✓
_accrueRewardFee → NO alignment                     ✗
```

**PoC**: `OffsetAlignmentPoCTest` confirms shares not aligned to offset (remainder 2,002 for offset=6).

**Verdict**: **VULNERABLE** — reward shares minted without offset alignment

### [FF-004] Vault.\_deposit — Q2.4 Abort Halfway / Late Connector Check

**Lines**: src/Vault.sol:625-647

**Q2.4**: What if the connector paused between `_maxDeposit()` and `getOrRevert()`?
→ Assets transferred, shares minted, then REVERT on paused connector.
→ Solidity atomicity saves all state, but gas is wasted.

**Q7.1**: What if delegatecall to connector.deposit reverts AFTER state change?
→ Atomicity saves state. But the connector has now seen the transfer and mint.

**Verdict**: **HAS_CONCERNS** — gas inefficiency, no fund loss

### [FF-005] Vault.collectRewardFees — Q7.3 Callee State at Call Time

**Lines**: src/Vault.sol:920-942

**Q7.3**: At the point of connector.withdraw (line 935), what state is visible?
→ Total supply includes un-burned reward shares. Assets haven't been withdrawn yet.
→ The connector sees the full vault state before fee shares are burned.

**Q2.1**: What if burn moves BEFORE withdraw?

```
Current: connector.withdraw → incrementPending → BURN
Proposed: BURN → connector.withdraw → incrementPending
```

If burn happens first and withdraw fails → atomic revert, no harm.
If burn happens after withdraw and connector manipulates rate → shares burned != assets withdrawn.

**Verdict**: **HAS_CONCERNS** — dynamic connector rates could cause share/asset mismatch

### [FF-006] Vault.\_accruedRewardFeeShares — Q4.1 Assumption about totalAssets

**Lines**: src/Vault.sol:827-843

**Q4.1**: What does `trySub(newTA, lastTA)` assume?
→ That `newTA >= lastTA` at all times.

**Q5.2**: What if the connector loses value (bad debt, depeg)?
→ `trySub` returns `(false, 0)`. `_reward = 0`. No fee. `_lastTotalAssets` NOT updated.
→ On recovery: yield is calculated from the HIGH watermark, not the actual low.
→ Recovery portion is double-fee'd.

**Verdict**: **VULNERABLE** — high-water mark fee model, double-fee on recovery

### [FF-007] ConnectorRegistry — Q3.2 Asymmetric Pause Behavior

**Lines**: src/ConnectorRegistry.sol

**Q3.2**: Why does `update` work when paused but `remove` doesn't?

```
update(name, addr) → requires: exists + notFrozen + CONNECTOR_MANAGER
remove(name)       → requires: exists + notFrozen + notPaused + CONNECTOR_MANAGER
```

→ A paused connector can be REPLACED (update) but not DELETED (remove)
→ If a connector is paused due to compromise, it can be updated with a fix — makes sense
→ But it can't be removed without unpausing first — potential issue

**Verdict**: **HAS_CONCERNS** — intentional design but asymmetric

---

## Pass 1 SUSPECT List (Feeds to Pass 2)

| ID   | Function                       | Why Suspect                 | Suspect State                 |
| ---- | ------------------------------ | --------------------------- | ----------------------------- |
| S-01 | Vault.forceWithdraw            | No caller access control    | caller identity               |
| S-02 | Vault.\_accrueRewardFee        | No offset alignment on mint | shares % 10^offset            |
| S-03 | Vault.\_accruedRewardFeeShares | trySub returns 0 silently   | \_lastTotalAssets             |
| S-04 | FeeDispatcher.dispatchFees     | Floor rounding leaves dust  | \_pendingDepositFee           |
| S-05 | Vault.collectRewardFees        | Burn after external call    | \_collectableRewardFeesShares |
| S-06 | Vault.\_deposit                | Late connector check        | shares, assets in flight      |
| S-07 | Vault.claimAdditionalRewards   | No \_lastTotalAssets update | \_lastTotalAssets             |
