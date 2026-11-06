# ABI and client integration

[abi/SqueekOdometer.json](abi/SqueekOdometer.json) is the compiler-generated ABI. Regenerate after `forge build` with
`python3 tools/export_abi.py`; `--check` compares it with the local artifact.

## Writes

| Function | Who | What |
| --- | --- | --- |
| `mint()` | anyone, once per wallet | mints the next id to the caller, free; returns the id |
| `refresh(uint256 id)` | anyone | emits `MetadataUpdate(id)` (ERC-4906) so marketplaces fetch the art again |
| `refreshAll()` | anyone | emits `BatchMetadataUpdate(1, totalMinted)` |
| ERC-721 transfers and approvals | holders | standard OpenZeppelin behaviour |

## Reads

| Function | Returns |
| --- | --- |
| `tokenURI(uint256 id)` | `data:application/json;base64,...` with an animated SVG image (`data:image/svg+xml;base64,...`) |
| `reading(uint256 id)` | the live `Reading` struct below |
| `idOf(address)` | the token a wallet minted (0: none) |
| `startWork(uint256 id)`, `mintedAt(uint256 id)` | SqueekCore work and block time at mint |
| `totalMinted()`, `MAX_SUPPLY()`, `MM_PER_WORK()`, `ZOOMIES_WORK()` | counters and constants |
| `stageOf(uint256 distanceMm)` | the stage for a distance |
| `core()`, `squeeks()`, `staking()` | the Squeekchain addresses the token reads |

`Reading` (in declaration order): `startWork`, `work` (settled wheel turns since mint), `distanceMm`, `stage`
(0 Newbie, 1 Warm-up, 2 Jogger, 3 Runner, 4 Racer, 5 Marathoner, 6 Legend), `status` (0 napping, 1 jogging,
2 zoomies, 3 unknown), `holder`, `blockHeight` (Squeek block height), `live` (SqueekCore answered), `display`
(0 Green LCD, 1 Amber, 2 Red LED, 3 Ice VFD, 4 Nixie, 5 Mechanical), `casing` (0 Cream, 1 Silver, 2 Charcoal,
3 Signal Orange), `pouch` (the treat: 0 none, 1 sunflower seed, 2 berry, 3 coin, 4 diamond), `tier` (water bottle:
0 none, 1 bronze, 2 silver, 3 gold, 4 diamond), `pace` (work in the last three settled rounds).

## Events

| Event | When |
| --- | --- |
| `Minted(uint256 indexed id, address indexed to, uint256 startWork)` | every mint (the site lists recent mints from it) |
| `MetadataUpdate(uint256)`, `BatchMetadataUpdate(uint256, uint256)` | `refresh` / `refreshAll` |
| `Transfer`, `Approval`, `ApprovalForAll` | ERC-721 |

Errors are listed in [ERRORS.md](ERRORS.md).

`idOf` records mint history: a wallet can transfer that token away and still keep the same `idOf` value. Query
`ownerOf` before treating it as the connected wallet's token, as `dist/app.js` does; a bought token is found through
its `Transfer` log. `reading` and `tokenURI` revert only for a token that does not exist. A successful `refresh`
receipt does not guarantee marketplace cache invalidation.
