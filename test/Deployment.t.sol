// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";

/// @dev A local factory rehearsal, not the launch's factory and never broadcast.
contract OdometerDeploymentProbe {
    function deploy(bytes memory initcode, bytes32 salt) external payable returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(callvalue(), add(initcode, 32), mload(initcode), salt)
        }
    }
}

contract OdometerDeploymentTest is Test {
    address constant CORE = 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4;
    address constant NFT = 0xC4C7982657f00509548F3a3a41db7FA439a6856B;
    address constant STAKING = 0x50fd1780526C3186A0c037c7622203bC4fb611ca;

    function _code() internal pure returns (bytes memory) {
        return bytes.concat(type(SqueekOdometer).creationCode, abi.encode(CORE, NFT, STAKING));
    }

    function test_factoryDeploymentOnEmptySepolia() public {
        vm.chainId(11155111);
        assertEq(CORE.code.length + NFT.code.length + STAKING.code.length, 0);
        OdometerDeploymentProbe factory = new OdometerDeploymentProbe();
        bytes memory initcode = _code();
        bytes32 salt = keccak256("odometer rehearsal");
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(initcode)))))
        );
        address deployed = factory.deploy(initcode, salt);
        assertEq(deployed, predicted);
        assertGt(deployed.code.length, 0);
        assertLe(deployed.code.length, 24_576);
        assertLe(initcode.length, 49_152);
        SqueekOdometer odo = SqueekOdometer(deployed);
        assertEq(address(odo.core()), CORE);
        assertEq(address(odo.squeeks()), NFT);
        assertEq(address(odo.staking()), STAKING);
        assertEq(odo.totalMinted(), 0);
        assertEq(deployed.balance, 0);
        // No code is required at any dependency during construction, but mint needs a real reading.
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
    }

    function test_constructorRejectsValue() public {
        vm.chainId(11155111);
        OdometerDeploymentProbe factory = new OdometerDeploymentProbe();
        vm.deal(address(this), 1);
        assertEq(factory.deploy{value: 1}(_code(), bytes32(uint256(1))), address(0));
    }

    /// @dev The launch rehearses the constructor from its factory on an empty chain whose id is not Sepolia's, with
    /// another wallet as tx.origin: it must deploy there, and nothing about the deployer may reach storage.
    function testFuzz_constructorDeploysOnAnyChainFromAnyFactory(uint64 chain, address factory, address origin) public {
        vm.assume(factory != address(0) && factory.code.length == 0 && uint160(factory) > 0xffff);
        vm.chainId(chain);
        OdometerDeploymentProbe implementation = new OdometerDeploymentProbe();
        vm.etch(factory, address(implementation).code);
        vm.prank(origin, origin);
        address deployed = OdometerDeploymentProbe(factory).deploy(_code(), bytes32(uint256(chain)));
        assertGt(deployed.code.length, 0, "constructor must not revert on a rehearsal chain");
        SqueekOdometer odo = SqueekOdometer(deployed);
        assertEq(address(odo.core()), CORE);
        assertEq(address(odo.squeeks()), NFT);
        assertEq(address(odo.staking()), STAKING);
        // no owner, admin or role resolves to the factory or to the origin: there are no such functions at all
        (bool ok,) = deployed.staticcall(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
        (ok,) = deployed.staticcall(abi.encodeWithSignature("getOwner()"));
        assertFalse(ok);
        (ok,) = deployed.staticcall(abi.encodeWithSignature("DEFAULT_ADMIN_ROLE()"));
        assertFalse(ok);
    }

    function test_runtimeHasNoEscapeOpcodes() public {
        vm.chainId(11155111);
        bytes memory code = address(new SqueekOdometer(CORE, NFT, STAKING)).code;
        bool reachable = true;
        for (uint256 j; j < code.length; ++j) {
            uint8 op = uint8(code[j]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                j += op - 0x5f;
                continue;
            }
            if (reachable) assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) reachable = false;
        }
    }

    function test_noOwnerAdminInitializerOrUpgradeEntryPoint() public {
        vm.chainId(11155111);
        SqueekOdometer odo = new SqueekOdometer(CORE, NFT, STAKING);
        bytes4[6] memory selectors = [
            bytes4(keccak256("owner()")),
            bytes4(keccak256("admin()")),
            bytes4(keccak256("initialize(address)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("pause()"))
        ];
        for (uint256 i; i < selectors.length; ++i) {
            (bool ok,) = address(odo).call(abi.encodeWithSelector(selectors[i], address(this)));
            assertFalse(ok, "unexpected privileged entry point");
        }
    }
}
