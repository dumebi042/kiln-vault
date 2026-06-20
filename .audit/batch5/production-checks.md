# Batch 5 — Production Checks

## FeeDispatcher

- Implementation: upgradeable via proxy
- State keying: `mapping(address => Dispatch)` by msg.sender
- Verified: vaults are isolated, EOA calls create separate state

## Production Verification Needed

For fee-related findings, verify:

- Network
- Vault address
- FeeDispatcher proxy address
- Current deposit and reward fee settings
- Recipient configuration
- Pending fees
- Vault idle balance vs pending fee backing

## Known Configurations

- Deposit fee: 0–35% (max)
- Reward fee: 0–35% (max)
- Recipients: configured per vault
