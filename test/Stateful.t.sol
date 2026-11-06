// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {Reading} from "../src/Types.sol";
import {MockCore, MockNFT, MockStaking} from "./mocks/Mocks.sol";

/// @dev A separate model of successful minting, baseline persistence and ownership over arbitrary action sequences.
contract OdometerHandler is Test {
    SqueekOdometer public immutable odo;
    MockCore public immutable core;
    address[16] public actors;
    mapping(address => uint256) public minted;
    mapping(uint256 => address) public owners;
    mapping(uint256 => uint256) public baselines;
    mapping(uint256 => uint256) public times;
    uint256 public count;
    uint64 public currentWork = 11_048;
    bool public broken;

    constructor(SqueekOdometer odo_, MockCore core_) {
        odo = odo_;
        core = core_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
        }
    }

    function mint(uint8 actor) external {
        address who = actors[actor % actors.length];
        vm.prank(who);
        if (minted[who] != 0 || broken) {
            vm.expectRevert(
                minted[who] != 0 ? SqueekOdometer.AlreadyMinted.selector : SqueekOdometer.CoreUnreadable.selector
            );
            odo.mint();
            return;
        }
        uint256 id = odo.mint();
        count++;
        assertEq(id, count);
        minted[who] = id;
        owners[id] = who;
        baselines[id] = currentWork;
        times[id] = block.timestamp;
    }

    function transfer(uint8 token, uint8 to) external {
        if (count == 0) return;
        uint256 id = 1 + token % count;
        address recipient = actors[to % actors.length];
        vm.prank(owners[id]);
        odo.transferFrom(owners[id], recipient, id);
        owners[id] = recipient;
    }

    function unauthorizedTransfer(uint8 token, uint8 caller) external {
        if (count == 0) return;
        uint256 id = 1 + token % count;
        address who = actors[caller % actors.length];
        if (who == owners[id]) return;
        vm.prank(who);
        vm.expectRevert();
        odo.transferFrom(owners[id], who, id);
    }

    function setCore(uint64 work, bool unavailable) external {
        currentWork = work;
        broken = unavailable;
        core.set(0, work, 1);
        core.setBroken(unavailable);
    }

    function refresh(uint8 token, uint8 caller) external {
        vm.startPrank(actors[caller % actors.length]);
        odo.refreshAll();
        if (count > 0) odo.refresh(1 + token % count);
        vm.stopPrank();
    }
}

contract OdometerStatefulTest is Test {
    SqueekOdometer internal odo;
    OdometerHandler internal handler;

    function setUp() public {
        vm.chainId(31337);
        MockCore core = new MockCore();
        core.set(0, 11_048, 1);
        odo = new SqueekOdometer(address(core), address(new MockNFT()), address(new MockStaking()));
        handler = new OdometerHandler(odo, core);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.mint.selector;
        selectors[1] = handler.transfer.selector;
        selectors[2] = handler.unauthorizedTransfer.selector;
        selectors[3] = handler.setCore.selector;
        selectors[4] = handler.refresh.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyOwnershipAndPermanentBaselines() public view {
        uint256 count = handler.count();
        assertEq(odo.totalMinted(), count);
        assertLe(count, odo.MAX_SUPPLY());
        uint256 balances;
        uint256 mintedWallets;
        for (uint256 i; i < 16; ++i) {
            address actor = handler.actors(i);
            assertEq(odo.idOf(actor), handler.minted(actor));
            if (handler.minted(actor) != 0) mintedWallets++;
            balances += odo.balanceOf(actor);
        }
        assertEq(balances, count);
        assertEq(mintedWallets, count);
        assertEq(address(odo).balance, 0);
        for (uint256 id = 1; id <= count; ++id) {
            assertEq(odo.ownerOf(id), handler.owners(id));
            assertEq(odo.startWork(id), handler.baselines(id));
            assertEq(odo.mintedAt(id), handler.times(id));
            Reading memory r = odo.reading(id);
            uint256 work = handler.currentWork();
            uint256 baseline = handler.baselines(id);
            uint256 expected = !handler.broken() && work > baseline ? work - baseline : 0;
            assertEq(r.distanceMm, expected * 887);
            assertEq(r.live, !handler.broken());
            assertEq(r.status, handler.broken() ? odo.UNKNOWN() : odo.NAPPING());
        }
    }
}
