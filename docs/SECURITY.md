# Security handoff

The deployed application and art are unchanged from the pinned upstream commit. Read [REVIEW.md](REVIEW.md) for
reproduced open findings and [VALIDATION.md](VALIDATION.md) for this adaptation's checks. These notes and tests are
not an independent audit or approval to release.

## Authority and value flow

There is no owner, admin, pause, upgrade, initializer or proxy. Anyone can mint once per address, up to 9,999 in total,
for no contract fee. `idOf` keeps the original minter's id permanently; transferring away does not restore eligibility.
ERC-721 owners, approved addresses and operators control transfers. A recipient may receive multiple tokens and
still exercise its own one-time mint. Mint acts for `msg.sender`, makes no receiver callback and stores its state
only after a successful static core read. Contract callers must know how to manage NFTs they mint.

`refresh(id)` validates existence and emits `MetadataUpdate`; `refreshAll()` emits `BatchMetadataUpdate(1, totalMinted)`
only for nonempty supply. Both are permissionless and write no storage. Metadata changes on read, not on refresh.

Every entry point is nonpayable. Plain ETH transfers and unknown selectors revert. There are no fees, royalties,
withdrawals or payouts. Forced ETH and accidentally transferred unrelated assets have no recovery path.

## External reads and liveness

The three addresses are immutable constructor arguments from the brief. Constructors make no calls to them and do
not require code; using the wrong address may leave mint unavailable forever, so launch-time verification matters.
`state()` and `roundPage()` are read from core, `accountPower(owner)` from staking and `balanceOf(owner)` from NFT.
Only staking's NFT power is used; SQK power alone does not count. Positive staking power bypasses the NFT read.

Every external read uses `_read`, a `STATICCALL` capped at 500,000 gas. Output memory is a fixed eight-word buffer;
only 2 words for mint state, 4 for reading state, 6 for a round page and 1 for either holder read are copied.
Reverts, gas exhaustion, missing code and short responses fail the read. A failed mint state read reverts the entire
mint with `CoreUnreadable`. Failed metadata state reads produce `live=false`, unknown status and zero distance;
a failed round page leaves distance live but status unknown. Failed staking reads fall back to the NFT balance.

This boundary does **not** fully decode or validate responses. Oversized work can panic in distance arithmetic, and
noncanonical work is accepted at mint. Also, the renderer cannot position eight or more kilometre digits. These
known defects invalidate any unconditional "tokenURI cannot revert" claim; see R1/R2 in [REVIEW.md](REVIEW.md).
All calls additionally require enough caller/RPC gas. Gas caps on dependencies are not guarantees under arbitrarily
small outer gas budgets.

## Arithmetic and display assumptions

Distance is `max(currentWork - startWork, 0) * 887` millimetres. Every canonical `uint64` delta fits in that multiplication.
Core rollback can reduce displayed distance; no high-water mark is stored. Status compares the last up to three
settled rounds' ledger positions: zero delta naps, 1–1,499 jogs, and at least 1,500 has zoomies. Settlement freshness is
not checked against time. Work, tiers and pace are cosmetic and rely on the fixed Squeekchain contracts' honesty.

Stages begin at 1/5/10/25/50/100 km. Traits come from a deterministic hash of id and baseline; mint timing and address
creation can influence them. There is no economically secure randomness requirement in this free testnet collection.
The internal art libraries have no external link references. Their buffers and loops are bounded, but rendering
still has the documented arithmetic edge case for sufficiently large text.

## Deployment and operations

- Chain: Sepolia, 11155111. Local 31337 is allowed by the original constructor for tests; other chains revert.
- One contract: `SqueekOdometer`, no token, distributor, pool or separate deployed library.
- Constructor order: core `0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4`, NFT
  `0xC4C7982657f00509548F3a3a41db7FA439a6856B`, staking `0x50fd1780526C3186A0c037c7622203bC4fb611ca`.
- Zero deployment value, no owner/admin argument, no initialization and no post-launch configuration transaction.
- No worker broadcast, keys, factory call, or deployed address is included. The launch service performs deployment
  after independent review and creates its own manifest. Verify the exact dependencies before making them immutable.
- Nobody can upgrade this application or redirect it if Squeekchain redeploys. A new odometer deployment would be needed.
- Site hosting is separate. Its operator supplies the real deployed address/block and an appropriate RPC; users pay
  normal Sepolia gas for mint/refresh/transfer. Marketplaces choose their own caching policies.
