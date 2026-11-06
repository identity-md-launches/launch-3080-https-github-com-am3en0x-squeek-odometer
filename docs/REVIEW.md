# Adaptation review and open findings

Scope: the unchanged SqueekOdometer application and art from upstream commit
`8a3615240715afb93f6f0eaa78c0018a7d4676f2`, the ERC-721 inheritance used by it, and its external read boundaries.
This is the adapting contributor's local review, not the independent adversarial signoff required before launch.
The pinned [job brief](https://github.com/am3en0x/squeek-odometer/blob/8a3615240715afb93f6f0eaa78c0018a7d4676f2/docs/IMD_JOB.md)
requests preservation of the contract and art. Consequently the findings below are reproduced and disclosed, not
silently repaired or hidden by weakening tests. No application source or art was changed.

## R1 — noncanonical core words defeat the metadata failure boundary

Severity: medium for metadata availability, conditional on malformed/hostile dependency responses; no custody or
transfer permission bypass was demonstrated. The ordinary typed SqueekCore ABI uses `uint64` cumulative work, so a
conforming dependency cannot produce the oversized value in this reproduction.

`SqueekOdometer._read` verifies call success and a minimum return length. It does not decode or range-check the
words. `reading` then uses word 1 directly as a `uint256` and multiplies its delta by 887. A successfully returned
out-of-range word can therefore panic, contradicting the brief's unconditional claim about a hostile dependency.

Exact reproduction (`test/KnownLimitations.t.sol`):

1. Mint token 1 at work 11,048.
2. Make `state()` return four words `[0, 2**256-1, 0, 1]` successfully.
3. `reading(1)` and `tokenURI(1)` both revert with `Panic(0x11)` instead of producing unknown metadata.

The related mint reproduction returns just `[0, 2**256-1]`. `mint()` succeeds and stores that noncanonical baseline.
Once canonical `uint64` readings resume, the token's delta remains zero for every possible canonical work value.
The length-only boundary also accepts incomplete ABI results and ignores a round page's dynamic offset. This is
prefix parsing, not authentication of Squeekchain's data.

Suggested remediation for a separately authorized revision: validate the ranges of consumed typed fields, reject a
malformed mint baseline with `CoreUnreadable`, and degrade malformed metadata responses to unknown. Review the
round page's fixed prefix and offset against the actual dependency ABI. No setter or admin is needed for this fix.

## R2 — valid large distances underflow the SVG's text position

Severity: low; requires an extreme distance, but lies inside the declared `uint64` work domain. It contradicts the
unqualified metadata-liveness claim even with an ABI-conforming dependency.

`OdometerArt._odometer` computes the text width and then `x0 = 30 - w`. Whole kilometres use four pixels per digit.
Eight digits require 32 pixels, so a distance of 10,000,000 km causes checked subtraction to panic. `reading` still
works, but `tokenURI` fails while that distance remains displayed. No token transfer or ownership operation is affected.

Exact boundary reproduction (`test_knownLimitation_largeCanonicalWorkOverflowsDisplayWidth`):

1. Mint with baseline zero.
2. Set cumulative work to **11,273,957,158**: `tokenURI(1)` succeeds.
3. Set it to **11,273,957,159**: distance is **10,000,000,000,033 mm**, and `tokenURI(1)` reverts with `Panic(0x11)`.

These are typed `MockCore` values, not corrupt raw words. The maximum possible `uint64` work is much larger.
Suggested remediation for a separately authorized revision: choose a bounded display representation for very large
values (for example a suffix or saturation), keep the actual numeric metadata separate, and fuzz the full work domain.
Preserving every existing rendered image below the boundary would still be possible, but changing the renderer is
outside this brief's preservation request.

## Verified properties and intentional limitations

- One successful mint per address, including after transfer, with a lifetime cap of 9,999. The full cap was exercised
  through 9,999 real mint calls, without changing odometer storage. Addresses are not human identities: many-wallet
  minting and trait grinding are possible, and transfers can give a holder more than one odometer.
- Mint state is atomic on a failed starting read. Mint uses `_mint` and never invokes an ERC-721 receiver callback.
  Contract wallets are allowed and must provide their own way to move an NFT they mint.
- Standard owner/operator/approved ERC-721 permissions remain intact. Safe receiver rejection rolls back state.
  A receiver callback can mint its own single token and transfer its received token; it cannot remint or bypass the cap.
- Factory construction on empty Sepolia requires no external code, value, initialization, signer, owner or admin.
  Chain 31337 is also allowed for local testing; the literal phrase "reverts outside Sepolia" needs that exception.
- All dependency calls are static, forward at most 500,000 gas each and copy only the consumed prefix. Tests exercise
  short responses, missing code, reverts, 128 KiB success/revert payloads, gas exhaustion and attempted writes/reentry.
  These checks bound the read operation, not the validity of returned values or the entire renderer.
- Holder power follows the current token owner. Staking NFT power takes precedence; SQK staking power alone does not
  qualify. A failed staking read falls back to the NFT wallet balance. Tiers do not confer transfer or admin privileges.
- `refresh` and `refreshAll` only log ERC-4906 events; tests record storage accesses and check no writes. They do not
  repair dependencies or guarantee that a marketplace refreshes. Core reads returning to normal need no refresh on-chain.
- Token baseline and traits persist across ownership transfers and dependency outages. `idOf` is mint history, not
  an ownership index. Status is the latest three *settled* rounds, not a wall-clock staleness check: if settlement
  stops, an old pace can remain visible.
- There is no payable entry point, fee, custody service, recovery, owner, upgrade, proxy or withdrawal. Forced ETH or
  accidentally sent assets are not recoverable. Immutable dependencies cannot be repointed after a redeployment.
- Trait rolls are deterministic from token id and baseline; they are not a verifiable randomness source. No monetary
  randomness, prize, payout or financial promise is implemented.

## Analysis limits and launch responsibilities

Solidity 0.8.26 build, local tests, seeded fuzzing, stateful invariants, formatting, ABI comparison, source hash
comparison, and offline gallery reproduction were performed. The test suite explicitly includes the above defect
reproducers, so a green suite must not be read as evidence that the defects are fixed.

Foundry emits lint warnings on the unchanged source (including packed string construction, integer casts and `_mint`).
The packed data builds display strings, not signed/authenticated hashes; the unsafe-mint warning reflects the intended
absence of a mint callback. These contextual explanations do not constitute an independent static-analysis verdict.
Slither and Mythril were not run, and no independent audit is claimed.

The live Sepolia fork and website wallet integration were not rerun in this adaptation. Dependency addresses are
exactly those supplied in the brief, not guessed; their current bytecode and behavior need confirmation by the
independent reviewer/deployment service. The default suite requires no RPC or external account. The optional fork
profile checks the supplied historical release at block 12,077,300 and requires an archive-capable RPC; it is not a
check of the live launch block.

The independent review must adjudicate R1 and R2 before release. The deployment service owns the later manifest,
actual factory deployment, explorer verification and recording the deployed address/block. A separate site operator
may then configure and host the unchanged static site. This assignment did not perform any of those external actions.
