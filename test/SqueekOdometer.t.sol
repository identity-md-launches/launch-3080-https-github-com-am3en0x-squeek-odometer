// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {Reading} from "../src/Types.sol";
import {MockCore, MockNFT, MockStaking} from "./mocks/Mocks.sol";

contract SqueekOdometerTest is Test {
    using stdStorage for StdStorage;

    MockCore core;
    MockNFT nft;
    MockStaking staking;
    SqueekOdometer odo;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    event Minted(uint256 indexed id, address indexed to, uint256 startWork);

    function setUp() public {
        core = new MockCore();
        nft = new MockNFT();
        staking = new MockStaking();
        core.set(10, 11_048, 1_140);
        odo = new SqueekOdometer(address(core), address(nft), address(staking));
    }

    function _mint(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = odo.mint();
    }

    // ---- mint

    function test_mintStoresTheWheelWorkAndIsSequential() public {
        vm.expectEmit(true, true, false, true);
        emit Minted(1, alice, 11_048);
        assertEq(_mint(alice), 1);
        assertEq(odo.startWork(1), 11_048);
        assertEq(odo.idOf(alice), 1);
        assertEq(odo.ownerOf(1), alice);
        core.set(11, 12_000, 1_200);
        assertEq(_mint(bob), 2);
        assertEq(odo.startWork(2), 12_000);
        assertEq(odo.totalMinted(), 2);
    }

    function test_oneMintPerWallet() public {
        _mint(alice);
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.AlreadyMinted.selector);
        odo.mint();
    }

    function test_supplyIsCapped() public {
        // 9,999 real mints cost ~1 billion gas: put the counter one short of the cap instead
        stdstore.target(address(odo)).sig("totalMinted()").checked_write(odo.MAX_SUPPLY() - 1);
        assertEq(_mint(bob), odo.MAX_SUPPLY());
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.SoldOut.selector);
        odo.mint();
    }

    function test_mintNeedsAReadableWheel() public {
        core.setBroken(true);
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
    }

    function test_onlySepoliaOrLocal() public {
        vm.chainId(1);
        vm.expectRevert(SqueekOdometer.WrongChain.selector);
        new SqueekOdometer(address(core), address(nft), address(staking));
    }

    // ---- distance and stage

    function test_distanceAndStage() public {
        _mint(alice);
        core.set(12, 11_048 + 1_128, 1_300);
        Reading memory r = odo.reading(1);
        assertEq(r.work, 1_128);
        assertEq(r.distanceMm, 1_000_536);
        assertEq(r.stage, 1, "1 km is Warm-up");
        assertEq(r.blockHeight, 1_300);
        assertTrue(r.live);
    }

    function test_stageThresholds() public {
        _mint(alice);
        uint256[7] memory km = [uint256(0), 1, 5, 10, 25, 50, 100];
        for (uint8 s = 0; s < 7; s++) {
            // the first work count at or past the threshold
            uint256 w = (km[s] * 1_000_000 + 886) / 887;
            core.set(12, uint64(11_048 + w), 1);
            assertEq(odo.reading(1).stage, s);
            if (w > 0) {
                core.set(12, uint64(11_048 + w - 1), 1);
                assertEq(odo.reading(1).stage, s - 1);
            }
        }
    }

    function testFuzz_distanceIsWorkTimes887(uint64 extra) public {
        extra = uint64(bound(extra, 0, 1e12));
        _mint(alice);
        core.set(12, 11_048 + extra, 1);
        Reading memory r = odo.reading(1);
        assertEq(r.distanceMm, uint256(extra) * 887);
        assertLe(r.stage, 6);
    }

    function test_workBelowTheStartReadsZero() public {
        _mint(alice);
        core.set(12, 5, 1);
        assertEq(odo.reading(1).work, 0);
        assertEq(odo.reading(1).distanceMm, 0);
    }

    // ---- status

    function test_statusFromTheLastThreeRounds() public {
        _mint(alice);
        core.set(20, 20_000, 1);
        assertEq(odo.reading(1).status, 0, "napping");
        core.setRound(18, 1_000);
        core.setRound(20, 499);
        assertEq(odo.reading(1).status, 1, "jogging");
        core.setRound(19, 1);
        assertEq(odo.reading(1).status, 2, "1,500 is zoomies");
        core.setRound(17, 5_000); // outside the window
        core.setRound(19, 0);
        assertEq(odo.reading(1).status, 1);
    }

    function test_statusWithFewerThanThreeRounds() public {
        core.set(1, 600, 1);
        core.setRound(1, 600);
        _mint(alice);
        assertEq(odo.reading(1).status, 1);
        core.set(0, 600, 1);
        assertEq(odo.reading(1).status, 0, "nothing settled yet");
    }

    function test_brokenCoreReadsUnknownAndKeepsTheStart() public {
        _mint(alice);
        core.setBroken(true);
        Reading memory r = odo.reading(1);
        assertFalse(r.live);
        assertEq(r.status, 3, "unknown");
        assertEq(r.startWork, 11_048);
        core.setBroken(false);
        core.setGasBomb(true);
        r = odo.reading(1);
        assertFalse(r.live);
    }

    // ---- holder

    function test_holderThroughWalletOrStaking() public {
        _mint(alice);
        assertFalse(odo.reading(1).holder);
        nft.setBalance(alice, 1);
        assertTrue(odo.reading(1).holder);
        nft.setBalance(alice, 0);
        staking.setPower(alice, 1_000);
        assertTrue(odo.reading(1).holder, "a deposited Squeek counts");
    }

    function test_holderFollowsTheCurrentOwner() public {
        _mint(alice);
        nft.setBalance(bob, 1);
        vm.prank(alice);
        odo.transferFrom(alice, bob, 1);
        assertTrue(odo.reading(1).holder);
    }

    function test_brokenHolderReadsAreFalseNotReverts() public {
        _mint(alice);
        nft.setBroken(true);
        staking.setGasBomb(true);
        assertFalse(odo.reading(1).holder);
    }

    function test_readingOfAMissingTokenReverts() public {
        vm.expectRevert();
        odo.reading(7);
    }

    // ---- frame tiers by Squeek power, and the pace (2026-11-07)

    function test_frameTierFollowsSqueekPower() public {
        _mint(alice);
        assertEq(odo.reading(1).tier, 0);
        nft.setBalance(alice, 1);
        assertEq(odo.reading(1).tier, 1, "a Squeek in the wallet: bronze");
        nft.setBalance(alice, 0);
        staking.setPower(alice, 1_000e18);
        assertEq(odo.reading(1).tier, 1, "one Level 1 deposited: bronze");
        staking.setPower(alice, 4_840e18);
        assertEq(odo.reading(1).tier, 2, "Level 3 power: silver");
        staking.setPower(alice, 23_426e18);
        assertEq(odo.reading(1).tier, 3, "Level 5 power: gold");
        staking.setPower(alice, 113_380e18);
        assertEq(odo.reading(1).tier, 4, "Level 7 power: diamond");
        assertTrue(odo.reading(1).holder);
        staking.setBroken(true);
        assertEq(odo.reading(1).tier, 0);
    }

    function test_paceIsTheLastThreeRoundsOfWork() public {
        _mint(alice);
        core.set(20, 20_000, 1);
        core.setRound(18, 300);
        core.setRound(20, 450);
        assertEq(odo.reading(1).pace, 750);
        core.setBroken(true);
        assertEq(odo.reading(1).pace, 0);
    }

    // ---- ERC-4906: anyone can ask marketplaces to look again

    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function test_refreshEmitsMetadataUpdates() public {
        _mint(alice);
        _mint(bob);
        vm.expectEmit(false, false, false, true);
        emit MetadataUpdate(2);
        odo.refresh(2);
        vm.expectEmit(false, false, false, true);
        emit BatchMetadataUpdate(1, 2);
        odo.refreshAll();
        vm.expectRevert();
        odo.refresh(3);
    }
}
