# Web3-DeFi-Yield-Auto-compounding-System

A minimal DeFi system showing a single‑token staking pool (MTN), a wrapped token (wMTN), and an ERC‑4626 vault (aMTN) that auto‑compounds streamed rewards. A `Deposit` contract orchestrates staking, minting, and reward syncing.

## Components
- MTN (`src/MTN.sol`): Mintable ERC20 for demos/tests.
- WMTN (`src/WMTN.sol`): ERC20 with `MINTER_ROLE`/`BURNER_ROLE` via OpenZeppelin AccessControl.
- StakingMTN (`src/StakingMTN.sol`): Single‑token staking of MTN paying MTN rewards over 7 days.
- VaultAutocompound (`src/VaultAutocompound.sol`): ERC‑4626 vault for wMTN; streams rewards and harvests into `totalAssets`.
- Deposit (`src/Deposit.sol`): User entrypoint for staking + routing to wMTN or aMTN; harvests rewards to the vault.

## How It Works
1) Non‑compound deposit
   - User approves `Deposit` to spend MTN.
   - Calls `deposit(receiver, false)`.
   - MTN is staked; wMTN is minted 1:1 to `receiver`.

2) Compound deposit
   - User approves `Deposit` and calls `deposit(receiver, true)`.
   - MTN is staked; wMTN is minted and deposited into the vault; `receiver` receives aMTN shares.

3) Rewards and auto‑compounding
   - An operator funds `StakingMTN` with MTN and calls `notifyRewardAmount(reward)` to start a 7‑day emission.
   - Later, `Deposit.harvest()` claims MTN rewards, re‑stakes them, mints wMTN to the vault, and calls `vault.notifyRewardAmount()`.
   - As time passes, `VaultAutocompound.harvest()` stakes accrued reward into backing, increasing `totalAssets` and aMTN share value.

4) Redeem
   - wMTN holders call `redeem(assets, receiver)` on `Deposit` to burn wMTN and withdraw MTN from staking.

## Wiring & Permissions
- Grant WMTN roles to `Deposit` from the WMTN admin:
  - `grantRole(MINTER_ROLE, Deposit)` and `grantRole(BURNER_ROLE, Deposit)`.
- Set `Deposit` as the vault’s notifier (owner‑only):
  - `vault.setDepositContract(Deposit)`.

## Local Dev
Prerequisites: Foundry (forge/cast) installed.

- Build: `forge build`
- Test (verbose): `forge test -vv`

The included system test (`test/System.t.sol`) covers both deposit modes, redeem, reward funding/streaming, and vault harvest behavior.

## Minimal Usage (Call Flow)
- Non‑compound:
  - `MTN.approve(Deposit, amount)` → `Deposit.deposit(receiver, false)` → receiver gets wMTN.
- Compound:
  - `MTN.approve(Deposit, amount)` → `Deposit.deposit(receiver, true)` → receiver gets aMTN.
- Start rewards (operator):
  - Fund `StakingMTN` with MTN → `StakingMTN.notifyRewardAmount(reward)`.
- Sync + compound rewards:
  - `Deposit.harvest()` → streams to vault → later `VaultAutocompound.harvest()` increases `totalAssets`.
- Redeem MTN from wMTN:
  - `Deposit.redeem(assets, receiver)`.

## Notes
- `Deposit.deposit` consumes the caller’s current MTN allowance as the amount; set exact allowances per call.
- Contracts are for education; hardening (ownership, reentrancy guards, auth) is intentionally minimal.
