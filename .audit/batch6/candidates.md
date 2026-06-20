# Batch 6 — Individual Connector Review Candidates

## Summary

| ID     | Title                                                       | Connector          | Classification           |
| ------ | ----------------------------------------------------------- | ------------------ | ------------------------ |
| B6-001 | swapTarget unlimited approval persists after reinvest       | AaveV3, CompoundV3 | **EXPECTED ADMIN POWER** |
| B6-002 | Reinvest arbitrary calldata to swapTarget                   | AaveV3, CompoundV3 | **EXPECTED ADMIN POWER** |
| B6-003 | MarketRegistry staleness strands positions                  | CompoundV3         | **EXPECTED ADMIN POWER** |
| B6-004 | MetaMorpho withdrawal queue liquidity                       | MetaMorpho         | **EXPECTED BEHAVIOR**    |
| B6-005 | No asset validation in MetaMorpho connector                 | MetaMorpho         | **EXPECTED ADMIN POWER** |
| B6-006 | sDAI/sUSDS rate change between preview and execution        | sDAI, sUSDS        | **EXPECTED BEHAVIOR**    |
| B6-007 | Connector uses only immutable storage (no vault corruption) | All 6              | **EXPECTED BEHAVIOR**    |

**No VALID vulnerabilities found.** All findings are either expected behavior or require admin-level privilege.
