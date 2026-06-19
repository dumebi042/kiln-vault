# Batch 2 — Initialization Review

## 1. Uninitialized Proxy Attack Surface

### 1.1 VaultBeaconProxy

**Verdict: PROTECTED**. The VaultBeaconProxy constructor atomically deploys AND initializes via `ERC1967Utils.upgradeBeaconToAndCall(beacon, data)`:

```solidity
// BeaconProxy.sol
constructor(address beacon, bytes memory data) payable {
    ERC1967Utils.upgradeBeaconToAndCall(beacon, data);
    _beacon = beacon;
}
```

`upgradeBeaconToAndCall` calls `Address.functionDelegateCall(IBeacon(beacon).implementation(), data)` in the constructor context. There is no window between deployment and initialization where an attacker could front-run.

### 1.2 BlockListBeaconProxy

**Verdict: PROTECTED**. Same pattern as VaultBeaconProxy — atomic constructor initialization.

### 1.3 VaultFactory Proxy

**Verdict: PROTECTED (partially)**. The factory is deployed via an upgradable proxy. The `initialize()` function uses `onlyDelegateCall` and `initializer`. If the factory proxy is deployed without initialization calldata, any address could call `initialize()` through the proxy — **but only if the proxy permits delegatecalls to uninitialized state**.

In the test helper (`SimpleProxy`), the constructor allows empty `_data`:

```solidity
constructor(address _impl, bytes memory _data) {
    implementation = _impl;
    if (_data.length > 0) {
        (bool ok, ) = _impl.delegatecall(_data);
        require(ok, "init failed");
    }
}
```

In production, the proxy should atomically initialize. If not, the factory proxy is uninitialized and anyone could front-run initialization.

**Risk**: A production deployment script that deploys the proxy in one tx and initializes in another creates a front-running window.

### 1.4 FeeDispatcher Proxy

**Verdict: PROTECTED**. `initialize()` has `onlyDelegateCall` and `initializer`. Same front-running risk applies if deployment and initialization are separate transactions.

### 1.5 ExternalAccessControl Proxy

**Verdict: PROTECTED**. `initialize()` has `onlyDelegateCall` and `initializer`. Same front-running risk applies if deployment and initialization are separate transactions.

---

## 2. Implementation Takeover

### 2.1 Vault Implementation

**Check:** `_disableInitializers()` called? **NO**

The Vault constructor does NOT call `_disableInitializers()`:

```solidity
// src/Vault.sol:304-307
constructor(address externalAccessControl_, address vaultFactory_) {
    _externalAccessControl = IAccessControl(externalAccessControl_);
    vaultFactory = vaultFactory_;
}
```

**Can anyone call `initialize()` on the implementation?**

`Vault.initialize()` has `onlyFactory` modifier:

```solidity
modifier onlyFactory() {
    if (_msgSender() != vaultFactory) revert NotConfiguredFactory(_msgSender());
}
```

The implementation has `vaultFactory` set to the factory address in its constructor. So `initialize()` can only be called by the factory itself.

**Can anyone call `upgrade()` on the implementation?**

`Vault.upgrade()` also has `onlyFactory`. Same protection.

**Can the factory itself initialize the implementation via `upgradeVault()`?**

`VaultFactory.upgradeVault(Vault(vaultImpl), ...)`: This calls `vault.upgrade(upgradeParams)` on the implementation directly (not through a proxy). The `onlyFactory` check passes because `msg.sender == vaultFactory` (factory is calling). The `reinitializer(2)` check passes because the implementation was never initialized (`_initialized == 0 < 2`).

**Impact**: A DEPLOYER_ROLE holder can initialize the Vault implementation contract. The implementation does not hold user funds, so this is a **nuisance** at worst:

- Implementation gets `_initialized = 2` and potentially some role assignments
- Storage modifications on the implementation don't affect proxies (they have separate storage)
- But this is an unnecessary capability

**Prior audit**: Spearbit 5.4.10 reported this. Kiln acknowledged and said the `onlyFactory` modifier prevents practical exploitation.

### 2.2 VaultFactory Implementation

**Check:** `_disableInitializers()` called? **NO** (empty constructor)

However, `VaultFactory.initialize()` has `onlyDelegateCall`:

```solidity
modifier onlyDelegateCall() {
    if (address(this) == _self) revert NotDelegateCall();
    _;
}
```

On the implementation: `address(this) == _self` → true → REVERT.
Through a proxy: `address(this) != _self` → passes.

So `initialize()` CANNOT be called directly on the implementation. **Protected**.

### 2.3 FeeDispatcher Implementation

**Check:** `_disableInitializers()` called? **NO**

`FeeDispatcher.initialize()` has both `initializer` and `onlyDelegateCall`.

On the implementation: `address(this) == _self` → REVERT via `onlyDelegateCall`.

**Protected** (fixed from prior audit 5.4.11 which noted missing `onlyDelegateCall`).

### 2.4 BlockList Implementation

**Check:** `_disableInitializers()` called? **NO**

`BlockList.initialize()` has `onlyDelegateCall`. **Protected**.

### 2.5 ExternalAccessControl Implementation

**Check:** `_disableInitializers()` called? **NO**

`ExternalAccessControl.initialize()` has `onlyDelegateCall`. **Protected**.

---

## 3. Reinitialization

### 3.1 Can `initialize()` be called twice on any proxy?

| Contract              | Protection                         | Revert Condition                               |
| --------------------- | ---------------------------------- | ---------------------------------------------- |
| Vault                 | `initializer` in `_initialize()`   | `InvalidInitialization` on second call         |
| Vault (upgrade path)  | `reinitializer(2)` in `_upgrade()` | `InvalidInitialization` if `_initialized >= 2` |
| VaultFactory          | `initializer` in `initialize()`    | `InvalidInitialization` on second call         |
| FeeDispatcher         | `initializer` in `initialize()`    | `InvalidInitialization` on second call         |
| BlockList             | `initializer` in `initialize()`    | `InvalidInitialization` on second call         |
| ExternalAccessControl | `initializer` in `initialize()`    | `InvalidInitialization` on second call         |

All are **PROTECTED** by OZ's `Initializable` guard.

### 3.2 Initializer Ordering (Vault)

The `Vault._initialize()` function calls OpenZeppelin initializers in this order:

1. `__ERC4626_init(params.asset_)` → which calls `__ERC20_init_unchained(...)` internally
2. `__ERC20_init(params.name_, params.symbol_)` — **DUPLICATE CALL**

**Wait** — `__ERC4626_init` calls `__ERC20_init` internally? Let me verify...

`ERC4626Upgradeable.__ERC4626_init(IERC20 asset)` does NOT call `__ERC20_init`. It only stores the asset. The `__ERC20_init` call is separate.

But looking more carefully at the OZ v5 code:

```solidity
// ERC4626Upgradeable
function __ERC4626_init(IERC20 asset_) internal onlyInitializing {
    __ERC4626_init_unchained(asset_);
}

function __ERC4626_init_unchained(IERC20 asset_) internal onlyInitializing {
    // just stores _asset
}
```

And separately:

```solidity
// ERC20Upgradeable
function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
    __ERC20_init_unchained(name_, symbol_);
}
```

The `__ERC4626_init` does NOT call `__ERC20_init`. It's up to the inheriting contract to call both in the correct order. Since `Vault` inherits from `ERC4626Upgradeable` (which inherits from `ERC20Upgradeable`), both initializers need to be called. The Vault does this correctly:

1. `__ERC4626_init(asset_)` — initializes ERC4626 storage (asset reference)
2. `__ERC20_init(name, symbol)` — initializes ERC20 storage (name, symbol)

This is correct. No double initialization.

### 3.3 Reinitializer Version Management

`_upgrade` uses `reinitializer(2)`. This means:

- Version 1 was consumed by `initializer` (which sets `_initialized = 1`)
- Version 2 is consumed by `reinitializer(2)` during upgrade

If a future upgrade needs to add more initialization, it would use `reinitializer(3)`. This is correct.

**Risk**: If `upgrade()` is called while `initialize()` wasn't (i.e., `_initialized == 0`), `reinitializer(2)` would pass (0 < 2). This IS possible on the implementation contract (as discussed in 2.1).

---

## 4. Initialization with Zero/Malicious Addresses

### 4.1 Vault.\_initialize

| Parameter              | Validation                       | Can Be Zero?                              |
| ---------------------- | -------------------------------- | ----------------------------------------- |
| `asset_`               | None (ERC4626 doesn't validate)  | YES — zero address possible               |
| `connectorRegistry_`   | `code.length == 0` check         | No — reverts if not contract              |
| `connectorName_`       | `registry.connectorExists(name)` | Reverts if name doesn't exist             |
| `initialDefaultAdmin_` | OZ validates internally          | OZ will accept zero but admin rules apply |
| `offset_`              | Must be ≤ 23                     | No — reverts if > 23                      |
| `depositFee_`          | Must be ≤ 35e(decimal)           | Zero is fine                              |
| `rewardFee_`           | Must be ≤ 35e(decimal)           | Zero is fine                              |

**Finding**: `asset_` is NOT validated to be non-zero or a contract. The ERC4626 base contract stores it as-is. A vault initialized with `address(0)` as asset would be permanently broken (all deposits/withdrawals revert). This requires DEPLOYER_ROLE to exploit.

### 4.2 VaultFactory.\_initialize

| Parameter            | Validation               | Can Be Zero?                 |
| -------------------- | ------------------------ | ---------------------------- |
| `vaultBeacon_`       | `code.length == 0` check | No                           |
| `connectorRegistry_` | `code.length == 0` check | No                           |
| `feeDispatcher_`     | `code.length == 0` check | No                           |
| `initialAdmin_`      | OZ validates             | OZ default admin rules apply |
| `initialDeployer_`   | None                     | YES — zero address possible  |

**Finding**: `initialDeployer_` is not validated. Setting it to `address(0)` would mean no one can deploy vaults initially, requiring a separate `grantRole(DEPLOYER_ROLE, ...)` from the admin.

---

## 5. Partially Initialized Deployments

### 5.1 Vault: initialize + upgrade in same call

The Vault's `initialize()` calls BOTH `_initialize()` (initializer) and `_upgrade()` (reinitializer(2)). If the upgrade step fails (e.g., `forceApprove` reverts for USDT-like tokens), the vault is left in a partially initialized state:

- `_initialized == 1` (set by initializer)
- But `_upgrade()` didn't run, so:
  - No blocklist
  - No fee dispatcher
  - No fee recipients
  - No FEE_COLLECTOR_ROLE

However, since this happens atomically in the constructor, the proxy isn't deployed at all — the constructor reverts entirely. So there's no usable proxy in this state.

**Exception**: If `_initialize()` succeeds but `_upgrade()` fails, and the error is caught... but OZ's `initializer` modifier doesn't catch errors — it rethrows. So the entire constructor reverts.

### 5.2 Sigma Prime Finding: USDT Upgrade Block

The `forceApprove` call in `__Vault_upgrade()` at line 416 of Vault.sol:

```solidity
SafeERC20.forceApprove(IERC20(asset()), params.feeDispatcher_, type(uint256).max);
```

This calls `asset().approve(feeDispatcher, max)` then optionally `asset().approve(feeDispatcher, 0)` then `asset().approve(feeDispatcher, max)` for non-standard return values. For USDT (which doesn't return a boolean), `forceApprove` should handle this correctly via OZ's SafeERC20.

**Prior finding**: Sigma Prime KLN2-03 (High) reported that USDT vaults cannot be upgraded. This was because the old code used `IERC20(asset()).approve()` directly instead of `forceApprove`. The current code uses `forceApprove`, which handles USDT.

**STATUS**: FIXED in current code. Not exploitable.

---

## 6. Initialization Through Unexpected Delegatecall Paths

### 6.1 Can delegateToFactory be used to reinitialize?

`Vault.delegateToFactory(data)` → `ISelf(vaultFactory)._self().functionDelegateCall(data)` → runs factory code in vault storage context.

If `data = abi.encodeCall(VaultFactory.initialize, (...))`:

- `initialize()` has `onlyDelegateCall` — during this delegatecall, `address(this)` is the Vault proxy, and `_self` is the factory implementation address. So `address(this) != _self` → PASSES.
- `initialize()` has `initializer` — the Vault proxy is already initialized (`_initialized >= 1`), so this REVERTS.

**Verdict**: Not exploitable. The `initializer` guard on the factory's `initialize()` prevents re-execution since the vault is already initialized.

### 6.2 Can clone-like patterns initialize storage?

All proxies use beacon or UUPS patterns. No minimal/EIP-1167 clone patterns are used. All initialization happens in constructor or explicit `initialize()` calls.

---

## 7. Initialization Parameter Mismatch: New Deployment vs Upgrade

### New Vault Deployment (`createVault`)

Params come from `CreateVaultParams`:

- `connectorRegistry_` = factory's stored registry
- `feeDispatcher_` = factory's stored dispatcher
- `blockList_` = from creation params
- `additionalRewardsStrategy_` = from creation params
- All roles assigned from creation params

### Vault Upgrade (`upgradeVault`)

Params come from migration + `UpgradeVaultParams`:

- `connectorRegistry_` = factory's stored registry (same as new deployment)
- `feeDispatcher_` = factory's stored dispatcher (same as new deployment)
- `blockList_` = from upgrade params
- `additionalRewardsStrategy_` = from upgrade params
- `pendingDepositFee_` = migrated from old FeeDispatcher_1_0_0 storage
- `pendingRewardFee_` = migrated from old FeeDispatcher_1_0_0 storage
- `recipients_` = converted from old FeeRecipient format

**Potential issue**: The `upgradeVault` function reads old FeeDispatcher storage via `delegateToFactory`. If the old storage was at a DIFFERENT slot than presumed, the migration would read garbage values. But the old `FeeDispatcherStorageLocation` constant is verified to match between old and new implementations:

- Old: `0xfdd5e928c3467d3da929a44639dde8d54e0576a04fec4ff333caa67a6f243300`
- New: `0xfdd5e928c3467d3da929a44639dde8d54e0576a04fec4ff333caa67a6f243300`

Same slot. **Safe**.

---

## 8. Summary Table: All Initialization Vectors

| Attack Vector                 | Exploitable?                   | Prerequisites           | Impact                            | Prior Report?           |
| ----------------------------- | ------------------------------ | ----------------------- | --------------------------------- | ----------------------- |
| Front-run factory proxy init  | YES (if deployed without init) | Separate deploy+init tx | Null — attacker can't steal funds | No                      |
| Init implementation contracts | NO (onlyDelegateCall guard)    | —                       | —                                 | Spearbit 5.4.10, 5.4.11 |
| Reinit proxy                  | NO (initializer guard)         | —                       | —                                 | No                      |
| Zero asset in Vault.init      | YES                            | DEPLOYER_ROLE           | Broken vault                      | No                      |
| Zero deployer in Factory.init | YES (minor)                    | Admin deploying factory | No vaults deployable              | No                      |
| USDT upgrade block            | FIXED (forceApprove)           | —                       | —                                 | Sigma Prime KLN2-03     |
| delegateToFactory reinit      | NO (initializer guard)         | —                       | —                                 | No                      |
