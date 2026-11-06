// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {SqueekOdometer} from "../../src/SqueekOdometer.sol";
import {MockCore, MockNFT, MockStaking} from "../mocks/Mocks.sol";

abstract contract OdometerTestBase is Test {
    MockCore internal core;
    MockNFT internal nft;
    MockStaking internal staking;
    SqueekOdometer internal odo;
    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public virtual {
        vm.chainId(31337);
        alice = makeAddr("Alice");
        bob = makeAddr("Bob");
        carol = makeAddr("Carol");
        core = new MockCore();
        nft = new MockNFT();
        staking = new MockStaking();
        core.set(10, 11_048, 1_140);
        odo = new SqueekOdometer(address(core), address(nft), address(staking));
    }

    function _mint(address who) internal returns (uint256) {
        vm.prank(who);
        return odo.mint();
    }

    function _json(uint256 id) internal view returns (string memory) {
        return string(_dataURI(odo.tokenURI(id), "data:application/json;base64,"));
    }

    function _dataURI(string memory uri, string memory prefix) internal pure returns (bytes memory) {
        bytes memory raw = bytes(uri);
        assertEq(Bytes.slice(raw, 0, bytes(prefix).length), bytes(prefix));
        return Base64.decode(string(Bytes.slice(raw, bytes(prefix).length)));
    }

    function _assertMetadata(uint256 id) internal view {
        string memory json = _json(id);
        assertEq(vm.parseJsonString(json, ".name"), string.concat("Squeek Odometer #", vm.toString(id)));
        assertEq(vm.parseJsonArrayLength(json, ".attributes"), 11);
        bytes memory svg = _dataURI(vm.parseJsonString(json, ".image"), "data:image/svg+xml;base64,");
        assertEq(Bytes.slice(svg, 0, 5), bytes("<svg "));
        assertEq(Bytes.slice(svg, svg.length - 6), bytes("</svg>"));
        assertGt(svg.length, 1_000);
        assertLt(svg.length, 32_768);
    }
}
