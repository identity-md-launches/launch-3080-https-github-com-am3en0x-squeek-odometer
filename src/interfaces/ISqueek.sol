// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The parts of Squeekchain's Sepolia contracts the odometer reads (release core-sepolia-20261103,
/// docs.squeekchain.com/developers). Struct layouts follow the published ABIs.
interface ISqueekCore {
    struct CoreState {
        uint64 settledThroughRound;
        uint64 cumulativeWork;
        uint96 cumulativeBlockUnits;
        uint64 blockHeight;
        uint96 blockProgress;
        uint32 workPerThousandBlocks;
        uint256 authorizationNonce;
        bool paused;
    }

    struct LedgerPosition {
        uint64 cumulativeWork;
        uint96 cumulativeBlockUnits;
        uint32 workPerThousandBlocks;
    }

    struct RoundCheckpoint {
        uint64 roundId;
        uint64 cumulativeWork;
        uint96 cumulativeBlockUnits;
        uint32 workPerThousandBlocks;
        bytes32 dataHash;
    }

    struct RoundPage {
        uint64 certifiedThroughRound;
        LedgerPosition start;
        LedgerPosition end;
        RoundCheckpoint[] rounds;
    }

    function state() external view returns (CoreState memory);

    function roundPage(uint64 afterRound, uint64 throughRound, uint256 maxRecords)
        external
        view
        returns (RoundPage memory);
}

interface ISqueekNFT {
    function balanceOf(address owner) external view returns (uint256);
}

interface ISqueekStaking {
    function accountPower(address account) external view returns (uint256 nftPower, uint256 sqkPower);
}
