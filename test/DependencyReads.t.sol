// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {ISqueekCore, ISqueekNFT, ISqueekStaking} from "../src/interfaces/ISqueek.sol";
import {Reading} from "../src/Types.sol";
import {OdometerTestBase} from "./helpers/OdometerTestBase.sol";
import {RawDependency} from "./mocks/Adversaries.sol";

contract OdometerDependencyTest is OdometerTestBase {
    function test_missingDependencyCodeDoesNotBreakExistingMetadata() public {
        _mint(alice);
        vm.etch(address(core), hex"");
        vm.etch(address(nft), hex"");
        vm.etch(address(staking), hex"");
        Reading memory r = odo.reading(1);
        assertFalse(r.live);
        assertFalse(r.holder);
        assertEq(r.status, odo.UNKNOWN());
        assertEq(r.distanceMm, 0);
        assertEq(r.startWork, 11_048);
        _assertMetadata(1);
    }

    function testFuzz_shortStateCannotBeMistakenForAReading(uint8 count) public {
        _mint(alice);
        uint256 length = bound(count, 0, 127);
        vm.mockCall(address(core), abi.encodeCall(ISqueekCore.state, ()), new bytes(length));
        Reading memory r = odo.reading(1);
        assertFalse(r.live);
        assertEq(r.status, odo.UNKNOWN());
        assertEq(r.distanceMm, 0);
        assertEq(r.startWork, 11_048);
    }

    function testFuzz_shortStateMintRevertsAndRollsBack(uint8 count) public {
        uint256 length = bound(count, 0, 63);
        vm.mockCall(address(core), abi.encodeCall(ISqueekCore.state, ()), new bytes(length));
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
        assertEq(odo.totalMinted(), 0);
        assertEq(odo.idOf(alice), 0);
        assertEq(odo.mintedAt(1), 0);
    }

    function test_mintReadsTwoWordsButMetadataRequiresFour() public {
        vm.mockCall(address(core), abi.encodeCall(ISqueekCore.state, ()), abi.encode(uint256(0), uint256(42)));
        _mint(alice);
        assertEq(odo.startWork(1), 42);
        assertFalse(odo.reading(1).live);
        _assertMetadata(1);
        vm.mockCall(
            address(core),
            abi.encodeCall(ISqueekCore.state, ()),
            abi.encode(uint256(0), uint256(43), uint256(0), uint256(99))
        );
        Reading memory r = odo.reading(1);
        assertTrue(r.live);
        assertEq(r.distanceMm, 887);
        assertEq(r.blockHeight, 99);
        assertEq(r.status, odo.NAPPING());
    }

    function testFuzz_shortRoundPageGivesUnknownWithoutLosingDistance(uint8 count) public {
        _mint(alice);
        core.set(10, 12_048, 1_200);
        vm.mockCall(
            address(core), abi.encodeWithSelector(ISqueekCore.roundPage.selector), new bytes(bound(count, 0, 191))
        );
        Reading memory r = odo.reading(1);
        assertTrue(r.live);
        assertEq(r.distanceMm, 887_000);
        assertEq(r.status, odo.UNKNOWN());
        assertEq(r.pace, 0);
    }

    function test_roundPageExactPrefixLengthAndRevertingPage() public {
        _mint(alice);
        bytes memory prefix = abi.encode(uint256(32), uint256(10), uint256(500), uint256(0), uint256(0), uint256(2_000));
        vm.mockCall(address(core), abi.encodeWithSelector(ISqueekCore.roundPage.selector), prefix);
        assertEq(odo.reading(1).status, odo.ZOOMIES());
        assertEq(odo.reading(1).pace, 1_500);
        vm.mockCallRevert(address(core), abi.encodeWithSelector(ISqueekCore.roundPage.selector), hex"1234");
        Reading memory r = odo.reading(1);
        assertTrue(r.live);
        assertEq(r.status, odo.UNKNOWN());
        _assertMetadata(1);
    }

    function testFuzz_roundWindowAndPace(uint64 settled, uint64 start, uint64 end) public {
        _mint(alice);
        core.set(settled, 12_048, 1);
        if (settled == 0) {
            assertEq(odo.reading(1).status, odo.NAPPING());
            assertEq(odo.reading(1).pace, 0);
            return;
        }
        uint64 from = settled > 3 ? settled - 3 : 0;
        bytes memory callData = abi.encodeCall(ISqueekCore.roundPage, (from, settled, 3));
        bytes memory prefix =
            abi.encode(uint256(32), uint256(settled), uint256(start), uint256(0), uint256(0), uint256(end));
        vm.mockCall(address(core), callData, prefix);
        vm.expectCall(address(core), callData);
        Reading memory r = odo.reading(1);
        uint256 pace = end > start ? uint256(end) - start : 0;
        assertEq(r.pace, pace);
        assertEq(r.status, pace == 0 ? odo.NAPPING() : pace < 1_500 ? odo.JOGGING() : odo.ZOOMIES());
    }

    function test_earlyRoundsUseZeroOriginAndZeroRoundsSkipPageRead() public {
        _mint(alice);
        // A broken roundPage is irrelevant before any settled round exists.
        vm.mockCallRevert(address(core), abi.encodeWithSelector(ISqueekCore.roundPage.selector), hex"1234");
        core.set(0, 11_048, 1);
        assertEq(odo.reading(1).status, odo.NAPPING());
        vm.clearMockedCalls();
        for (uint64 settled = 1; settled <= 4; ++settled) {
            core.set(settled, 11_048, 1);
            uint64 from = settled <= 3 ? 0 : 1;
            vm.expectCall(address(core), abi.encodeCall(ISqueekCore.roundPage, (from, settled, 3)));
            assertEq(odo.reading(1).status, odo.NAPPING());
        }
    }

    function test_decreasingRoundWorkClampsPaceToZero() public {
        _mint(alice);
        vm.mockCall(
            address(core),
            abi.encodeWithSelector(ISqueekCore.roundPage.selector),
            abi.encode(uint256(32), uint256(10), uint256(100), uint256(0), uint256(0), uint256(99))
        );
        Reading memory r = odo.reading(1);
        assertEq(r.pace, 0);
        assertEq(r.status, odo.NAPPING());
    }

    function test_holderFallbackIgnoresSQKPowerAndUsesNFTPowerOnly() public {
        _mint(alice);
        vm.mockCall(
            address(staking),
            abi.encodeCall(ISqueekStaking.accountPower, (alice)),
            abi.encode(uint256(0), type(uint256).max)
        );
        assertFalse(odo.reading(1).holder);
        nft.setBalance(alice, 1);
        assertEq(odo.reading(1).tier, 1);
        vm.mockCallRevert(address(staking), abi.encodeCall(ISqueekStaking.accountPower, (alice)), hex"12");
        assertEq(odo.reading(1).tier, 1, "wallet is checked after a failed staking read");
    }

    function test_shortHolderResponsesAreNotBalances() public {
        _mint(alice);
        bytes memory short = new bytes(31);
        short[0] = 0xff;
        vm.mockCall(address(staking), abi.encodeCall(ISqueekStaking.accountPower, (alice)), short);
        vm.mockCall(address(nft), abi.encodeCall(ISqueekNFT.balanceOf, (alice)), short);
        assertFalse(odo.reading(1).holder);
        assertEq(odo.reading(1).tier, 0);
        vm.mockCall(address(nft), abi.encodeCall(ISqueekNFT.balanceOf, (alice)), abi.encode(uint256(1)));
        assertEq(odo.reading(1).tier, 1);
    }

    function test_tierBoundariesAndStakingPrecedence() public {
        _mint(alice);
        uint256[9] memory powers = [
            uint256(0),
            1,
            4_840e18 - 1,
            4_840e18,
            23_426e18 - 1,
            23_426e18,
            113_380e18 - 1,
            113_380e18,
            type(uint256).max
        ];
        uint8[9] memory tiers = [0, 1, 1, 2, 2, 3, 3, 4, 4];
        for (uint256 i; i < powers.length; ++i) {
            staking.setPower(alice, powers[i]);
            Reading memory r = odo.reading(1);
            assertEq(r.tier, tiers[i]);
            assertEq(r.holder, tiers[i] != 0);
        }
        nft.setBroken(true);
        assertEq(odo.reading(1).tier, 4, "positive stake does not need a wallet read");
    }

    function test_allCallsRemainStatic() public {
        RawDependency attacker = new RawDependency();
        attacker.configure(RawDependency.Mode.Write, abi.encode(uint256(0), uint256(10), uint256(0), uint256(1)));
        SqueekOdometer target = new SqueekOdometer(address(attacker), address(nft), address(staking));
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        target.mint();
        assertEq(attacker.writes(), 0);
        attacker.configure(RawDependency.Mode.Answer, abi.encode(uint256(0), uint256(10), uint256(0), uint256(1)));
        vm.prank(alice);
        target.mint();
        attacker.configure(RawDependency.Mode.Write, "");
        assertFalse(target.reading(1).live);
        assertEq(attacker.writes(), 0);
    }

    function test_returnDataBombCopiesOnlyRequestedPrefix() public {
        RawDependency attacker = new RawDependency();
        attacker.configure(RawDependency.Mode.ReturnBomb, abi.encode(uint256(0), uint256(42), uint256(0), uint256(99)));
        odo = new SqueekOdometer(address(attacker), address(nft), address(staking));
        _mint(alice);
        assertEq(odo.startWork(1), 42);
        assertTrue(odo.reading(1).live);
        assertEq(odo.reading(1).blockHeight, 99);
        _assertMetadata(1);
    }

    function test_revertDataBombBecomesUnknownAndMintRevertsCleanly() public {
        RawDependency attacker = new RawDependency();
        attacker.configure(RawDependency.Mode.Answer, abi.encode(uint256(0), uint256(42), uint256(0), uint256(1)));
        odo = new SqueekOdometer(address(attacker), address(nft), address(staking));
        _mint(alice);
        attacker.configure(RawDependency.Mode.RevertBomb, "");
        assertFalse(odo.reading(1).live);
        _assertMetadata(1);
        vm.prank(bob);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
        assertEq(odo.totalMinted(), 1);
    }

    function test_threeGasBurningDependenciesStillPermitMetadataWithinBudget() public {
        RawDependency attacker = new RawDependency();
        attacker.configure(RawDependency.Mode.Burn, "");
        // Independent instances exercise three real gas-burning calls in one reading.
        RawDependency holder = new RawDependency();
        holder.configure(RawDependency.Mode.Burn, "");
        RawDependency staker = new RawDependency();
        staker.configure(RawDependency.Mode.Burn, "");
        SqueekOdometer target = new SqueekOdometer(address(attacker), address(holder), address(staker));
        attacker.configure(RawDependency.Mode.Answer, abi.encode(uint256(0), uint256(42), uint256(0), uint256(1)));
        vm.prank(alice);
        target.mint();
        attacker.configure(RawDependency.Mode.Burn, "");
        (bool ok, bytes memory result) =
            address(target).staticcall{gas: 8_000_000}(abi.encodeCall(SqueekOdometer.tokenURI, (1)));
        assertTrue(ok, "gas-capped failures should leave enough gas to render");
        assertGt(bytes(abi.decode(result, (string))).length, 1_000);
        Reading memory r = target.reading(1);
        assertFalse(r.live);
        assertFalse(r.holder);
        assertEq(r.status, target.UNKNOWN());
    }

    function test_roundPageGasBurnDoesNotHideLiveDistance() public {
        _mint(alice);
        RawDependency attacker = new RawDependency();
        attacker.configure(RawDependency.Mode.Burn, "");
        // Mock only state(). roundPage() executes the actual burner.
        vm.etch(address(core), address(attacker).code);
        // RawDependency.mode occupies slot zero; write its test fixture, not odometer state.
        vm.store(address(core), bytes32(0), bytes32(uint256(RawDependency.Mode.Burn)));
        vm.mockCall(
            address(core),
            abi.encodeCall(ISqueekCore.state, ()),
            abi.encode(uint256(10), uint256(12_048), uint256(0), uint256(1_200))
        );
        Reading memory r = odo.reading(1);
        assertTrue(r.live);
        assertEq(r.distanceMm, 887_000);
        assertEq(r.status, odo.UNKNOWN());
        _assertMetadata(1);
    }
}
