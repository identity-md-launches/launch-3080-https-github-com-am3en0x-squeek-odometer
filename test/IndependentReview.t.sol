// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {OdometerArt} from "../src/art/OdometerArt.sol";
import {ISqueekCore} from "../src/interfaces/ISqueek.sol";
import {Reading} from "../src/Types.sol";

// =====================================================================================================================
// Independent review suite. Self-contained (own mocks) so it does not depend on, or edit, the other test files.
// =====================================================================================================================

/// @dev A core whose answers, failures and gas use are all programmable. roundPage only answers the exact window the
/// odometer is specified to ask for (the last three settled rounds, at most 3 records), so a wrong window shows up
/// as an Unknown status that the model does not expect.
contract IRCore {
    uint64 public settled;
    uint64 public work;
    uint64 public height;
    uint64 public pageStart;
    uint64 public pageEnd;
    bool public stateBroken;
    bool public pageBroken;
    uint256 public burn;

    function setState(uint64 settled_, uint64 work_, uint64 height_) external {
        settled = settled_;
        work = work_;
        height = height_;
    }

    function setPage(uint64 start_, uint64 end_) external {
        pageStart = start_;
        pageEnd = end_;
    }

    function setBroken(bool state_, bool page_) external {
        stateBroken = state_;
        pageBroken = page_;
    }

    function setBurn(uint256 burn_) external {
        burn = burn_;
    }

    function _burn() internal view {
        uint256 b = burn;
        if (b == 0) return;
        uint256 stop = gasleft() - b; // underflow when the call has less than `b`: the read fails, as it should
        while (gasleft() > stop) {}
    }

    function state() external view returns (ISqueekCore.CoreState memory s) {
        _burn();
        require(!stateBroken, "state broken");
        s.settledThroughRound = settled;
        s.cumulativeWork = work;
        s.blockHeight = height;
    }

    function roundPage(uint64 afterRound, uint64 throughRound, uint256 maxRecords)
        external
        view
        returns (ISqueekCore.RoundPage memory p)
    {
        _burn();
        require(!pageBroken, "page broken");
        uint64 s = settled;
        require(afterRound == (s > 3 ? s - 3 : 0) && throughRound == s && maxRecords == 3, "unexpected window");
        p.certifiedThroughRound = throughRound;
        p.start.cumulativeWork = pageStart;
        p.end.cumulativeWork = pageEnd;
    }
}

contract IRNFT {
    mapping(address => uint256) public bal;

    function setBalance(address a, uint256 b) external {
        bal[a] = b;
    }

    function balanceOf(address a) external view returns (uint256) {
        return bal[a];
    }
}

contract IRStaking {
    mapping(address => uint256) public power;
    uint256 public burn;

    function setPower(address a, uint256 p) external {
        power[a] = p;
    }

    function setBurn(uint256 b) external {
        burn = b;
    }

    function accountPower(address a) external view returns (uint256, uint256) {
        uint256 b = burn;
        if (b != 0) {
            uint256 stop = gasleft() - b;
            while (gasleft() > stop) {}
        }
        return (power[a], 7e18); // SQK power must never count
    }
}

/// @dev Exposes the internal renderer.
contract IRArt {
    function svg(uint256 id, Reading memory r) external pure returns (bytes memory) {
        return OdometerArt.svg(id, r);
    }

    function json(uint256 id, Reading memory r) external pure returns (bytes memory) {
        return OdometerArt.json(id, r);
    }
}

/// @dev Specification of what a reading must show, written from the brief and the interface, not from the code.
library IRModel {
    uint8 internal constant NAPPING = 0;
    uint8 internal constant JOGGING = 1;
    uint8 internal constant ZOOMIES = 2;
    uint8 internal constant UNKNOWN = 3;

    function stage(uint256 mm) internal pure returns (uint8 s) {
        if (mm >= 1_000_000) s++;
        if (mm >= 5_000_000) s++;
        if (mm >= 10_000_000) s++;
        if (mm >= 25_000_000) s++;
        if (mm >= 50_000_000) s++;
        if (mm >= 100_000_000) s++;
    }

    function tier(uint256 power, uint256 balance) internal pure returns (uint8) {
        if (power >= 113_380e18) return 4;
        if (power >= 23_426e18) return 3;
        if (power >= 4_840e18) return 2;
        if (power > 0 || balance > 0) return 1;
        return 0;
    }

    function status(bool live, uint64 settled, bool pageOk, uint64 start, uint64 end)
        internal
        pure
        returns (uint8, uint256)
    {
        if (!live) return (UNKNOWN, 0);
        if (settled == 0) return (NAPPING, 0);
        if (!pageOk) return (UNKNOWN, 0);
        uint256 w = end > start ? end - start : 0;
        if (w == 0) return (NAPPING, 0);
        return (w >= 1_500 ? ZOOMIES : JOGGING, w);
    }
}

abstract contract IRBase is Test {
    IRCore internal core;
    IRNFT internal nft;
    IRStaking internal staking;
    SqueekOdometer internal odo;
    address internal alice = makeAddr("ir-alice");
    address internal bob = makeAddr("ir-bob");

    function setUp() public virtual {
        core = new IRCore();
        nft = new IRNFT();
        staking = new IRStaking();
        core.setState(10, 11_048, 1_140);
        odo = new SqueekOdometer(address(core), address(nft), address(staking));
    }

    function _decode(bytes memory raw, string memory prefix) internal pure returns (bytes memory) {
        assertEq(Bytes.slice(raw, 0, bytes(prefix).length), bytes(prefix));
        return Base64.decode(string(Bytes.slice(raw, bytes(prefix).length)));
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Unit and fuzz tests: failure paths and edges the other suites leave open
// ---------------------------------------------------------------------------------------------------------------------

contract IndependentEdgeTest is IRBase {
    // ---- existence checks on every token-taking entry point

    function test_everyTokenEntryPointRejectsMissingIds() public {
        uint256[3] memory ids = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < ids.length; i++) {
            bytes memory err = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, ids[i]);
            vm.expectRevert(err);
            odo.refresh(ids[i]);
            vm.expectRevert(err);
            odo.reading(ids[i]);
            vm.expectRevert(err);
            odo.tokenURI(ids[i]);
            vm.expectRevert(err);
            odo.ownerOf(ids[i]);
        }
        vm.prank(alice);
        odo.mint();
        // the next id is still missing once one exists
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 2));
        odo.refresh(2);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 2));
        odo.tokenURI(2);
    }

    function test_refreshAllIsEmptyThenCoversExactlyTheMintedRange() public {
        vm.recordLogs();
        odo.refreshAll();
        assertEq(vm.getRecordedLogs().length, 0, "nothing to refresh");
        vm.prank(alice);
        odo.mint();
        vm.prank(bob);
        odo.mint();
        vm.expectEmit(address(odo));
        emit SqueekOdometer.BatchMetadataUpdate(1, 2);
        vm.prank(makeAddr("stranger"));
        odo.refreshAll();
    }

    // ---- mint needs a real core

    function test_mintRevertsAgainstCoreWithoutCodeAndStoresNothing() public {
        SqueekOdometer o = new SqueekOdometer(makeAddr("eoa-core"), address(nft), address(staking));
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        o.mint();
        assertEq(o.totalMinted(), 0);
        assertEq(o.idOf(alice), 0);
        assertEq(o.balanceOf(alice), 0);
        o.refreshAll();
    }

    function test_mintRevertsWhenCoreReverts() public {
        core.setBroken(true, false);
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
        // a broken round page does not matter for mint, which only reads state()
        core.setBroken(false, true);
        vm.prank(alice);
        assertEq(odo.mint(), 1);
    }

    function test_coreBurningMoreThanTheReadCapCanNeverMint() public {
        core.setBurn(510_000); // above READ_GAS (500,000): the capped read always runs out
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint{gas: 5_000_000}();
        assertEq(odo.totalMinted(), 0);
    }

    // ---- gas starvation: mint is all-or-nothing and a reading is either true or marked degraded

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_mintUnderAnyOuterGasIsAllOrNothing(uint256 gasLimit, uint256 burn, uint64 work) public {
        gasLimit = bound(gasLimit, 25_000, 1_500_000);
        burn = bound(burn, 0, 600_000);
        core.setBurn(burn);
        core.setState(3, work, 9);
        vm.prank(alice);
        (bool ok, bytes memory ret) = address(odo).call{gas: gasLimit}(abi.encodeCall(SqueekOdometer.mint, ()));
        if (ok) {
            assertLe(burn, 500_000, "a read past the cap cannot have succeeded");
            assertEq(abi.decode(ret, (uint256)), 1);
            assertEq(odo.totalMinted(), 1);
            assertEq(odo.idOf(alice), 1);
            assertEq(odo.ownerOf(1), alice);
            assertEq(odo.startWork(1), work, "the baseline is the core's real reading");
        } else {
            assertEq(odo.totalMinted(), 0);
            assertEq(odo.idOf(alice), 0);
            assertEq(odo.balanceOf(alice), 0);
            assertEq(odo.startWork(1), 0);
            // eligibility is intact
            core.setBurn(0);
            vm.prank(alice);
            assertEq(odo.mint(), 1);
            assertEq(odo.startWork(1), work);
        }
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_readingUnderAnyOuterGasNeverMisreportsDistanceOrStatus(
        uint256 gasLimit,
        uint256 burn,
        uint64 extra,
        uint64 pageWork
    ) public {
        vm.prank(alice);
        odo.mint();
        gasLimit = bound(gasLimit, 30_000, 3_000_000);
        burn = bound(burn, 0, 600_000);
        extra = uint64(bound(extra, 0, type(uint64).max - 11_048));
        core.setState(10, 11_048 + extra, 77);
        core.setPage(1_000, 1_000 + uint64(bound(pageWork, 0, 5_000)));
        core.setBurn(burn);
        (uint8 trueStatus, uint256 truePace) = IRModel.status(true, 10, true, core.pageStart(), core.pageEnd());
        try odo.reading{gas: gasLimit}(1) returns (Reading memory r) {
            if (r.live) {
                assertEq(r.work, extra);
                assertEq(r.distanceMm, uint256(extra) * 887);
                assertEq(r.blockHeight, 77);
                assertEq(r.stage, IRModel.stage(uint256(extra) * 887));
            } else {
                assertEq(r.work, 0);
                assertEq(r.distanceMm, 0);
                assertEq(r.status, IRModel.UNKNOWN);
            }
            if (r.status != IRModel.UNKNOWN) {
                assertEq(r.status, trueStatus, "a status that is shown is the true status");
                assertEq(r.pace, truePace);
            } else {
                assertEq(r.pace, 0);
            }
            if (burn > 500_000) assertFalse(r.live, "a read past the cap cannot be live");
        } catch {
            // running out of outer gas is allowed; inventing a value is not
        }
    }

    // ---- the status window is exactly the last three settled rounds

    function test_roundPageIsAskedForExactlyTheLastThreeSettledRounds() public {
        vm.prank(alice);
        odo.mint();
        uint64[7] memory settledValues = [uint64(1), 2, 3, 4, 5, 1_000, type(uint64).max];
        for (uint256 i; i < settledValues.length; i++) {
            uint64 s = settledValues[i];
            core.setState(s, 12_000, 1);
            core.setPage(0, 1_499);
            vm.expectCall(address(core), abi.encodeCall(ISqueekCore.roundPage, (s > 3 ? s - 3 : 0, s, 3)));
            Reading memory r = odo.reading(1);
            assertEq(r.status, IRModel.JOGGING, "IRCore refuses any other window");
            assertEq(r.pace, 1_499);
        }
    }

    function test_noRoundPageReadBeforeTheFirstSettledRound() public {
        vm.prank(alice);
        odo.mint();
        core.setState(0, 99_999, 1);
        core.setBroken(false, true); // a page read would fail, so Napping proves it was not made
        vm.expectCall(address(core), abi.encodeWithSelector(ISqueekCore.roundPage.selector), 0);
        Reading memory r = odo.reading(1);
        assertEq(r.status, IRModel.NAPPING);
        assertEq(r.pace, 0);
        assertTrue(r.live);
    }

    function test_zoomiesLineAndPaceAtTheBoundary() public {
        vm.prank(alice);
        odo.mint();
        uint64[6] memory w = [uint64(0), 1, 1_498, 1_499, 1_500, type(uint64).max - 1];
        for (uint256 i; i < w.length; i++) {
            core.setPage(1, 1 + w[i]);
            Reading memory r = odo.reading(1);
            (uint8 s, uint256 p) = IRModel.status(true, 10, true, 1, 1 + w[i]);
            assertEq(r.status, s);
            assertEq(r.pace, p);
        }
    }

    // ---- holder tier: staking's NFT power first, SQK power ignored, extreme answers clamp

    function test_tierAtExtremeDependencyAnswers() public {
        vm.prank(alice);
        odo.mint();
        staking.setPower(alice, type(uint256).max);
        assertEq(odo.reading(1).tier, 4);
        staking.setPower(alice, 1);
        assertEq(odo.reading(1).tier, 1);
        staking.setPower(alice, 0);
        assertEq(odo.reading(1).tier, 0, "SQK power (7e18 in IRStaking) never counts");
        assertFalse(odo.reading(1).holder);
        nft.setBalance(alice, type(uint256).max);
        assertEq(odo.reading(1).tier, 1);
        assertTrue(odo.reading(1).holder);
    }

    function test_starvedStakingReadFallsBackToWalletBalanceOnly() public {
        vm.prank(alice);
        odo.mint();
        staking.setPower(alice, 200_000e18);
        staking.setBurn(510_000); // the staking read can never finish under the cap
        Reading memory r = odo.reading(1);
        assertEq(r.tier, 0, "no wallet balance: the frame degrades to none, it is never invented");
        nft.setBalance(alice, 1);
        assertEq(odo.reading(1).tier, 1);
    }

    // ---- the renderer over the whole domain the contract can hand it

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_rendererIsTotalOverEveryReachableReading(
        uint256 id,
        uint64 work,
        uint64 startWork,
        uint64 height,
        uint256 pace,
        uint8 status,
        uint8 traits,
        uint8 tier,
        bool live
    ) public {
        IRArt art = new IRArt();
        Reading memory r;
        id = bound(id, 1, 9_999);
        r.live = live;
        r.startWork = startWork;
        r.status = uint8(bound(status, 0, 3));
        if (live) {
            r.work = work;
            r.distanceMm = uint256(work) * 887;
            r.blockHeight = height;
        } else {
            r.status = 3;
        }
        r.stage = IRModel.stage(r.distanceMm);
        r.pace = r.status == 1 || r.status == 2 ? bound(pace, 1, type(uint64).max) : 0;
        r.display = traits % 6;
        r.casing = (traits / 6) % 4;
        r.pouch = (traits / 24) % 5;
        r.tier = uint8(bound(tier, 0, 4));
        r.holder = r.tier > 0;

        string memory j = string(art.json(id, r));
        assertEq(vm.parseJsonString(j, ".name"), string.concat("Squeek Odometer #", vm.toString(id)));
        assertEq(vm.parseJsonArrayLength(j, ".attributes"), 11);
        string[4] memory names = ["Napping", "Jogging", "Zoomies", "Unknown"];
        assertEq(vm.parseJsonString(j, ".attributes[2].value"), names[r.status]);
        assertEq(vm.parseJsonUint(j, ".attributes[8].value"), r.pace);
        assertEq(vm.parseJsonUint(j, ".attributes[9].value"), r.startWork);
        assertEq(vm.parseJsonUint(j, ".attributes[10].value"), r.blockHeight);
        bytes memory s = _decode(bytes(vm.parseJsonString(j, ".image")), "data:image/svg+xml;base64,");
        assertEq(Bytes.slice(s, 0, 5), bytes("<svg "));
        assertEq(Bytes.slice(s, s.length - 6), bytes("</svg>"));
    }

    /// @dev The densest pictures: every display (LED dots draw one element per lit pixel), every status, the bulkiest
    /// treat and frame, the widest digits ("888.88", "88888", the pegged "99999"), twelve pips, the bib and the crown.
    function test_densestScenesStayInsideTheFixedBuffers() public {
        IRArt art = new IRArt();
        uint256[5] memory mm = [uint256(888_880_000), 25_000_000, 88_888_000_000, OdometerArt.MAX_SHOWN_MM, 1_300e6];
        uint256 largest;
        for (uint8 d; d < 6; d++) {
            for (uint8 st; st < 4; st++) {
                for (uint256 k; k < mm.length; k++) {
                    Reading memory r;
                    r.live = true;
                    r.distanceMm = mm[k];
                    r.work = mm[k] / 887;
                    r.stage = IRModel.stage(mm[k]);
                    r.status = st;
                    r.pace = st == 1 || st == 2 ? type(uint64).max : 0;
                    r.display = d;
                    r.casing = 3;
                    r.pouch = 4;
                    r.tier = 4;
                    r.holder = true;
                    r.startWork = type(uint64).max;
                    r.blockHeight = type(uint64).max;
                    bytes memory s = art.svg(9_998, r);
                    if (s.length > largest) largest = s.length;
                    art.json(9_999, r);
                }
            }
        }
        assertLt(largest, 32_768);
        emit log_named_uint("largest svg (bytes)", largest);
    }

    // ---- traits are fixed at mint

    function test_traitsDoNotMoveWithTimeOwnerOrWheel() public {
        vm.prank(alice);
        odo.mint();
        Reading memory a = odo.reading(1);
        vm.warp(block.timestamp + 365 days);
        core.setState(999, type(uint64).max, type(uint64).max);
        core.setPage(0, 10_000);
        vm.prank(alice);
        odo.transferFrom(alice, bob, 1);
        staking.setPower(bob, 1e30);
        Reading memory b = odo.reading(1);
        assertEq(b.display, a.display);
        assertEq(b.casing, a.casing);
        assertEq(b.pouch, a.pouch);
        assertEq(b.startWork, a.startWork);
        assertEq(b.tier, 4, "the frame follows the current owner");
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Invariants: a model of ownership, mint eligibility, baselines and every reading over random call sequences
// ---------------------------------------------------------------------------------------------------------------------

contract IRHandler is Test {
    SqueekOdometer public immutable odo;
    IRCore public immutable core;
    IRNFT public immutable nft;
    IRStaking public immutable staking;

    address[8] public actors;
    mapping(address => uint256) public mintedId;
    mapping(uint256 => address) public minterOf;
    mapping(uint256 => address) public owners;
    mapping(uint256 => uint256) public baselines;
    mapping(uint256 => uint256) public times;
    mapping(uint256 => uint8) public displays;
    mapping(uint256 => uint8) public casings;
    mapping(uint256 => uint8) public pouches;
    mapping(address => uint256) public power;
    mapping(address => uint256) public bal;
    uint256 public count;
    uint256 public failedMints;
    uint256 public transfers;

    constructor(SqueekOdometer odo_, IRCore core_, IRNFT nft_, IRStaking staking_) {
        odo = odo_;
        core = core_;
        nft = nft_;
        staking = staking_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("ir-actor", vm.toString(i)));
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _token(uint256 seed) internal view returns (uint256) {
        return 1 + seed % count;
    }

    function mint(uint256 seed) external {
        address who = _actor(seed);
        if (mintedId[who] != 0) {
            vm.prank(who);
            vm.expectRevert(SqueekOdometer.AlreadyMinted.selector);
            odo.mint();
            return;
        }
        if (core.stateBroken()) {
            vm.prank(who);
            vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
            odo.mint();
            failedMints++;
            return;
        }
        vm.prank(who);
        uint256 id = odo.mint();
        count++;
        assertEq(id, count, "ids are sequential from 1");
        mintedId[who] = id;
        minterOf[id] = who;
        owners[id] = who;
        baselines[id] = core.work();
        times[id] = block.timestamp;
        Reading memory r = odo.reading(id);
        displays[id] = r.display;
        casings[id] = r.casing;
        pouches[id] = r.pouch;
    }

    function transfer(uint256 tokenSeed, uint256 toSeed, uint8 how) external {
        if (count == 0) return;
        uint256 id = _token(tokenSeed);
        address from = owners[id];
        address to = _actor(toSeed);
        address spender = from;
        how = how % 4;
        if (how == 1) {
            spender = _actor(toSeed % 8 + 1);
            vm.prank(from);
            odo.approve(spender, id);
        } else if (how == 2) {
            spender = _actor(toSeed % 8 + 3);
            vm.prank(from);
            odo.setApprovalForAll(spender, true);
        }
        vm.prank(spender);
        if (how == 3) odo.safeTransferFrom(from, to, id);
        else odo.transferFrom(from, to, id);
        if (how == 2 && spender != from) {
            vm.prank(from);
            odo.setApprovalForAll(spender, false);
        }
        owners[id] = to;
        transfers++;
    }

    function unauthorizedTransfer(uint256 tokenSeed, uint256 callerSeed) external {
        if (count == 0) return;
        uint256 id = _token(tokenSeed);
        address who = _actor(callerSeed);
        address owner = owners[id];
        if (who == owner) return;
        vm.prank(who);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, who, id));
        odo.transferFrom(owner, who, id);
        // a non-owner cannot approve itself either
        vm.prank(who);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, who));
        odo.approve(who, id);
    }

    function wrongFromTransfer(uint256 tokenSeed, uint256 fromSeed) external {
        if (count == 0) return;
        uint256 id = _token(tokenSeed);
        address owner = owners[id];
        address fake = _actor(fromSeed);
        if (fake == owner) return;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, fake, id, owner));
        odo.transferFrom(fake, owner, id);
    }

    function setWheel(uint64 settled, uint64 work, uint64 height) external {
        core.setState(settled % 50, work, height);
    }

    function turnWheel(uint32 more) external {
        uint64 w = core.work();
        uint64 add = uint64(bound(more, 0, 2_000_000));
        if (w > type(uint64).max - add) add = 0;
        uint64 h = core.height();
        uint64 s = core.settled();
        core.setState(s < type(uint64).max ? s + 1 : s, w + add, h < type(uint64).max ? h + 1 : h);
    }

    function setPage(uint64 start, uint64 end) external {
        core.setPage(start, end);
    }

    function setBroken(bool state_, bool page_) external {
        core.setBroken(state_, page_);
    }

    function setPower(uint256 actorSeed, uint256 p) external {
        address a = _actor(actorSeed);
        p = p % 4 == 0 ? 0 : bound(p, 0, 200_000e18);
        power[a] = p;
        staking.setPower(a, p);
    }

    function setBalance(uint256 actorSeed, uint8 b) external {
        address a = _actor(actorSeed);
        bal[a] = b % 3;
        nft.setBalance(a, b % 3);
    }

    function refresh(uint256 tokenSeed, uint256 callerSeed) external {
        vm.startPrank(_actor(callerSeed));
        odo.refreshAll();
        if (count > 0) odo.refresh(_token(tokenSeed));
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, count + 1));
        odo.refresh(count + 1);
        vm.stopPrank();
    }

    function warp(uint32 dt) external {
        vm.warp(block.timestamp + dt);
    }

    function actorList() external view returns (address[8] memory) {
        return actors;
    }
}

contract IndependentInvariantTest is Test {
    SqueekOdometer internal odo;
    IRCore internal core;
    IRHandler internal handler;

    function setUp() public {
        core = new IRCore();
        IRNFT nft = new IRNFT();
        IRStaking staking = new IRStaking();
        core.setState(5, 11_048, 1);
        odo = new SqueekOdometer(address(core), address(nft), address(staking));
        handler = new IRHandler(odo, core, nft, staking);
        targetContract(address(handler));
        bytes4[] memory s = new bytes4[](13);
        s[0] = IRHandler.mint.selector;
        s[1] = IRHandler.mint.selector; // weighted: minting drives the rest
        s[2] = IRHandler.transfer.selector;
        s[3] = IRHandler.unauthorizedTransfer.selector;
        s[4] = IRHandler.wrongFromTransfer.selector;
        s[5] = IRHandler.setWheel.selector;
        s[6] = IRHandler.turnWheel.selector;
        s[7] = IRHandler.setPage.selector;
        s[8] = IRHandler.setBroken.selector;
        s[9] = IRHandler.setPower.selector;
        s[10] = IRHandler.setBalance.selector;
        s[11] = IRHandler.refresh.selector;
        s[12] = IRHandler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: s}));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 48
    function invariant_supplyEqualsMintsAndBalances() public view {
        uint256 count = handler.count();
        assertEq(odo.totalMinted(), count);
        assertLe(count, odo.MAX_SUPPLY());
        address[8] memory actors = handler.actorList();
        uint256 balances;
        uint256 minters;
        for (uint256 i; i < actors.length; ++i) {
            balances += odo.balanceOf(actors[i]);
            uint256 id = odo.idOf(actors[i]);
            assertEq(id, handler.mintedId(actors[i]));
            if (id != 0) {
                minters++;
                assertEq(handler.minterOf(id), actors[i], "idOf is the minter's own id");
            }
        }
        assertEq(balances, count, "every token is held by someone in the actor set");
        assertEq(minters, count, "one wallet, one token: no wallet minted twice");
        assertEq(address(odo).balance, 0, "the odometer never holds ether");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 48
    function invariant_ownersBaselinesAndTraitsAreFrozen() public view {
        uint256 count = handler.count();
        for (uint256 id = 1; id <= count; ++id) {
            assertEq(odo.ownerOf(id), handler.owners(id));
            assertEq(odo.getApproved(id), address(0), "approvals are cleared by every transfer");
            assertEq(odo.startWork(id), handler.baselines(id));
            assertEq(odo.mintedAt(id), handler.times(id));
            Reading memory r = odo.reading(id);
            assertEq(r.startWork, handler.baselines(id));
            assertEq(r.display, handler.displays(id));
            assertEq(r.casing, handler.casings(id));
            assertEq(r.pouch, handler.pouches(id));
        }
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 48
    function invariant_everyReadingMatchesTheSpecification() public view {
        uint256 count = handler.count();
        bool live = !core.stateBroken();
        uint64 work = core.work();
        (uint8 status, uint256 pace) =
            IRModel.status(live, core.settled(), !core.pageBroken(), core.pageStart(), core.pageEnd());
        for (uint256 id = 1; id <= count; ++id) {
            Reading memory r = odo.reading(id);
            uint256 base = handler.baselines(id);
            uint256 w = live && work > base ? work - base : 0;
            assertEq(r.live, live);
            assertEq(r.work, w);
            assertEq(r.distanceMm, w * 887);
            assertEq(r.stage, IRModel.stage(w * 887));
            assertEq(r.blockHeight, live ? core.height() : 0);
            assertEq(r.status, status);
            assertEq(r.pace, pace);
            address owner = handler.owners(id);
            uint8 tier = IRModel.tier(handler.power(owner), handler.bal(owner));
            assertEq(r.tier, tier);
            assertEq(r.holder, tier > 0);
        }
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 32
    function invariant_latestTokenUriAlwaysRenders() public view {
        uint256 count = handler.count();
        if (count == 0) return;
        bytes memory uri = bytes(odo.tokenURI(count));
        bytes memory prefix = bytes("data:application/json;base64,");
        assertEq(Bytes.slice(uri, 0, prefix.length), prefix);
        assertGt(uri.length, 2_000);
    }
}
