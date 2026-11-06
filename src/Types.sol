// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Everything an odometer token shows, derived from Squeekchain on every read.
struct Reading {
    uint256 startWork; // SqueekCore cumulativeWork when the token was minted
    uint256 work; // settled work since then (one unit = one wheel turn)
    uint256 distanceMm; // work * MM_PER_WORK
    uint8 stage; // 0 Newbie .. 6 Legend
    uint8 status; // 0 napping, 1 jogging, 2 zoomies, 3 unknown
    bool holder; // the token's owner holds a Squeek, in the wallet or deposited in staking
    uint64 blockHeight; // Squeek block height
    bool live; // SqueekCore answered
    uint8 display; // the odometer's display: 0 Green LCD .. 5 Mechanical (rolled at mint)
    uint8 casing; // its casing: 0 Cream, 1 Silver, 2 Charcoal, 3 Signal Orange (rolled at mint)
    uint8 pouch; // the treat Squeektoshi holds: 0 none, 1 seed, 2 berry, 3 coin, 4 diamond (rolled at mint)
    uint8 tier; // holder frame: 0 none, 1 bronze, 2 silver, 3 gold, 4 diamond (by Squeek power in staking)
    uint256 pace; // work settled in the last three rounds (wheel turns per 30 minutes)
}
