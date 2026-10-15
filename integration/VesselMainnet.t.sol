// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SelloutMachine} from "../src/SelloutMachine.sol";
import {SupplyMock} from "../test/mocks/SupplyMocks.sol";
import {IVessel, IVesselRelics} from "./IVessel.sol";

/// @notice Real-mainnet integration. Invoke with the mainnet profile and a fork at block 26,200,148.
/// @dev Never skips, creates a mock Vessel, etches live code, or rewrites Vessel storage.
contract VesselMainnetTest is Test {
    address private constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    address private constant VESSEL = 0xECb92Cc7112b80A2234936315BbB493fb48d1463;
    address private constant RENDERER = 0x85c7D2933f178A02Ee9AAC0E654094EaDAca48a2;
    bytes32 private constant VESSEL_CODE_HASH =
        0x991e261d56406937caf1763b003b962cbd11bab4e2dfd273926d91a11447f659;
    bytes32 private constant RENDERER_CODE_HASH =
        0xeb3af5bd334b536c7aed1633c42371e4acce9a105ae07f23c7178e7c7d68bbae;

    IVessel private constant vessel = IVessel(VESSEL);
    SelloutMachine private machine;
    SupplyMock private collection;

    function setUp() public {
        assertEq(block.chainid, 1, "requires --fork-url Ethereum mainnet");
        assertEq(block.number, 26_200_148, "requires the documented --fork-block-number");
        assertEq(VESSEL.codehash, VESSEL_CODE_HASH, "unexpected Vessel bytecode");
        assertEq(vessel.renderer(), RENDERER);
        assertEq(RENDERER.codehash, RENDERER_CODE_HASH, "unexpected renderer bytecode");
        assertEq(vessel.ownerOf(10_000), OWNER);
        assertTrue(vessel.craftToMachineStatus(10_000));
        assertEq(vessel.craftToType(10_000), "Machine");
        assertEq(vessel.craftToColorMode(10_000), 0, "Craft must use grayscale");
        assertFalse(vessel.craftToLocked(10_000));
        assertFalse(IVesselRelics(vessel.relics()).isRelic(10_000), "Relic routing overrides Machine");
        machine = new SelloutMachine(OWNER);
        collection = new SupplyMock();
    }

    function _attach() private {
        vm.prank(vessel.ownerOf(10_000));
        vessel.setMachineHolder(10_000, address(machine));
        assertEq(vessel.craftToMachine(10_000), address(machine));
    }

    function _configure() private {
        vm.prank(OWNER);
        machine.setTrackedCollection(address(collection));
    }

    function _assertPayload(uint256 supply) private {
        collection.setSupply(supply);
        bytes memory payload = vessel.craftToPayload(10_000);
        uint256 count = supply > 10_000 ? 10_000 : supply;
        assertEq(payload.length, 10_000);
        assertEq(keccak256(payload), keccak256(machine.craftToPayload(10_000)));
        for (uint256 i; i < 10_000; ++i) {
            if (uint8(payload[i]) != (i < count ? 0 : 255)) revert("wrong Vessel pixel");
        }
    }

    function test_mainnetAuthorizedAttachmentAndUnconfiguredPayload() public {
        uint256 beforeGas = gasleft();
        _attach();
        emit log_named_uint("attachment plus routing assertion gas", beforeGas - gasleft());
        _assertPayload(0);
    }

    function test_mainnetRejectsUnauthorizedAttachment() public {
        address previous = vessel.craftToMachine(10_000);
        vm.prank(address(this));
        vm.expectRevert(bytes4(keccak256("MustBeHolderOrDelegate()")));
        vessel.setMachineHolder(10_000, address(machine));
        assertEq(vessel.craftToMachine(10_000), previous);
    }

    function test_mainnetPayloadMilestonesAndGas() public {
        _attach();
        _configure();
        uint256[8] memory counts = [uint256(0), 1, 100, 101, 5000, 9999, 10_000, type(uint256).max];
        for (uint256 i; i < counts.length; ++i) {
            collection.setSupply(counts[i]);
            uint256 beforeGas = gasleft();
            bytes memory payload = vessel.craftToPayload(10_000);
            uint256 used = beforeGas - gasleft();
            uint256 calleeGas = vm.lastCallGas().gasTotalUsed;
            emit log_named_uint("supply", counts[i]);
            emit log_named_uint("Vessel payload call gas (warm)", used);
            emit log_named_uint("Vessel payload execution gas (warm, callee only)", calleeGas);
            assertLt(used, 100_000);
            assertEq(payload.length, 10_000);
            _assertPayload(counts[i]);
        }
    }

    function test_mainnetCollectionChangeBurnAndFailureNeedNoReattachment() public {
        _attach();
        _configure();
        _assertPayload(5000);
        _assertPayload(101);
        collection.setBehavior(SupplyMock.Behavior.Reverts);
        bytes memory white = vessel.craftToPayload(10_000);
        for (uint256 i; i < white.length; ++i) {
            if (white[i] != 0xff) revert("failure must render white");
        }
        collection = new SupplyMock();
        _configure();
        _assertPayload(9999);
        assertEq(vessel.craftToMachine(10_000), address(machine));
    }

    // Full SVG hashes are generated independently by tools/svg_vectors.py, not by the renderer.
    // Matching all bytes checks all 10,000 x/y coordinates and RGB triples, including both ends.
    function _checkSVG(uint256 count, bytes32 expected) private {
        _attach();
        _configure();
        collection.setSupply(count);
        uint256 beforeGas = gasleft();
        string memory svg = vessel.craftToSVG(10_000);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("black pixels", count);
        emit log_named_uint("Vessel SVG call gas (includes existing renderer)", used);
        emit log_named_uint("SVG bytes", bytes(svg).length);
        assertEq(bytes(svg).length, 658_122 - count * 6);
        assertEq(sha256(bytes(svg)), expected, "full SVG differs from row-major grayscale oracle");
        assertLt(used, 800_000_000, "existing renderer gas regression");
    }

    function test_mainnetSVG0() public {
        _checkSVG(0, 0x46764e7817d0ff114dc23337f05c751a3f963cdcfbcc71e46b9586f76cefdf12);
    }

    function test_mainnetSVG1() public {
        _checkSVG(1, 0xdbc08ac2d2f231d09de7a3ff7991d7a65ec300de5a9fe179b4e4784dd6854886);
    }

    function test_mainnetSVG100() public {
        _checkSVG(100, 0x0eb485a25a04f3250dccacfadb5aa0e71daa3a07fae426c6f2ef0aa0cb3c03b3);
    }

    function test_mainnetSVG101() public {
        _checkSVG(101, 0x3bf7607f1ab679f1d10cf784d8de01adf543c7befcd932cd918303dee244d1bc);
    }

    function test_mainnetSVG5000() public {
        _checkSVG(5000, 0x978f0c8383763f7ae83314995797b99f1d26e651e60831aa3e2006188b873046);
    }

    function test_mainnetSVG9999() public {
        _checkSVG(9999, 0xa21dc837327e077930da62c44f71a01f9db0d070b10074df94e566b30e26e3a4);
    }

    function test_mainnetSVG10000() public {
        _checkSVG(10_000, 0xe4d795c069b8601b58ead37191219c553b744c4a9de365c2b497db1a5f92a5a1);
    }
}
