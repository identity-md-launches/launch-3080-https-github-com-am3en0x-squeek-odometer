# Security handoff

The deployed application and art are the pinned upstream commit's with the review revision of 2026-11-06 applied
(chain guard removed, copied words range-checked, display pegged and aligned). Read [REVIEW.md](REVIEW.md) for every
finding and its disposition and [VALIDATION.md](VALIDATION.md) for this work's checks. These notes and tests are not
an independent audit or approval to release.

## Authority and value flow

There is no owner, admin, pause, upgrade, initializer or proxy. Anyone can mint once per address, up to 9,999 in total,
for no contract fee. `idOf` keeps the original minter's id permanently; transferring away does not restore eligibility.
Addresses are free, so the cap can be reached by throwaway wallets or by contracts that mint in their constructor
(whose tokens are then stranded, since `_mint` makes no receiver check); once reached, the lockout is permanent and
no token can be recovered or burned. That is a property of the agreed free open mint, not something the contract
prevents.
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
Reverts, gas exhaustion, missing code and short responses fail the read. Each copied word that is used is then
checked against the type its field declares: `settledThroughRound`, `cumulativeWork` and `blockHeight` must fit
`uint64`, a round page must start at ABI offset 32 and its two `cumulativeWork` words must fit `uint64`. A word out
of range fails the read like a revert would. A failed or out-of-range mint state read reverts the entire mint with
`CoreUnreadable`, so no baseline that a canonical reading could never exceed is ever stored. Failed metadata state
reads produce `live=false`, unknown status and zero distance; a failed round page leaves distance live but status
unknown. Failed staking reads fall back to the NFT balance.

Because the baseline and the live work are both `uint64`, the distance multiplication cannot overflow, and the
renderer pegs its screen at 99,999 km, so `tokenURI` cannot revert for an existing token whatever the dependencies
answer. The boundary validates ranges and layout, not truth: values inside their ranges are trusted as
Squeekchain's data. SqueekCore and SqueekStaking on Sepolia are EIP-1967 proxies that Squeekchain's timelock
(5-minute delay) can upgrade; an upgrade that changes the layout of `state()` or `roundPage()` makes tokens read
*Unknown* (or, at mint, revert `CoreUnreadable`) until the layout is restored, since the addresses are immutable and
there is no owner to repoint them. All calls additionally require enough caller/RPC gas. Gas caps on dependencies
are not guarantees under arbitrarily small outer gas budgets.

During a read failure the JSON still carries numeric attributes: Distance (km) 0.00, Stage Newbie and, when the
staking read fails for a wallet whose Squeeks are deposited, Squeek Holder No; only Status says Unknown and the
screen shows "?". Marketplaces that cache attributes may show those until the next fetch. The attribute set is kept
stable on purpose (the site and indexers read it by name); treat Status Unknown as "the rest is not current".

## Arithmetic and display assumptions

Distance is `max(currentWork - startWork, 0) * 887` millimetres. Every canonical `uint64` delta fits in that multiplication.
Core rollback can reduce displayed distance; no high-water mark is stored. Status compares the last up to three
settled rounds' ledger positions: zero delta naps, 1–1,499 jogs, and at least 1,500 has zoomies. Settlement freshness is
not checked against time. Work, tiers and pace are cosmetic and rely on the fixed Squeekchain contracts' honesty.

Stages begin at 1/5/10/25/50/100 km. Traits come from a deterministic hash of id and baseline; mint timing and address
creation can influence them. There is no economically secure randomness requirement in this free testnet collection.
The internal art libraries have no external link references. Their buffers and loops are bounded, and the odometer
text is never wider than its screen (five digit positions, columns 9 to 30): past 99,999 km the screen reads 99999
while the JSON keeps the exact distance.

## Deployment and operations

- Chain: Sepolia, 11155111. The constructor does not check the chain id (the launch rehearses it on another chain);
  the Sepolia binding is the three dependency addresses.
- One contract: `SqueekOdometer`, no token, distributor, pool or separate deployed library.
- Constructor order: core `0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4`, NFT
  `0xC4C7982657f00509548F3a3a41db7FA439a6856B`, staking `0x50fd1780526C3186A0c037c7622203bC4fb611ca`.
- Zero deployment value, no owner/admin argument, no initialization and no post-launch configuration transaction.
- No worker broadcast, keys, factory call, or deployed address is included. The launch service performs deployment
  after independent review and creates its own manifest. Verify the exact dependencies before making them immutable.
- Nobody can upgrade this application or redirect it if Squeekchain redeploys. A new odometer deployment would be needed.
- Site hosting is separate. Its operator supplies the real deployed address/block and an appropriate RPC; users pay
  normal Sepolia gas for mint/refresh/transfer. Marketplaces choose their own caching policies.
