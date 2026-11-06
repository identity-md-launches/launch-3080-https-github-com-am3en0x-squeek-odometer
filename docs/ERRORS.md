# Errors

| Error | Raised by | Meaning | What to show the user |
| --- | --- | --- | --- |
| `AlreadyMinted()` | `mint` | this wallet has minted before (also if it sent its token away) | "Each wallet gets one odometer." |
| `SoldOut()` | `mint` | all 9,999 are minted | "All odometers are minted." |
| `CoreUnreadable()` | `mint` | SqueekCore did not answer, answered short, or answered with a round or work word outside `uint64`, so there is no starting point | "Squeekchain is not answering right now; try again in a minute." |
| `ERC721NonexistentToken(uint256)` | `tokenURI`, `reading`, `refresh`, `ownerOf` | no such token | "No odometer with that number." |
| other `ERC721*` errors | transfers and approvals | standard OpenZeppelin 5 errors | as for any ERC-721 |

The constructor has no revert path of its own (no chain check, no external call). `reading` and `tokenURI` do not
revert for an existing token: a dependency that reverts, runs out of gas, answers short or answers out of range
makes the token read *Unknown*, and every `uint64` work delta renders (the screen pegs at 99,999 km).
