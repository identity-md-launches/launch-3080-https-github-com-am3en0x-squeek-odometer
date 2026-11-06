// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {Reading} from "../src/Types.sol";
import {OdometerTestBase} from "./helpers/OdometerTestBase.sol";
import {CallbackWallet, RejectingWallet, ReentrantCore} from "./mocks/Adversaries.sol";

contract OdometerAdversarialTest is OdometerTestBase {
    function test_mintIsFreeAndRejectsEtherAtomically() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(odo).call{value: 1}(abi.encodeCall(SqueekOdometer.mint, ()));
        assertFalse(ok);
        assertEq(odo.totalMinted(), 0);
        assertEq(odo.idOf(alice), 0);
        assertEq(address(odo).balance, 0);
        assertEq(_mint(alice), 1);
        assertEq(alice.balance, 1 ether);
    }

    function test_plainEtherAndUnknownSelectorsRejected() public {
        vm.deal(address(this), 2);
        (bool plain,) = address(odo).call{value: 1}("");
        (bool fallbackCall,) = address(odo).call{value: 1}(hex"abcdef12");
        assertFalse(plain);
        assertFalse(fallbackCall);
        assertEq(address(odo).balance, 0);
    }

    function test_failedMintLeavesNoStateAndCanRetry() public {
        core.setBroken(true);
        vm.recordLogs();
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(odo.totalMinted(), 0);
        assertEq(odo.idOf(alice), 0);
        assertEq(odo.balanceOf(alice), 0);
        assertEq(odo.startWork(1), 0);
        assertEq(odo.mintedAt(1), 0);
        core.setBroken(false);
        vm.warp(1_800_000_001);
        assertEq(_mint(alice), 1);
        assertEq(odo.mintedAt(1), 1_800_000_001);
    }

    function test_transferringAwayDoesNotRestoreMintEligibility() public {
        _mint(alice);
        vm.prank(alice);
        odo.transferFrom(alice, bob, 1);
        assertEq(odo.balanceOf(alice), 0);
        assertEq(odo.idOf(alice), 1);
        assertEq(odo.idOf(bob), 0);
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.AlreadyMinted.selector);
        odo.mint();
        assertEq(_mint(bob), 2, "receiving is not minting");
        assertEq(odo.balanceOf(bob), 2, "one mint per wallet is not one NFT per holder");
        assertEq(odo.totalMinted(), 2);
    }

    function test_transferKeepsBaselineTimestampAndTraitsButUpdatesHolder() public {
        _mint(alice);
        uint256 timestamp = odo.mintedAt(1);
        Reading memory before_ = odo.reading(1);
        staking.setPower(bob, 113_380e18);
        core.set(0, 20_000, 2_000);
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        odo.transferFrom(alice, bob, 1);
        Reading memory after_ = odo.reading(1);
        assertEq(after_.startWork, before_.startWork);
        assertEq(odo.mintedAt(1), timestamp);
        assertEq(after_.display, before_.display);
        assertEq(after_.casing, before_.casing);
        assertEq(after_.pouch, before_.pouch);
        assertEq(after_.distanceMm, (20_000 - 11_048) * 887);
        assertEq(after_.tier, 4);
        assertTrue(after_.holder);
    }

    function test_unauthorizedTransfersAndApprovalsRevert() public {
        _mint(alice);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, bob, 1));
        odo.transferFrom(alice, bob, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, bob));
        odo.approve(bob, 1);
        vm.stopPrank();
        assertEq(odo.ownerOf(1), alice);
    }

    function test_singleApprovalIsClearedOnTransfer() public {
        _mint(alice);
        vm.prank(alice);
        odo.approve(carol, 1);
        vm.prank(carol);
        odo.transferFrom(alice, bob, 1);
        assertEq(odo.getApproved(1), address(0));
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, carol, 1));
        odo.transferFrom(bob, carol, 1);
    }

    function test_operatorApprovalAndRevocation() public {
        _mint(alice);
        vm.prank(alice);
        odo.setApprovalForAll(carol, true);
        assertTrue(odo.isApprovedForAll(alice, carol));
        vm.prank(alice);
        odo.setApprovalForAll(carol, false);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, carol, 1));
        odo.transferFrom(alice, bob, 1);
        vm.prank(alice);
        odo.setApprovalForAll(carol, true);
        vm.prank(carol);
        odo.transferFrom(alice, bob, 1);
        assertEq(odo.ownerOf(1), bob);
    }

    function test_cannotBurnOrTransferFromWrongOwner() public {
        _mint(alice);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        odo.transferFrom(alice, address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, bob, 1, alice));
        odo.transferFrom(bob, carol, 1);
        vm.stopPrank();
        assertEq(odo.ownerOf(1), alice);
    }

    function test_rejectedSafeTransferRollsBackOwnerBalanceAndApproval() public {
        _mint(alice);
        RejectingWallet receiver = new RejectingWallet();
        vm.prank(alice);
        odo.approve(carol, 1);
        vm.prank(carol);
        vm.expectRevert(bytes("receiver refuses"));
        odo.safeTransferFrom(alice, address(receiver), 1);
        assertEq(odo.ownerOf(1), alice);
        assertEq(odo.balanceOf(alice), 1);
        assertEq(odo.balanceOf(address(receiver)), 0);
        assertEq(odo.getApproved(1), carol);
    }

    function test_receiverCanMintOnceAndTransferReceivedTokenDuringCallback() public {
        _mint(alice);
        CallbackWallet receiver = new CallbackWallet(odo, bob);
        vm.prank(alice);
        odo.safeTransferFrom(alice, address(receiver), 1, hex"cafe");
        assertTrue(receiver.callback());
        assertEq(receiver.mintedId(), 2);
        assertEq(receiver.secondMintError(), SqueekOdometer.AlreadyMinted.selector);
        assertEq(odo.ownerOf(1), bob);
        assertEq(odo.ownerOf(2), address(receiver));
        assertEq(odo.totalMinted(), 2);
        assertEq(odo.balanceOf(address(receiver)), 1);
        assertEq(odo.idOf(alice), 1);
    }

    function test_mintToContractDoesNotInvokeReceiverHook() public {
        CallbackWallet wallet = new CallbackWallet(odo, bob);
        assertEq(wallet.mint(), 1);
        assertFalse(wallet.callback());
        assertEq(odo.ownerOf(1), address(wallet));
    }

    function test_staticDependencyCannotReenterMint() public {
        ReentrantCore attacker = new ReentrantCore();
        SqueekOdometer target = new SqueekOdometer(address(attacker), address(nft), address(staking));
        attacker.setTarget(target);
        vm.prank(alice);
        assertEq(target.mint(), 1);
        assertEq(target.startWork(1), 123);
        assertEq(target.totalMinted(), 1);
        assertEq(target.idOf(address(attacker)), 0);
        assertEq(target.balanceOf(address(attacker)), 0);
    }

    function test_emptyRefreshAllEmitsNothingAndWritesNothing() public {
        vm.record();
        vm.recordLogs();
        odo.refreshAll();
        (, bytes32[] memory writes) = vm.accesses(address(odo));
        assertEq(writes.length, 0);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_anyoneCanRefreshWithoutChangingStorageOrReadingDependencies() public {
        _mint(alice);
        _mint(bob);
        core.setBroken(true);
        nft.setBroken(true);
        staking.setBroken(true);
        vm.record();
        vm.recordLogs();
        vm.startPrank(carol);
        odo.refresh(2);
        odo.refreshAll();
        vm.stopPrank();
        (, bytes32[] memory writes) = vm.accesses(address(odo));
        assertEq(writes.length, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(odo));
        assertEq(logs[0].topics.length, 1, "ERC-4906 token ids are not indexed");
        assertEq(logs[0].topics[0], keccak256("MetadataUpdate(uint256)"));
        assertEq(logs[0].data, abi.encode(uint256(2)));
        assertEq(logs[1].topics[0], keccak256("BatchMetadataUpdate(uint256,uint256)"));
        assertEq(logs[1].data, abi.encode(uint256(1), uint256(2)));
        assertEq(odo.totalMinted(), 2);
    }

    function test_missingTokenQueriesRejectZeroAndPastSupply() public {
        _mint(alice);
        uint256[3] memory ids = [uint256(0), 2, type(uint256).max];
        for (uint256 i; i < ids.length; ++i) {
            bytes memory error_ = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, ids[i]);
            vm.expectRevert(error_);
            odo.tokenURI(ids[i]);
            vm.expectRevert(error_);
            odo.reading(ids[i]);
            vm.expectRevert(error_);
            odo.refresh(ids[i]);
        }
    }

    function test_supportedInterfacesArePrecise() public view {
        assertEq(odo.name(), "Squeek Odometer");
        assertEq(odo.symbol(), "ODOMETER");
        assertTrue(odo.supportsInterface(0x01ffc9a7)); // ERC-165
        assertTrue(odo.supportsInterface(0x80ac58cd)); // ERC-721
        assertTrue(odo.supportsInterface(0x5b5e139f)); // metadata
        assertTrue(odo.supportsInterface(0x49064906)); // ERC-4906
        assertFalse(odo.supportsInterface(0xffffffff));
        assertFalse(odo.supportsInterface(0x2a55205a)); // no royalties
        assertFalse(odo.supportsInterface(0x780e9d63)); // no enumeration
    }

    function test_all9999MintsAndFinalRejectionWithoutEditingStorage() public {
        // Exercise the full supply. Disable metering only for setup; real calls still execute normally.
        vm.pauseGasMetering();
        for (uint256 i = 1; i < 9_999; ++i) {
            address minter = address(uint160(0x100_000 + i));
            assertEq(_mint(minter), i);
            assertEq(odo.ownerOf(i), minter);
            assertEq(odo.idOf(minter), i);
        }
        vm.resumeGasMetering();
        assertEq(_mint(alice), 9_999);
        vm.prank(bob);
        vm.expectRevert(SqueekOdometer.SoldOut.selector);
        odo.mint();
        assertEq(odo.totalMinted(), 9_999);
        assertEq(odo.idOf(bob), 0);
        assertEq(odo.balanceOf(bob), 0);
        assertEq(odo.startWork(10_000), 0);
    }
}
