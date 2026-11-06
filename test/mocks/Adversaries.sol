// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekOdometer} from "../../src/SqueekOdometer.sol";
import {ISqueekCore} from "../../src/interfaces/ISqueek.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @dev Returns a configured prefix, a large answer, a revert, or exhausts its call gas.
contract RawDependency {
    enum Mode {
        Answer,
        Revert,
        Burn,
        ReturnBomb,
        RevertBomb,
        Write
    }
    Mode public mode;
    bytes private response;
    uint256 public writes;

    function configure(Mode mode_, bytes memory response_) external {
        mode = mode_;
        response = response_;
    }

    fallback() external {
        Mode m = mode;
        if (m == Mode.Revert) revert("dependency unavailable");
        if (m == Mode.Burn) {
            assembly ("memory-safe") { for {} 1 {} {} }
        }
        if (m == Mode.Write) writes++;
        bytes memory data = response;
        if (m == Mode.ReturnBomb || m == Mode.RevertBomb) {
            // 128 KiB fits inside READ_GAS but must never be copied in full by the caller.
            bytes memory bomb = new bytes(131_072);
            for (uint256 i; i < data.length && i < 256; ++i) {
                bomb[i] = data[i];
            }
            assembly ("memory-safe") {
                if eq(m, 4) { revert(add(bomb, 32), mload(bomb)) }
                return(add(bomb, 32), mload(bomb))
            }
        }
        assembly ("memory-safe") { return(add(data, 32), mload(data)) }
    }
}

/// @dev Attempts a write by callback and still supplies valid state if the callback was blocked.
contract ReentrantCore {
    SqueekOdometer private target;

    function setTarget(SqueekOdometer target_) external {
        target = target_;
    }

    function state() external returns (ISqueekCore.CoreState memory s) {
        (bool ok,) = address(target).call{gas: 100_000}(abi.encodeCall(SqueekOdometer.mint, ()));
        require(!ok, "static context did not block reentry");
        s.cumulativeWork = 123;
    }
}

contract CallbackWallet is IERC721Receiver {
    SqueekOdometer private immutable target;
    address private immutable onward;
    bool public callback;
    uint256 public mintedId;
    bytes4 public secondMintError;

    constructor(SqueekOdometer target_, address onward_) {
        target = target_;
        onward = onward_;
    }

    function mint() external returns (uint256) {
        return target.mint();
    }

    function onERC721Received(address, address, uint256 id, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(target));
        callback = true;
        // The receiver may mint its own token, but cannot mint a second or take another owner's token.
        mintedId = target.mint();
        try target.mint() {
            revert("second mint succeeded");
        } catch (bytes memory reason) {
            secondMintError = bytes4(reason);
        }
        target.transferFrom(address(this), onward, id);
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract RejectingWallet is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert("receiver refuses");
    }
}
