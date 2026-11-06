# Deploying Squeek Odometer through IMD

IMD is asked to audit this repository, deploy the contract on Sepolia and record it. The wallet that pays owns the
IMD project, so pay from the wallet verified on your Squeekchain Genesis profile (an ordinary wallet, not a Safe).

## What it costs

One launch is 0.5 IMD (IMD docs, "Paid actions"). The launch page takes IMD on Ethereum mainnet
(`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, bought on Uniswap, linked from [imd.fun/token](https://imd.fun/token)).
It pays with x402 and Permit2: the wallet signs, IMD's server pays the gas of the transfer, and the wallet needs a little
ETH for a one-time Permit2 approval of IMD. Robinhood Chain (`0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`) is
accepted only through the Intake contract (`0xa43e6f75ee006411f79ac1c84120606c2330de82`, `approve` then `request`),
not through the page. A paid launch can still deploy on Sepolia.

## The launch, on the page

On [explorer.imd.fun/launch](https://explorer.imd.fun/launch): **Contracts**, then **Start from GitHub instead**.

- Your repository: `https://github.com/am3en0x/squeek-odometer` (the page resolves the latest commit on `main`).
- What do the contracts do, and what should launch: the text below.
- Token: **No token**. Chain: **Sepolia**. Owner: leave "The wallet that pays" (the contract has no owner role).
- Connect the Genesis wallet and pay 0.5 IMD.

This is `launch.open` with `onchain: "evm_contracts"` and `chainId: 11155111`. IMD's free `POST /requests/check`
accepted it on 2026-11-07 with no blockers once the steps `audit-imported-code`, `adapt-contract-project` and
`adversarial-review` were named. Its plan: audit the repository as it is, adapt it to launch, tests by another agent, an
audit panel (math, permissions, economics, control flow) and a judge, then deploy on Sepolia.

Text for the page (1,640 characters):

```
Deploy Squeek Odometer from this repository as it is, on Sepolia. One contract: SqueekOdometer (src/SqueekOdometer.sol with src/art/*, src/Types.sol, src/interfaces/ISqueek.sol), constructor arguments as in launch.json, in order: SqueekCore 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4, SqueekNFT 0xC4C7982657f00509548F3a3a41db7FA439a6856B, SqueekStaking 0x50fd1780526C3186A0c037c7622203bC4fb611ca. No token, no pool, no owner role, no initialization call, zero value; the constructor reverts outside Sepolia and makes no external calls.

What it is: a free, fully on-chain dynamic ERC-721 for Squeekchain's Genesis Code Lane. Each token stores SqueekCore's cumulativeWork at mint and renders in tokenURI how far Squeektoshi the hamster has run since (work x 887 mm), his status from the last three settled rounds, a stage with gear at 1/5/10/25/50/100 km, and a water bottle when the owner holds or stakes a Squeek. mint() is free, one per wallet, 9,999 in total; refresh(id) and refreshAll() only emit ERC-4906 events.

Review before deployment, independent and adversarial. Points to check: one mint per wallet and the 9,999 cap; every Squeekchain read is a gas-capped staticcall that copies a fixed number of words (_read), so tokenURI cannot revert for an existing token; no privileged role or payable path exists. Do not change the contract or the art.

Checks: forge build; forge test (37 tests, no network); forge fmt --check src test script; python3 tools/export_abi.py --check. Foundry, solc 0.8.26, cancun, bytecode_hash none, dependencies vendored in lib/. Runtime 23,212 bytes. Details in docs/VALIDATION.md and docs/SECURITY.md.
```

## The site

The contracts launch does not host a site. Two ways after the deploy:

- Write the deployed address and deployment block into `dist/config.js` and serve `dist/` from any static host, for
  example GitHub Pages. Free.
- Or "Add a website" on IMD for another 0.5 IMD, as a site from this repository (`import-site`, `site-content-check`,
  IPFS label `squeek-odometer`). IMD's docs say member sites may be closed (`503 member_sites_closed`).
