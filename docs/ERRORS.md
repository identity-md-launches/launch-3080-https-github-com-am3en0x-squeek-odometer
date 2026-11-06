# Errors

| Error | Raised by | Meaning | What to show the user |
| --- | --- | --- | --- |
| `AlreadyMinted()` | `mint` | this wallet has minted before (also if it sent its token away) | "Each wallet gets one odometer." |
| `SoldOut()` | `mint` | all 9,999 are minted | "All odometers are minted." |
| `CoreUnreadable()` | `mint` | SqueekCore did not answer, so there is no starting point | "Squeekchain is not answering right now; try again in a minute." |
| `WrongChain()` | constructor | deployed outside Sepolia (or local 31337) | deployment error |
| `ERC721NonexistentToken(uint256)` | `tokenURI`, `reading`, `refresh`, `ownerOf` | no such token | "No odometer with that number." |
| other `ERC721*` errors | transfers and approvals | standard OpenZeppelin 5 errors | as for any ERC-721 |
| `Panic(0x11)` | `reading`, `tokenURI` | an oversized dependency work word overflows distance, or an extreme distance exceeds the SVG text position arithmetic | "Metadata is unavailable; retry later." See the open findings in [REVIEW.md](REVIEW.md); refresh events cannot repair these conditions. |
