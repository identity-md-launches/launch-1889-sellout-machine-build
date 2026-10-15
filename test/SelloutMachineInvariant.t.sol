// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SelloutMachine} from "src/SelloutMachine.sol";
import {SupplyMock, SupplyOnlyMock} from "./mocks/SupplyMocks.sol";

/// @dev Ghost state comes from attempted actions, never from Machine getters.
contract SelloutMachineHandler is Test {
    address public constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    SelloutMachine public immutable machine;
    SupplyMock[3] public collections;
    address[3] private outsiders;
    address private immutable nonNFT;
    uint256[3] public ghostSupply;
    SupplyMock.Behavior[3] public ghostBehavior;
    address public ghostSelected;
    uint256 private selectedIndex;
    uint256 public successfulSelections;
    uint256 public rejectedSelections;
    uint256 public unauthorizedAttempts;
    uint256 public supplyChanges;
    uint256 public behaviorChanges;

    constructor(SelloutMachine machine_) {
        machine = machine_;
        for (uint256 i; i < collections.length; ++i) {
            collections[i] = new SupplyMock();
        }
        outsiders[0] = makeAddr("invariant outsider one");
        outsiders[1] = makeAddr("invariant outsider two");
        outsiders[2] = address(this);
        nonNFT = address(new SupplyOnlyMock());
    }

    function changeSupply(uint256 index, uint256 value, bool fullWidth) external {
        index = bound(index, 0, 2);
        // Mix realistic partial images with the complete uint256 domain, including overflow edges.
        if (!fullWidth) value = bound(value, 0, 10_001);
        collections[index].setSupply(value);
        ghostSupply[index] = value;
        ++supplyChanges;
    }

    function changeBehavior(uint256 index, uint256 behavior) external {
        index = bound(index, 0, 2);
        behavior = bound(behavior, 0, uint256(SupplyMock.Behavior.WritesState));
        collections[index].setBehavior(SupplyMock.Behavior(behavior));
        ghostBehavior[index] = SupplyMock.Behavior(behavior);
        ++behaviorChanges;
    }

    function selectCollection(uint256 index) external {
        index = bound(index, 0, 2);
        address candidate = address(collections[index]);
        vm.recordLogs();
        vm.prank(OWNER);
        (bool ok, bytes memory result) =
            address(machine).call(abi.encodeCall(SelloutMachine.setTrackedCollection, (candidate)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (ghostBehavior[index] == SupplyMock.Behavior.Normal) {
            assertTrue(ok, "owner cannot select healthy collection");
            assertEq(logs.length, 1, "selection must emit exactly one event");
            assertEq(logs[0].emitter, address(machine));
            assertEq(logs[0].topics.length, 3);
            assertEq(logs[0].topics[0], keccak256("TrackedCollectionUpdated(address,address)"));
            assertEq(logs[0].topics[1], bytes32(uint256(uint160(ghostSelected))));
            assertEq(logs[0].topics[2], bytes32(uint256(uint160(candidate))));
            assertEq(logs[0].data.length, 0);
            ghostSelected = candidate;
            selectedIndex = index;
            ++successfulSelections;
        } else {
            assertFalse(ok, "owner selected malformed collection");
            assertEq(result, abi.encodeWithSelector(SelloutMachine.InvalidCollection.selector, candidate));
            assertEq(logs.length, 0);
            ++rejectedSelections;
        }
        assertEq(machine.trackedCollection(), ghostSelected);
    }

    function unauthorizedSelection(uint256 actor, uint256 index) external {
        actor = bound(actor, 0, 2);
        index = bound(index, 0, 2);
        vm.prank(outsiders[actor]);
        (bool ok, bytes memory result) = address(machine)
            .call(abi.encodeCall(SelloutMachine.setTrackedCollection, (address(collections[index]))));
        assertFalse(ok, "non-owner changed configuration");
        assertEq(result, abi.encodeWithSelector(SelloutMachine.Unauthorized.selector));
        assertEq(machine.trackedCollection(), ghostSelected);
        ++unauthorizedAttempts;
    }

    function invalidSelection(uint256 choice) external {
        choice = bound(choice, 0, 3);
        address candidate =
            choice == 0 ? address(0) : choice == 1 ? OWNER : choice == 2 ? address(machine) : nonNFT;
        vm.prank(OWNER);
        (bool ok, bytes memory result) =
            address(machine).call(abi.encodeCall(SelloutMachine.setTrackedCollection, (candidate)));
        assertFalse(ok, "invalid address replaced collection");
        assertEq(result, abi.encodeWithSelector(SelloutMachine.InvalidCollection.selector, candidate));
        assertEq(machine.trackedCollection(), ghostSelected);
        ++rejectedSelections;
    }

    function expectedCount() public view returns (uint256) {
        if (ghostSelected == address(0) || ghostBehavior[selectedIndex] != SupplyMock.Behavior.Normal) {
            return 0;
        }
        uint256 supply = ghostSupply[selectedIndex];
        return supply > 10_000 ? 10_000 : supply;
    }
}

contract SelloutMachineInvariantTest is Test {
    address private constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    SelloutMachine private machine;
    SelloutMachineHandler private handler;
    bytes32 private allWhiteHash;
    bytes32 private allBlackHash;

    function setUp() public {
        machine = new SelloutMachine(OWNER);
        handler = new SelloutMachineHandler(machine);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.changeSupply.selector;
        selectors[1] = handler.changeBehavior.selector;
        selectors[2] = handler.selectCollection.selector;
        selectors[3] = handler.unauthorizedSelection.selector;
        selectors[4] = handler.invalidSelection.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        bytes memory referenceImage = new bytes(10_000);
        allBlackHash = keccak256(referenceImage);
        for (uint256 i; i < referenceImage.length; ++i) {
            referenceImage[i] = 0xff;
        }
        allWhiteHash = keccak256(referenceImage);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_configurationAndImageAlwaysMatchActionHistory() public view {
        assertEq(machine.owner(), OWNER, "exclusive owner changed");
        assertEq(
            machine.trackedCollection(), handler.ghostSelected(), "selection diverged from authorized actions"
        );
        uint256 expected = handler.expectedCount();
        assertEq(machine.mintedCount(), expected);
        assertEq(machine.mintProgress(), expected);
        bytes memory payload = machine.craftToPayload(10_000);
        assertEq(payload.length, 10_000);
        // Hash full zero/white images to keep failure-heavy campaigns inexpensive.
        // Partial images use an independent byte-by-byte oracle, not the implementation's word loop.
        if (expected == 0) {
            assertEq(keccak256(payload), allWhiteHash);
        } else if (expected == 10_000) {
            assertEq(keccak256(payload), allBlackHash);
        } else {
            for (uint256 i; i < payload.length; ++i) {
                if (payload[i] != (i < expected ? bytes1(0) : bytes1(0xff))) {
                    revert("image disagrees with history");
                }
            }
        }
        for (uint256 i; i < 3; ++i) {
            assertEq(handler.collections(i).writes(), 0, "supply STATICCALL wrote state");
        }
    }

    // Pins a nonvacuous lifecycle alongside the randomized campaign. It also regression-tests
    // the handler model itself, without claiming that every random sequence covers every action.
    function test_handlerExercisesReplacementBurnFailureRecoveryAndOldCollectionIsolation() public {
        handler.changeSupply(0, 5000, true);
        handler.selectCollection(0);
        invariant_configurationAndImageAlwaysMatchActionHistory();
        handler.changeSupply(0, 101, true);
        invariant_configurationAndImageAlwaysMatchActionHistory();
        handler.changeBehavior(0, uint256(SupplyMock.Behavior.GasBomb));
        invariant_configurationAndImageAlwaysMatchActionHistory();
        handler.selectCollection(0);
        handler.changeBehavior(0, uint256(SupplyMock.Behavior.Normal));
        invariant_configurationAndImageAlwaysMatchActionHistory();
        handler.changeSupply(1, 9999, true);
        handler.selectCollection(1);
        handler.changeSupply(0, type(uint256).max, true);
        handler.unauthorizedSelection(0, 0);
        handler.invalidSelection(0);
        invariant_configurationAndImageAlwaysMatchActionHistory();
        assertEq(machine.mintedCount(), 9999);
        assertEq(handler.successfulSelections(), 2);
        assertEq(handler.rejectedSelections(), 2);
        assertEq(handler.unauthorizedAttempts(), 1);
        assertEq(handler.supplyChanges(), 4);
        assertEq(handler.behaviorChanges(), 2);
    }
}
