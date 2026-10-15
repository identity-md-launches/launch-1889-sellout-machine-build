// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SelloutMachine} from "src/SelloutMachine.sol";
import {ResponseCollection} from "./mocks/ResponseCollection.sol";

contract ConfigurationForwarder {
    function forward(SelloutMachine machine, address collection) external {
        machine.setTrackedCollection(collection);
    }
}

contract ResponseValidationTest is Test {
    address private constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    SelloutMachine private machine;
    ResponseCollection private original;
    ResponseCollection private candidate;

    event TrackedCollectionUpdated(address indexed previousCollection, address indexed newCollection);

    function setUp() public {
        machine = new SelloutMachine(OWNER);
        original = new ResponseCollection();
        candidate = new ResponseCollection();
        _select(address(original));
    }

    function _select(address collection) private {
        vm.prank(OWNER);
        machine.setTrackedCollection(collection);
    }

    function _invalid(address collection) private {
        address before = machine.trackedCollection();
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(SelloutMachine.InvalidCollection.selector, collection));
        vm.prank(OWNER);
        machine.setTrackedCollection(collection);
        assertEq(vm.getRecordedLogs().length, 0, "rejected update emitted a log");
        assertEq(machine.trackedCollection(), before, "rejected update changed selection");
    }

    function _interfaceId(uint256 stage) private pure returns (bytes4) {
        return stage == 0 ? bytes4(0x01ffc9a7) : stage == 1 ? bytes4(0xffffffff) : bytes4(0x80ac58cd);
    }

    function _assertImage(uint256 count) private view {
        assertEq(machine.mintedCount(), count);
        assertEq(machine.mintProgress(), count);
        bytes memory image = machine.craftToPayload(10_000);
        assertEq(image.length, 10_000);
        for (uint256 i; i < image.length; ++i) {
            if (image[i] != (i < count ? bytes1(0) : bytes1(0xff))) revert("wrong pixel");
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_eachERC165StageRequiresExactWordAndLength(uint256 stage, uint256 word, uint256 size)
        public
    {
        stage = bound(stage, 0, 2);
        size = bound(size, 0, 96);
        candidate.setInterface(_interfaceId(stage), word, size, ResponseCollection.Action.Return);
        uint256 expectedWord = stage == 1 ? 0 : 1;
        if (size == 32 && word == expectedWord) {
            _select(address(candidate));
            assertEq(machine.trackedCollection(), address(candidate));
            assertEq(machine.mintedCount(), 101);
        } else {
            _invalid(address(candidate));
            assertEq(machine.mintedCount(), 101);
        }
    }

    // Pin the valid branch and both sides of the one-word boundary at every validation stage.
    function test_eachERC165StageBoundaryMatrix() public {
        uint256[7] memory sizes = [uint256(0), 1, 31, 32, 33, 64, 65_536];
        for (uint256 stage; stage < 3; ++stage) {
            bytes4 id = _interfaceId(stage);
            uint256 expectedWord = stage == 1 ? 0 : 1;
            for (uint256 i; i < sizes.length; ++i) {
                candidate.setInterface(id, expectedWord, sizes[i], ResponseCollection.Action.Return);
                if (sizes[i] == 32) {
                    _select(address(candidate));
                    assertEq(machine.mintedCount(), 101);
                    _select(address(original));
                } else {
                    _invalid(address(candidate));
                }
            }
            candidate.setInterface(id, expectedWord, 32, ResponseCollection.Action.Return);
        }
    }

    function test_eachERC165StageChecksCanonicalBooleanAndExpectedClaim() public {
        uint256[4] memory words = [uint256(0), 1, 2, type(uint256).max];
        for (uint256 stage; stage < 3; ++stage) {
            bytes4 id = _interfaceId(stage);
            uint256 expectedWord = stage == 1 ? 0 : 1;
            for (uint256 i; i < words.length; ++i) {
                candidate.setInterface(id, words[i], 32, ResponseCollection.Action.Return);
                if (words[i] == expectedWord) {
                    _select(address(candidate));
                    assertEq(machine.trackedCollection(), address(candidate));
                    _select(address(original));
                } else {
                    _invalid(address(candidate));
                }
            }
            candidate.setInterface(id, expectedWord, 32, ResponseCollection.Action.Return);
        }
    }

    function test_eachERC165StageRejectsSideEffectsRevertAndGasExhaustion() public {
        for (uint256 stage; stage < 3; ++stage) {
            bytes4 id = _interfaceId(stage);
            uint256 expectedWord = stage == 1 ? 0 : 1;
            for (uint256 action = 1; action <= uint256(ResponseCollection.Action.TransientStore); ++action) {
                candidate.setInterface(id, expectedWord, 32, ResponseCollection.Action(action));
                uint256 beforeGas = gasleft();
                _invalid(address(candidate));
                assertLt(beforeGas - gasleft(), 100_000, "interface failure escaped its gas budget");
                assertEq(candidate.writes(), 0);
            }
            candidate.setInterface(id, expectedWord, 32, ResponseCollection.Action.Return);
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_supplyResponseLengthBeforeAndAfterSelection(uint256 size, uint256 supply) public {
        size = bound(size, 0, 128);
        candidate.setSupply(supply, size, ResponseCollection.Action.Return);
        if (size == 32) {
            _select(address(candidate));
        } else {
            _invalid(address(candidate));
            candidate.setSupply(101, 32, ResponseCollection.Action.Return);
            _select(address(candidate));
            candidate.setSupply(supply, size, ResponseCollection.Action.Return);
        }
        uint256 count = size != 32 ? 0 : supply > 10_000 ? 10_000 : supply;
        _assertImage(count);
        // A read failure must neither clear the selected collection nor poison subsequent reads.
        assertEq(machine.trackedCollection(), address(candidate));
        candidate.setSupply(9999, 32, ResponseCollection.Action.Return);
        assertEq(machine.mintedCount(), 9999);
    }

    function test_supplyCannotWriteLogsStorageOrTransientStorage() public {
        for (
            uint256 action = uint256(ResponseCollection.Action.Store);
            action <= uint256(ResponseCollection.Action.TransientStore);
            ++action
        ) {
            candidate.setSupply(10_000, 32, ResponseCollection.Action(action));
            _invalid(address(candidate));
            candidate.setSupply(101, 32, ResponseCollection.Action.Return);
            _select(address(candidate));
            candidate.setSupply(10_000, 32, ResponseCollection.Action(action));
            vm.recordLogs();
            _assertImage(0);
            assertEq(vm.getRecordedLogs().length, 0);
            assertEq(candidate.writes(), 0);
            _select(address(original));
        }
    }

    function test_revertingWithExactlyOneSupplyWordIsNotASuccessfulRead() public {
        candidate.setSupply(10_000, 32, ResponseCollection.Action.Revert);
        _invalid(address(candidate));
        original.setSupply(10_000, 32, ResponseCollection.Action.Revert);
        _assertImage(0);
        original.setSupply(10_000, 32, ResponseCollection.Action.Return);
        _assertImage(10_000);
    }

    function test_unsupportedCraftRejectedBeforeCallingHostileCollection() public {
        original.setSupply(101, 32, ResponseCollection.Action.ExhaustGas);
        vm.expectCall(address(original), abi.encodeWithSignature("totalSupply()"), uint64(0));
        vm.expectRevert(abi.encodeWithSelector(SelloutMachine.UnsupportedCraft.selector, 10_001));
        machine.craftToPayload(10_001);
    }

    function test_payloadReadsSupplyExactlyOnceAndWritesNoStorage() public {
        vm.record();
        vm.expectCall(address(original), abi.encodeWithSignature("totalSupply()"), uint64(1));
        bytes memory payload = machine.craftToPayload(10_000);
        assertEq(payload.length, 10_000);
        assertEq(payload[100], bytes1(0));
        assertEq(payload[101], bytes1(0xff));
        (, bytes32[] memory machineWrites) = vm.accesses(address(machine));
        (, bytes32[] memory collectionWrites) = vm.accesses(address(original));
        assertEq(machineWrites.length, 0, "payload stored pixel state");
        assertEq(collectionWrites.length, 0, "payload mutated the collection");
    }

    function test_ownerOriginDoesNotAuthorizeAnIntermediary() public {
        ConfigurationForwarder intermediary = new ConfigurationForwarder();
        vm.prank(OWNER, OWNER);
        vm.expectRevert(SelloutMachine.Unauthorized.selector);
        intermediary.forward(machine, address(candidate));
        assertEq(machine.trackedCollection(), address(original));
        _select(address(candidate));
        assertEq(machine.trackedCollection(), address(candidate));
    }

    function test_reselectingSameCollectionEmitsAccurateEventAndRevalidates() public {
        vm.expectEmit(true, true, false, true, address(machine));
        emit TrackedCollectionUpdated(address(original), address(original));
        _select(address(original));
        original.setSupply(101, 31, ResponseCollection.Action.Return);
        _invalid(address(original));
        original.setSupply(1, 32, ResponseCollection.Action.Return);
        _select(address(original));
        _assertImage(1);
    }
}
