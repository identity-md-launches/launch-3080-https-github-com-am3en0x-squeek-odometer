# Squeek Odometer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A free, fully on-chain dynamic ERC-721 on Sepolia whose art follows Squeektoshi's settled wheel work, plus a static mint site, ready for an IMD import-audit-deploy job.

**Architecture:** One contract `SqueekOdometer` (OpenZeppelin ERC721, no owner) reads SqueekCore, SqueekNFT and SqueekStaking through narrow interfaces with gas-capped `try`/`catch`, derives a `Reading`, and renders it with a pure `OdometerArt` library into an SVG built from run-length pixel sprites generated offline by `tools/sprites.py`. The site is one static page talking JSON-RPC directly.

**Tech Stack:** Solidity 0.8.26, Foundry, OpenZeppelin Contracts v5 (vendored files), Python 3 (sprite generator and previews), vanilla JS.

**Spec:** `docs/superpowers/specs/2026-11-06-squeek-odometer-design.md`

## Global Constraints

- Chain: Sepolia 11155111 (constructor also accepts 31337 for local tests). No mainnet.
- Addresses: SqueekCore `0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4`, SqueekNFT `0xC4C7982657f00509548F3a3a41db7FA439a6856B`, SqueekStaking `0x50fd1780526C3186A0c037c7622203bC4fb611ca` (constructor arguments, immutable).
- `MM_PER_WORK = 887`; `MAX_SUPPLY = 9_999`; one mint per wallet; free; no owner, admin, pause, upgrade, withdraw.
- Stages (km): 0 Newbie, 1 Warm-up, 5 Jogger, 10 Runner, 25 Racer, 50 Marathoner, 100 Legend.
- Status from the last three settled rounds: 0 work napping, < 1,500 jogging, >= 1,500 zoomies; unreadable = unknown.
- `tokenURI` never reverts for an existing token, whatever the dependencies do.
- foundry.toml: `solc = "0.8.26"`, optimizer on, `bytecode_hash = "none"`; no submodules, no FFI, no fs cheatcodes and no network in the default profile; fork tests only under `[profile.fork]`.
- Repo content in English (it is public and reviewed by IMD and the Squeekchain team); chat with the owner in Russian. Commit messages in English with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task 1: Scaffold, interfaces, mocks

**Files:** `foundry.toml`, `remappings.txt`, `.gitignore`, `lib/openzeppelin-contracts/**` (only the files ERC721 needs), `lib/forge-std/**`, `src/interfaces/ISqueek.sol`, `test/mocks/Mocks.sol`.

**Produces:** `ISqueekCore` (structs `CoreState`, `LedgerPosition`, `RoundCheckpoint`, `RoundPage`; `state()`, `roundPage(uint64,uint64,uint256)`), `ISqueekNFT.balanceOf(address)`, `ISqueekStaking.accountPower(address) returns (uint256 nftPower, uint256 sqkPower)`; mocks `MockCore` (settable state, per-round work, `setBroken(bool)`, `setGasBomb(bool)`), `MockNFT`, `MockStaking` with the same switches.

- [ ] Copy forge-std and the OpenZeppelin files as plain files (no `.git`), write foundry.toml/remappings/.gitignore.
- [ ] Write the interfaces exactly as in the spec's "Squeekchain facts" section and the mocks.
- [ ] `forge build` passes. Commit "Scaffold: Foundry project, Squeekchain interfaces and test mocks".

### Task 2: Contract logic (mint and reading)

**Files:** `src/SqueekOdometer.sol` (logic part), `test/SqueekOdometer.t.sol`.

**Produces:** `constructor(address core, address squeeks, address staking)`, `mint() returns (uint256 id)`, `idOf(address) returns (uint256)`, `startWork(uint256)`, `mintedAt(uint256)`, `totalMinted()`, `reading(uint256 id) returns (Reading)` with `struct Reading { uint256 startWork; uint256 work; uint256 distanceMm; uint8 stage; uint8 status; bool holder; uint64 blockHeight; bool live; }`, constants `MM_PER_WORK`, `MAX_SUPPLY`, event `Minted(uint256 indexed id, address indexed to, uint256 startWork)`, errors `AlreadyMinted()`, `SoldOut()`, `CoreUnreadable()`, `WrongChain()`.

Tests first (each must fail before the code exists):
- [ ] mint stores startWork = core cumulativeWork, ids are sequential, `Minted` is emitted; second mint from the same wallet reverts `AlreadyMinted`; the 10,000th mint reverts `SoldOut` (set the counter through a test helper loop of 9,999 distinct addresses).
- [ ] mint reverts `CoreUnreadable` when the core is broken; the constructor reverts `WrongChain` on chain id 1.
- [ ] distance: work 1,128 since mint gives 1,000,536 mm and stage Warm-up; fuzz `distanceMm == work * 887` and stage monotonic in work; work below startWork reads 0.
- [ ] status: last three rounds 0 work napping, 1,499 jogging, 1,500 zoomies; fewer than three settled rounds uses what exists; broken core gives status unknown and `live == false` with the stored startWork.
- [ ] holder: wallet `balanceOf > 0` true; `nftPower > 0` true; both zero false; reverting or gas-bombing NFT/staking reads false without reverting.
- [ ] Implement, run `forge test`, commit "Contract: free one-per-wallet mint and a live reading of the wheel".

### Task 3: Pixel sprites and the renderer

**Files:** `tools/sprites.py`, `src/art/Sprites.sol` (generated), `src/art/OdometerArt.sol`, `test/OdometerArt.t.sol`, `tools/preview.py`.

**Produces:** `OdometerArt.svg(Reading memory r) returns (string)`, `OdometerArt.json(uint256 id, Reading memory r) returns (string)`; `tokenURI` in `SqueekOdometer` returns `data:application/json;base64,…`; `supportsInterface(0x49064906)`.

- [ ] `tools/sprites.py` holds the char maps (40×40 scene: wheel ring and spokes, stand, hamster run/nap poses, zoomies speed lines, nap "z", gear overlays per stage, 3×5 pixel digits, K/M letters) and a palette, and writes `src/art/Sprites.sol` with each layer as packed runs `(x, y, len, color)` = 4 bytes per run.
- [ ] Tests first: `svg` starts with `<svg` and ends with `</svg>`; holder adds the gold frame color, non-holder the grey one; napping contains the "z" layer and not the speed lines, zoomies the opposite; Legend contains the crown color; the digits for 12.73 km render as "0012.73"-style runs (check by counting digit runs); `json` is valid (parses in a test helper that checks braces/quotes) and holds the attributes Distance, Stage, Status, Squeek Holder, Start Work, Squeek Block Height; `tokenURI` of a token whose core is broken still returns a JSON with Status "unknown"; `tokenURI` of a missing id reverts like ERC721.
- [ ] `tools/preview.py` renders every stage × status × holder combination from the same sprite data to PNG files in `previews/` (git-ignored) for the owner to look at; iterate the art until it reads well at 64 px and 512 px.
- [ ] `forge test`, commit "Art: pixel odometer rendered on chain from the wheel's work".

### Task 4: Fork test against Sepolia

**Files:** `test/fork/SqueekOdometerFork.t.sol`, `[profile.fork]` in foundry.toml (`match_path = "test/fork/*"`, `eth_rpc_url = "https://ethereum-sepolia-rpc.publicnode.com"`); the default profile excludes `test/fork/**`.

- [ ] Deploy against the real three addresses at a pinned recent block, mint, read `reading` and `tokenURI`; the startWork equals `SqueekCore.state().cumulativeWork` at that block.
- [ ] `forge test --profile fork`, commit "Fork test: the odometer against Sepolia SqueekCore".

### Task 5: Static site

**Files:** `site/index.html`, `site/app.js`, `site/style.css`, `site/config.js` (contract address constant, empty until deploy).

- [ ] Connect wallet (EIP-1193), switch to Sepolia, `mint()`, show `idOf(account)` and render its `tokenURI` image; live panel from `https://api.squeekchain.com/v1/status` (running or idle, RPM, Squeek block height) with the official livestream link; recent mints from `Minted` logs via a public Sepolia RPC. Hand-written ABI encoding for the four calls used (selectors in a table at the top of app.js).
- [ ] Check in a local browser with a mocked config (no deploy) that the page loads, the live panel fills, and errors read clearly. Commit "Site: mint page with the live wheel".

### Task 6: README, delivery

**Files:** `README.md`, `docs/IMD_JOB.md`.

- [ ] README: what it is, how distance/stage/status are computed (with the 887 mm source), addresses, build and test commands, no-owner statement, Squeekchain attribution line.
- [ ] `docs/IMD_JOB.md`: the exact IMD job body (import repo at commit, audit, `evm_contracts` deploy of `SqueekOdometer` with the three addresses, site to IPFS) for the owner to submit from the Genesis-verified wallet.
- [ ] Push to the owner's public GitHub repository once it exists. Commit "Docs: README and the IMD job".
