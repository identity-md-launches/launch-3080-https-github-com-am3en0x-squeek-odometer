// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISqueekCore, ISqueekNFT, ISqueekStaking} from "../../src/interfaces/ISqueek.sol";

/// @dev Switches every mock shares: answer, revert, or burn all the gas it is given.
abstract contract Breakable {
    bool public broken;
    bool public gasBomb;

    function setBroken(bool b) external {
        broken = b;
    }

    function setGasBomb(bool b) external {
        gasBomb = b;
    }

    function _check() internal view {
        if (gasBomb) {
            uint256 x;
            while (true) x++;
        }
        require(!broken, "broken");
    }
}

contract MockCore is ISqueekCore, Breakable {
    uint64 public settled;
    uint64 public work;
    uint64 public height;
    mapping(uint64 => uint64) public workIn; // round => work settled in it

    function set(uint64 settled_, uint64 work_, uint64 height_) external {
        settled = settled_;
        work = work_;
        height = height_;
    }

    function setRound(uint64 round, uint64 w) external {
        workIn[round] = w;
    }

    function state() external view returns (CoreState memory s) {
        _check();
        s.settledThroughRound = settled;
        s.cumulativeWork = work;
        s.blockHeight = height;
    }

    /// @dev Only what the odometer uses: the work between the two ledger positions.
    function roundPage(uint64 afterRound, uint64 throughRound, uint256) external view returns (RoundPage memory p) {
        _check();
        require(afterRound <= throughRound && throughRound <= settled, "InvalidRoundPageBounds");
        uint64 w;
        for (uint64 r = afterRound + 1; r <= throughRound; r++) {
            w += workIn[r];
        }
        p.certifiedThroughRound = throughRound;
        p.start.cumulativeWork = work - w;
        p.end.cumulativeWork = work;
    }
}

contract MockNFT is ISqueekNFT, Breakable {
    mapping(address => uint256) public bal;

    function setBalance(address a, uint256 b) external {
        bal[a] = b;
    }

    function balanceOf(address a) external view returns (uint256) {
        _check();
        return bal[a];
    }
}

contract MockStaking is ISqueekStaking, Breakable {
    mapping(address => uint256) public power;

    function setPower(address a, uint256 p) external {
        power[a] = p;
    }

    function accountPower(address a) external view returns (uint256, uint256) {
        _check();
        return (power[a], 0);
    }
}
