# Validation of the imported launch project

Local checks completed with Foundry **1.8.3**, Solidity **0.8.26**, Cancun, optimizer **200** runs,
`bytecode_hash = "none"`. The application and art are unchanged from upstream commit
`8a3615240715afb93f6f0eaa78c0018a7d4676f2`. The historical upstream test/fork/site claims are not used as this
adaptation's evidence.

## Commands and results

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x85fa591383f4e7b776f91b5633053b3d8132526e6370e1e924ac214f2266ba93 forge test
forge fmt --check
python3 tools/export_abi.py --check
python3 tools/check_upstream.py
python3 tools/export_gallery.py --check
```

- Clean `forge build`: passed with the pinned compiler. The unchanged source emits lint warnings; see [REVIEW.md](REVIEW.md).
- Complete `forge test`: **86 passed, 0 failed, 0 skipped**, across eight suites, approximately 120 seconds locally.
- Nine fuzz tests: **512 cases each**, using the supplied seed, which is also pinned in `foundry.toml`.
- Stateful invariant: **128 runs × 64 calls = 8,192 calls**, no unexpected reverts. `fail_on_revert = true`.
- `forge fmt --check`: passed for the root project. `forge fmt` left all application and art sources unchanged.
- ABI export comparison: passed against `docs/abi/SqueekOdometer.json`.
- Source preservation: all **327** application, art, dependency and static site hashes match the pinned upstream.
- Gallery: the helper rendered and exactly reproduced all **10** committed SVG files without EVM filesystem grants,
  FFI, RPC access or broadcasting. Those SVG files also parsed as complete XML documents.

All build/test dependencies are ordinary vendored files in `lib/`, with their original licenses. No submodules,
network imports, node package installation or generated artifacts are required in the submitted source. The compiler
is pinned by version, not a filesystem path. No test consumes environment variables or shared mutable files.
The separate optional fork profile is excluded from the default suite.

**A passing suite is not a claim of unconditional metadata availability.** Three tests deliberately reproduce the
unchanged source's defects: oversized work words panic on read, a noncanonical mint baseline is accepted, and the
first eight-digit kilometre value breaks SVG position arithmetic. [REVIEW.md](REVIEW.md) records the expected-versus-actual
behavior, exact inputs, severity, suggested revisions and independent release responsibilities.

## Coverage

| Suite | Tests | Purpose |
| --- | ---: | --- |
| Original `SqueekOdometer.t.sol` | 19 | Mint, distance, stages, status, holder tiers, dependency failure, refresh |
| Original `OdometerArt.t.sol` | 18 | Art layers, animation, traits, metadata, interfaces, rendering gas |
| `Deployment.t.sol` | 5 | CREATE2 on empty Sepolia, exact arguments, chain restriction, nonpayable construction, runtime/opcode/privilege checks |
| `Adversarial.t.sol` | 18 | Full supply, mint rollback, ownership and approvals, receiver rejection/reentry, mint history, no ETH path, refresh storage/events |
| `DependencyReads.t.sol` | 17 | Short/missing/reverting/gas-burning dependencies, 128 KiB responses, static write rejection, window bounds, holder fallbacks |
| `KnownLimitations.t.sol` | 3 | Explicit, passing reproducers of the open upstream findings |
| `Properties.t.sol` | 5 | Full `uint64` distance domain, exact stage thresholds, decoded JSON/SVG within display limits, recovery |
| `Stateful.t.sol` | 1 | Model-based sequences of mint, transfer, invalid transfer, core changes/outages, refresh |

The full-cap test makes **9,999 real mint calls**, without overwriting application storage. Gas metering is disabled
only for the first 9,998 setup mints to avoid imposing a single-test gas limit on a lifetime supply; the boundary mint
and rejected over-cap mint use normal metering. This is not a gas estimate for minting the entire collection in one
transaction. The original counter-boundary test is retained as well.

The stateful model checks total balances equal minted supply, successful minters remain permanently marked, owners
match the transfer model, baselines/timestamps remain fixed, and distance remains correct through arbitrary canonical
work changes and outages. It does not assume `tokenURI` supports the full `uint64` range; the open boundary defect is
tested separately. Metadata fuzzing checks the whole supported nonpanicking display range and decodes the nested
Base64 JSON and SVG.

## Deployment artifact

| Property | Result |
| --- | ---: |
| SqueekOdometer runtime template | 23,212 bytes |
| EIP-170 remaining runtime space | 1,364 bytes |
| Creation bytecode, before arguments | 23,947 bytes |
| Creation bytecode plus three address arguments | 24,043 bytes |
| External library link references | None |

The factory rehearsal uses the brief's three exact addresses on chain 11155111, with no dependency code present,
zero value and no initialization. It verifies the CREATE2 address and immutable getters. A matching executable-opcode
scan checks the deployed runtime for DELEGATECALL, CALLCODE and SELFDESTRUCT. These local checks supplement the
protected launch checks; they do not claim to run the later manifest-dependent protected harness or replace it.

The checked runtime *template* SHA-256 is
`a9ec81210c6d4341668d55069f4898215f6a0e8eed5373a6f1c8a46d1fbc9498`.
Actual deployed bytes incorporate the constructor's immutable addresses; this template hash is not a live contract
code hash or a deployment attestation.

## Not performed by this adaptation

- No actual deployment, funded-wallet action, broadcast, factory call or source-verification transaction.
- No Slither, Mythril or independent-contributor security signoff.
- No live Sepolia or historical fork run, and no browser wallet integration run. The imported optional fork test can
  be run with `FOUNDRY_PROFILE=fork forge test`; it requires historical state at Sepolia block 12,077,300 and is not
  needed for the offline default checks.
- No website publication or invented deployed address. The launch service must provide the final address/block.

Operational assumptions, exact constructor parameters and post-launch responsibilities are in [README.md](../README.md)
and [SECURITY.md](SECURITY.md). Before release, the independent review must adjudicate the open findings, and the
launch service must verify the supplied dependencies on the actual target chain.
