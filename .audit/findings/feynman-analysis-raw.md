# Feynman Audit — Raw Findings (Pre-Verification)

## Phase 0: Attacker's Hit List

```
┌─────────────────────────────────────────────────────┐
│ PHASE 0 — ATTACKER'S HIT LIST                       │
├─────────────────────────────────────────────────────┤
│                                                      │
│ LANGUAGE: Solidity 0.8.22                            │
│                                                      │
│ ATTACK GOALS:                                        │
│   1. Drain vault assets by manipulating fee system   │
│   2. Force-close user positions (griefing)           │
│   3. Inflate fee accumulator to steal yield          │
│   4. Break share price invariant via rounding        │
│                                                      │
│ NOVEL CODE:                                          │
│   - Vault.sol: delegatecall-based connector pattern  │
│   - FeeDispatcher.sol: split-based fee distribution  │
│   - Vault.sol: custom offset-based inflation defense │
│                                                      │
│ VALUE STORES:                                        │
│   - Vault holds: user deposits (ERC20), shares       │
│   - FeeDispatcher tracks: pending fee accumulators   │
│   - ConnectorRegistry holds: connector addresses     │
│                                                      │
│ COMPLEX PATHS:                                       │
│   - deposit → connector deposit via delegatecall     │
│   - collectRewardFees → connector withdraw → burn    │
│   - FeeDispatcher dispatch loop with mulDiv rounding │
│                                                      │
│ PRIORITY ORDER:                                      │
│   1. forceWithdraw — any caller, no access control   │
│   2. FeeDispatcher rounding — dust accumulation      │
│   3. _accrueRewardFee offset alignment               │
│   4. collectRewardFees share burn sequence            │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## Phase 1: Function-State Matrix

See [detector-candidates.md](detector-candidates.md) for full matrix.

## Phase 2: Deep Function Interrogation

### FF-001: forceWithdraw — Q3.1 Guard Consistency

```
FUNCTION: Vault.forceWithdraw
Visibility: public
Guards: nonReentrant ONLY
State reads: _blockList, balances, totalSupply, totalAssets, _feeDispatcher
State writes: _burn, _withdraw, _lastTotalAssets

Q1.1: Why does this function exist?
→ To force-withdraw a sanctioned/blocked user from the vault.
→ The user's funds go to THEMSELVES, not the caller.

Q3.1: Why does forceWithdraw have NO onlyRole() when:
  - collectRewardFees has onlyRole(FEE_COLLECTOR_ROLE)
  - pauseDeposit has onlyRole(PAUSER_ROLE)
  - setFeeRecipients has onlyRole(FEE_MANAGER_ROLE)
  - setBlockList has onlyRole(SANCTIONS_MANAGER_ROLE)
→ This is an access control gap. Every other sensitive function guards the caller.

VERDICT: VULNERABLE — missing caller authorization
```

### FF-002: FeeDispatcher.dispatchFees — Q5.2 Draining

```
FUNCTION: FeeDispatcher.dispatchFees
Guards: nonReentrant ONLY
State writes: _pendingDepositFee, _pendingRewardFee (decrement)

Q1.1: Why does the post-loop subtraction exist?
→ _pendingDepositFee - _depositFeeTransferred is the remainder after distribution

Q1.2: What if I delete the subtraction?
→ pending fees are never decremented → double-spending of fees

Q5.2: What happens on the LAST dispatch?
→ Integer division rounding leaves dust that can never reach zero
→ Dust stays in accumulator permanently: _pendingDepositFee > 0 forever

VERDICT: VULNERABLE — permanent dust trapping
```

### FF-003: \_accrueRewardFee — Q3.1 Sibling Consistency

```
FUNCTION: Vault._accrueRewardFee
Calls: _convertToShares (internal), _mint (internal)

Q3.1: Why does _accrueRewardFee NOT call _roundDownPartialShares when:
  - transfer() calls _checkPartialShares (line 878)
  - transferFrom() calls _checkPartialShares (line 893)
  - _previewDeposit calls _roundDownPartialShares (line 742)
  - _previewMint calls _roundDownPartialShares (line 784)
  - redeem() calls _checkPartialShares (line 593)

→ All user-facing functions enforce offset alignment
→ _accrueRewardFee mints shares WITHOUT alignment

VERDICT: VULNERABLE — shares can be misaligned to offset
```

### FF-004: collectRewardFees — Q2.1 Ordering (CEI)

```
FUNCTION: Vault.collectRewardFees
LINE-BY-LINE:

L926-930: _convertToAssets(collectable + newShares, Floor, newTA, supply + newShares)
  → Computes asset value using virtual total supply

L933: balanceBefore = balanceOf(this)

L935: connector.withdraw(asset, collectable) via delegatecall
  → STATE: assets leave connector, arrive in vault

L937: feeDispatcher.incrementPendingRewardFee(actualReceived)
  → STATE: pending reward fees updated

L939: _burn(address(this), _collectableRewardFeesShares)
  → STATE: reward shares burned

Q2.1: What if burn happens BEFORE the withdraw?
→ If shares are burned before withdrawal fails → no funds lost (atomic revert)

Q2.2: What if burn happens AFTER incrementPendingRewardFee?
→ This is the actual order. is this correct?
→ Shares are BURNED after the FeeDispatcher call

VERDICT: HAS_CONCERNS — burn happens late, but protected by nonReentrant
```

### FF-005: \_accruedRewardFeeShares — Q4.1 Assumption about totalAssets

```
FUNCTION: Vault._accruedRewardFeeShares (VIEW)

L831: (, uint256 _reward) = newTotalAssets.trySub($._lastTotalAssets);

Q4.1: What does this assume about totalAssets?
→ That it has increased since _lastTotalAssets was set
→ trySub returns (false, 0) when newTA < lastTA
→ _reward = 0 → NO fee accrued

Q5.2: What happens after repeated losses?
→ lastTotalAssets stays at the ATH
→ Recovery yield up to the ATH generates NO fee
→ _lastTotalAssets is never reduced during losses

VERDICT: HAS_CONCERNS — high-water mark behavior, double-fee risk on recovery
```

### FF-006: FeeDispatcher.setFeeRecipients — Q5.3 Double call

```
FUNCTION: FeeDispatcher.setFeeRecipients

L239: delete $._dispatches[msg.sender]._feeRecipients;

Q5.3: What if called twice rapidly?
→ Old recipients deleted, pending fees stay
→ New recipients get old pending fees with new split ratios
→ Old recipients lose their share of already-accrued fees

VERDICT: HAS_CONCERNS — pending fees redistributed on reconfiguration
```

### FF-007: Vault.\_deposit — Q2.4 Abort halfway

```
FUNCTION: Vault._deposit
ORDER:
1. safeTransferFrom(caller, vault, assets)  ← external call, assets moved
2. _mint(receiver, shares)                   ← state change
3. Check minTotalSupply                      ← validation
4. getOrRevert(connectorName)                ← can revert if paused!
5. connector.deposit via delegatecall         ← external call
6. _lastTotalAssets = totalAssets()           ← state write

Q2.4: What if getOrRevert() reverts at step 4?
→ Assets already transferred (step 1)
→ Shares already minted (step 2)
→ BUT: Solidity atomicity reverts EVERYTHING — no fund loss
→ Gas wasted, but safe

VERDICT: HAS_CONCERNS — gas inefficiency on connector pause
```

## Raw Finding Summary

| ID     | Severity | Description                                               | Verification Status |
| ------ | -------- | --------------------------------------------------------- | ------------------- |
| FF-001 | MEDIUM   | forceWithdraw missing caller authorization                | PoC DONE            |
| FF-002 | LOW      | FeeDispatcher rounding dust accumulation                  | PoC DONE            |
| FF-003 | LOW      | Reward shares not aligned to offset                       | PoC DONE            |
| FF-004 | LOW      | collectRewardFees CEI ordering concern                    | UNVERIFIED          |
| FF-005 | LOW      | \_accruedRewardFeeShares high-water mark                  | UNVERIFIED          |
| FF-006 | LOW      | Fee recipients reconfiguration redistributes pending fees | UNVERIFIED          |
| FF-007 | LOW      | \_deposit gas waste on connector pause                    | UNVERIFIED          |
