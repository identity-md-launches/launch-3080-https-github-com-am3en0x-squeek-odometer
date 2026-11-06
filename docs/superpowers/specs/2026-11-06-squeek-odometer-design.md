# Squeek Odometer — design

A free, fully on-chain, dynamic ERC-721 on Ethereum Sepolia for the Squeekchain Genesis Code Lane
(squeekchain.com/genesis/code, category "Dynamic NFTs that evolve with the hamster"). Every token is a
personal odometer: it shows how far Squeektoshi has run on the WHEELY9000 since that token was minted,
and its art and traits change as he runs, naps and crosses distance milestones.

## Goals

- A real, working product that uses Squeekchain's contracts directly (not a dashboard or an API wrapper).
- The art is computed in `tokenURI` from live SqueekCore state; nothing off-chain is needed to see a token.
- No owner, no admin, no upgrade, no pause, no funds. Free mint. Nothing can break or rug it.
- Ready for an IMD job that imports the public repository, audits it, deploys it on Sepolia and hosts the site.

## Non-goals

- No token, no payments, no mainnet deployment.
- No keeper, no oracle, no stored snapshots besides the work counter at mint.
- No following a future SqueekCore redeploy: the addresses are fixed at deploy (a new deploy is a new version).

## Squeekchain facts used (checked 2026-11-06)

- Chain: Sepolia, chain id 11155111. Release core-sepolia-20261103 (docs.squeekchain.com/developers/#deployments).
- SqueekCore proxy `0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4` (api.squeekchain.com/v1/core: deployment block
  12,057,556; cumulativeWork 11,048 and settledThroughRound 401 at the time of writing).
  - `state() returns (CoreState)`: `settledThroughRound uint64, cumulativeWork uint64, cumulativeBlockUnits uint96,
    blockHeight uint64, blockProgress uint96, workPerThousandBlocks uint32, authorizationNonce uint256, paused bool`.
  - `roundPage(uint64 afterRound, uint64 throughRound, uint256 maxRecords) returns (RoundPage)`: `certifiedThroughRound
    uint64, start LedgerPosition, end LedgerPosition, rounds RoundCheckpoint[]`; `LedgerPosition = (uint64
    cumulativeWork, uint96 cumulativeBlockUnits, uint32 workPerThousandBlocks)`. At most 16 records; rounds after the
    settled frontier revert.
- SqueekNFT (Squeeks) `0xC4C7982657f00509548F3a3a41db7FA439a6856B`: standard ERC-721 `balanceOf`.
- SqueekStaking `0x50fd1780526C3186A0c037c7622203bC4fb611ca`: `accountPower(address) returns (uint256 nftPower, uint256
  sqkPower)`; a deposited Squeek is owned by Staking, so a staker's wallet `balanceOf` is 0.
- One work unit is one accepted magnet passage, i.e. one wheel turn. Distance is the device's estimate from a fixed
  wheel circumference; the API's lifetime figures (22,789,368 mm over 25,701 units) give 886.7 mm per unit, and
  live speed/RPM readings give about 880 mm. The contract uses **887 mm per work unit**, stated in the README.

## Contract: `SqueekOdometer`

- ERC-721, name "Squeek Odometer", symbol "ODOMETER". OpenZeppelin v5 ERC721, vendored as plain files.
- Constructor: `(address core, address squeeks, address staking)`, all immutable. Reverts unless `block.chainid` is
  11155111 or 31337 (local tests).
- `mint()`: free, one per wallet (`minted[msg.sender]`), `MAX_SUPPLY = 9_999`, sequential ids from 1. Stores
  `startWork[id] = core.state().cumulativeWork` and `mintedAt[id] = block.timestamp`. If SqueekCore cannot be read,
  the mint reverts (a token must have a real starting point). Emits `Minted(id, owner, startWork)`.
- Reads that can fail (gas-capped static calls that copy a fixed number of words) never make `tokenURI` revert: if
  SqueekCore cannot be read, the token keeps its start work, shows no distance and the status "unknown".
- Derived values for a token:
  - `workSince = core.cumulativeWork - startWork` (never negative; 0 if the core went backwards).
  - `distance mm = workSince * 887`; shown as km with two decimals.
  - Stage by km: 0 Newbie, 1 Warm-up, 5 Jogger, 10 Runner, 25 Racer, 50 Marathoner, 100 Legend.
  - Status from the last three settled rounds (`roundPage(s-3, s, 3)`, `end - start` work, s = settledThroughRound):
    0 napping, under 1,500 jogging, 1,500 or more zoomies. Fewer than 3 settled rounds: use what exists.
  - Holder: the token owner holds a Squeek (`balanceOf > 0`) or has Squeeks deposited (`nftPower > 0`).
- `tokenURI`: `data:application/json;base64` with name `Squeek Odometer #id`, a description, `image` as
  `data:image/svg+xml;base64`, and attributes: Distance (km, number), Stage, Status, Squeek Holder (Yes/No),
  Start Work, Squeek Block Height.
- `odometer(id)` view returning the same derived values as a struct, for the site and tests.
- ERC-4906 `supportsInterface(0x49064906)` is true; no events are emitted for live changes (the art is computed on
  read; marketplaces refresh on their own).

## Art (SVG, pixel style)

- 32×32 pixel grid scaled to 512×512 with `shape-rendering="crispEdges"`, a small palette, matching Squeekchain's
  dot/pixel look.
- Layers: background tint by stage; the wheel (ring with spokes); the hamster sprite in one of three poses (running,
  zoomies with speed lines, napping with "z"); stage gear on the hamster (headband, shoes, medal, crown and cape for
  Legend); an odometer strip with the km digits; a gold frame for Squeek holders, a plain frame otherwise.
- Sprites are encoded as compact run-length byte strings in the contract; the renderer turns runs into `<rect>`s.
- Every stage × status × holder combination is rendered to a PNG gallery for review before deploy.

## Site (static, IPFS)

- One page: connect wallet (Sepolia), mint, "your odometer" rendered from `tokenURI`, a small live panel from
  `api.squeekchain.com/v1/status` (running or idle, RPM, block height) with a link to the official livestream, and
  a gallery of recent mints read from `Minted` events.
- No backend. viem from a pinned CDN build or vendored file; the contract address is a single constant.
- Contains the Squeekchain page tag if the board asks for one.

## Testing

- Foundry unit tests with mock SqueekCore, SqueekNFT and SqueekStaking: mint rules, distance and stage math (fuzz),
  status thresholds, holder detection through wallet and staking, `tokenURI` survives every failing dependency,
  JSON and SVG are well-formed, supply cap.
- A fork test against Sepolia SqueekCore (pinned block) that mints and reads `tokenURI`.
- `forge build` with `bytecode_hash = "none"`, solc 0.8.26 pinned, no submodules, no FFI, no network in the default
  profile (IMD's import rules).

## Delivery

- Public GitHub repository (the owner creates it; the code is pushed there).
- IMD job, paid from the owner's Genesis-verified wallet: import the repo at a commit, audit, deploy
  `SqueekOdometer` on Sepolia with the three addresses, host the site on IPFS. The paying wallet owns the project.
- Submit the project to the Code Lane board.
