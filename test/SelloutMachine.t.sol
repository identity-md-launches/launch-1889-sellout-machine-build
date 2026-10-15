// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SelloutMachine} from "../src/SelloutMachine.sol";
import {IMachine} from "../src/interfaces/IMachine.sol";
import {SupplyMock, InterfaceMock, SupplyOnlyMock, MissingSupplyMock} from "./mocks/SupplyMocks.sol";

contract DeploymentFactoryMock {
    function deploy(address owner) external returns (SelloutMachine) {
        return new SelloutMachine{salt: bytes32(uint256(1))}(owner);
    }
}

contract SelloutMachineTest is Test {
    address internal constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    SelloutMachine internal machine;
    SupplyMock internal collection;

    event TrackedCollectionUpdated(address indexed previousCollection, address indexed newCollection);

    function setUp() public {
        machine = new SelloutMachine(OWNER);
        collection = new SupplyMock();
    }

    function _configure(SupplyMock target) internal {
        vm.prank(OWNER);
        machine.setTrackedCollection(address(target));
    }

    // The reference algorithm deliberately checks individual bytes, independently of word stores.
    function _assertPixels(bytes memory payload, uint256 count) internal pure {
        assertEq(payload.length, 10_000);
        uint256 blacks;
        for (uint256 i; i < payload.length; ++i) {
            if (uint8(payload[i]) != (i < count ? 0 : 255)) {
                revert("incorrect grayscale byte or pixel order");
            }
            if (payload[i] == 0x00) ++blacks;
        }
        assertEq(blacks, count);
    }

    function _checkSupply(uint256 supply) internal {
        collection.setSupply(supply);
        _configure(collection);
        uint256 count = supply > 10_000 ? 10_000 : supply;
        assertEq(machine.mintedCount(), count);
        assertEq(machine.mintProgress(), count);
        _assertPixels(machine.craftToPayload(10_000), count);
    }

    function test_unconfiguredIsWhite() public view {
        assertEq(machine.owner(), OWNER);
        assertEq(machine.trackedCollection(), address(0));
        assertEq(machine.mintedCount(), 0);
        assertEq(machine.mintProgress(), 0);
        assertEq(IMachine(address(machine)).name(), "The Sellout Machine");
        _assertPixels(IMachine(address(machine)).craftToPayload(10_000), 0);
    }

    function test_pixels0() public {
        _checkSupply(0);
    }

    function test_pixels1() public {
        _checkSupply(1);
    }

    function test_pixels100() public {
        _checkSupply(100);
    }

    function test_pixels101() public {
        _checkSupply(101);
    }

    function test_pixels5000() public {
        _checkSupply(5000);
    }

    function test_pixels9999() public {
        _checkSupply(9999);
    }

    function test_pixels10000() public {
        _checkSupply(10_000);
    }

    function test_supplyOverflowIsClamped() public {
        _checkSupply(type(uint256).max);
    }

    function test_supply10001IsClamped() public {
        _checkSupply(10_001);
    }

    function testFuzz_payloadAgainstReference(uint256 supply) public {
        _checkSupply(bound(supply, 0, 10_050));
    }

    function testFuzz_fullUintSupplyRange(uint256 supply) public {
        collection.setSupply(supply);
        _configure(collection);
        assertEq(machine.mintedCount(), supply > 10_000 ? 10_000 : supply);
    }

    function test_wordAndTailBoundaries() public {
        uint256[10] memory counts = [uint256(15), 16, 17, 31, 32, 33, 9951, 9968, 9983, 9984];
        for (uint256 i; i < counts.length; ++i) {
            _checkSupply(counts[i]);
        }
    }

    function testFuzz_rejectsEveryOtherCraft(uint256 tokenId) public {
        vm.assume(tokenId != 10_000);
        vm.expectRevert(abi.encodeWithSelector(SelloutMachine.UnsupportedCraft.selector, tokenId));
        machine.craftToPayload(tokenId);
    }

    function testFuzz_unauthorizedConfiguration(address caller) public {
        vm.assume(caller != OWNER);
        vm.prank(caller);
        vm.expectRevert(SelloutMachine.Unauthorized.selector);
        machine.setTrackedCollection(address(collection));
        assertEq(machine.trackedCollection(), address(0));
    }

    function test_collectionChangeAndEvents() public {
        vm.expectEmit(true, true, false, true, address(machine));
        emit TrackedCollectionUpdated(address(0), address(collection));
        _configure(collection);
        SupplyMock next = new SupplyMock();
        next.setSupply(101);
        vm.expectEmit(true, true, false, true, address(machine));
        emit TrackedCollectionUpdated(address(collection), address(next));
        _configure(next);
        collection.setSupply(10_000);
        _assertPixels(machine.craftToPayload(10_000), 101);
        assertEq(machine.trackedCollection(), address(next));
        assertEq(machine.owner(), OWNER);
    }

    function test_liveMintsAndBurnsNeedNoMachineTransaction() public {
        _configure(collection);
        collection.setSupply(100);
        _assertPixels(machine.craftToPayload(10_000), 100);
        collection.setSupply(101);
        _assertPixels(machine.craftToPayload(10_000), 101);
        collection.setSupply(1);
        _assertPixels(machine.craftToPayload(10_000), 1);
        assertEq(machine.mintProgress(), 1);
    }

    function _expectInvalid(address target) internal {
        address previous = machine.trackedCollection();
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(SelloutMachine.InvalidCollection.selector, target));
        machine.setTrackedCollection(target);
        assertEq(machine.trackedCollection(), previous, "failed selection changed collection");
    }

    function test_rejectsZeroEOASelfAndPrecompile() public {
        _configure(collection);
        _expectInvalid(address(0));
        _expectInvalid(OWNER);
        _expectInvalid(address(machine));
        _expectInvalid(address(1));
    }

    function test_rejectsNonNFTAndMissingSupply() public {
        _expectInvalid(address(new SupplyOnlyMock()));
        _expectInvalid(address(new MissingSupplyMock()));
    }

    function test_rejectsInvalidERC165Responses() public {
        for (uint256 i; i <= uint256(InterfaceMock.Behavior.GasBomb); ++i) {
            _expectInvalid(address(new InterfaceMock(InterfaceMock.Behavior(i))));
        }
    }

    function test_rejectsBadSupplyAtSelection() public {
        for (uint256 i = 1; i <= uint256(SupplyMock.Behavior.WritesState); ++i) {
            collection.setBehavior(SupplyMock.Behavior(i));
            _expectInvalid(address(collection));
        }
    }

    function test_faultySupplyAfterSelectionFallsBackToWhiteAndRecovers() public {
        collection.setSupply(5000);
        _configure(collection);
        for (uint256 i = 1; i <= uint256(SupplyMock.Behavior.WritesState); ++i) {
            collection.setBehavior(SupplyMock.Behavior(i));
            assertEq(machine.mintedCount(), 0);
            assertEq(machine.mintProgress(), 0);
            _assertPixels(machine.craftToPayload(10_000), 0);
        }
        assertEq(collection.writes(), 0, "staticcall permitted state change");
        collection.setBehavior(SupplyMock.Behavior.Normal);
        _assertPixels(machine.craftToPayload(10_000), 5000);
    }

    function test_removedCollectionCodeFallsBackToWhite() public {
        _configure(collection);
        vm.etch(address(collection), "");
        assertEq(machine.mintedCount(), 0);
        _assertPixels(machine.craftToPayload(10_000), 0);
    }

    function test_supplyCallbackCannotChangeConfiguration() public {
        _configure(collection);
        SupplyMock replacement = new SupplyMock();
        collection.setCallback(
            address(machine), abi.encodeCall(machine.setTrackedCollection, (address(replacement)))
        );
        assertEq(machine.mintedCount(), 0);
        assertEq(machine.trackedCollection(), address(collection));
        _expectInvalid(address(collection));
        _configure(replacement);
        assertEq(machine.trackedCollection(), address(replacement));
    }

    function test_factoryNeverReceivesConfigurationAuthority() public {
        DeploymentFactoryMock factory = new DeploymentFactoryMock();
        SelloutMachine deployed = factory.deploy(OWNER);
        assertEq(deployed.owner(), OWNER);
        assertEq(deployed.trackedCollection(), address(0));
        vm.prank(address(factory));
        vm.expectRevert(SelloutMachine.Unauthorized.selector);
        deployed.setTrackedCollection(address(collection));
        vm.prank(OWNER);
        deployed.setTrackedCollection(address(collection));
    }

    function test_rejectsZeroOwner() public {
        vm.expectRevert(SelloutMachine.InvalidOwner.selector);
        new SelloutMachine(address(0));
    }

    function test_noTransferRenounceUpgradeOrEtherAcceptance() public {
        vm.startPrank(OWNER);
        (bool transfer,) =
            address(machine).call(abi.encodeWithSignature("transferOwnership(address)", address(this)));
        (bool renounce,) = address(machine).call(abi.encodeWithSignature("renounceOwnership()"));
        (bool upgrade,) = address(machine).call(abi.encodeWithSignature("upgradeTo(address)", address(this)));
        vm.stopPrank();
        vm.deal(address(this), 1 ether);
        (bool receiveEther,) = address(machine).call{value: 1}("");
        assertFalse(transfer || renounce || upgrade || receiveEther);
        assertEq(machine.owner(), OWNER);
    }

    function test_payloadABIHasExactLengthAndZeroPadding() public {
        _configure(collection);
        for (uint256 count; count < 33; ++count) {
            collection.setSupply(count);
            (bool ok, bytes memory encoded) =
                address(machine).staticcall(abi.encodeCall(machine.craftToPayload, (10_000)));
            assertTrue(ok);
            assertEq(encoded.length, 64 + 10_016);
            for (uint256 i = 64 + 10_000; i < encoded.length; ++i) {
                assertEq(encoded[i], bytes1(0));
            }
            _assertPixels(abi.decode(encoded, (bytes)), count);
        }
    }
}
