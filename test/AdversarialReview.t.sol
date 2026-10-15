// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SelloutMachine} from "../src/SelloutMachine.sol";

contract ReviewCollection {
    uint256 public supply;
    uint256 public mode;
    uint256 public interfaceMode;
    uint256 public writes;
    SelloutMachine public machine;
    address public replacement;

    function setup(uint256 supply_, uint256 mode_, uint256 interfaceMode_) external {
        supply = supply_;
        mode = mode_;
        interfaceMode = interfaceMode_;
    }

    function setMachine(SelloutMachine machine_, address replacement_) external {
        machine = machine_;
        replacement = replacement_;
    }

    function configureAsOwner(address collection) external {
        machine.setTrackedCollection(collection);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        uint256 kind = interfaceMode;
        if (kind == 1) {
            assembly {
                mstore(0, 2)
                return(0, 32)
            }
        }
        if (kind == 2) return true;
        if (kind == 3) {
            assembly {
                mstore(0, 1)
                return(0, 31)
            }
        }
        if (kind == 4) {
            assembly {
                mstore(0, 1)
                return(0, 64)
            }
        }
        return id == 0x01ffc9a7 || id == 0x80ac58cd;
    }

    // Deliberately non-view: the caller must enforce STATICCALL, including nested callbacks.
    function totalSupply() external returns (uint256) {
        uint256 kind = mode;
        if (kind == 1) {
            assembly {
                mstore(0, 10000)
                return(0, 31)
            }
        }
        if (kind == 2) {
            assembly {
                mstore(0, 10000)
                return(0, 64)
            }
        }
        if (kind == 3) {
            assembly {
                mstore(0, 10000)
                return(0, 100000)
            }
        }
        if (kind == 4) {
            assembly {
                revert(0, 100000)
            }
        }
        if (kind == 5) {
            ++writes;
        }
        if (kind == 6) {
            (bool ok,) = address(machine).call{gas: 50000}(
                abi.encodeCall(SelloutMachine.setTrackedCollection, (replacement))
            );
            require(!ok, "callback unexpectedly changed configuration");
        }
        if (kind == 7) {
            assembly {
                for {} 1 {} {}
            }
        }
        if (kind == 8) {
            (bool ok, bytes memory data) =
                address(machine).staticcall{gas: 90000}(abi.encodeCall(SelloutMachine.mintedCount, ()));
            if (ok && data.length == 32) return abi.decode(data, (uint256));
            return 0;
        }
        return supply;
    }
}

contract ReviewFactory {
    function deploy(address intendedOwner) external returns (SelloutMachine) {
        return new SelloutMachine(intendedOwner);
    }
}

contract AdversarialReviewTest is Test {
    address private constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    SelloutMachine private machine;
    ReviewCollection private collection;

    function setUp() external {
        machine = new SelloutMachine(OWNER);
        collection = new ReviewCollection();
        collection.setup(101, 0, 0);
        collection.setMachine(machine, address(collection));
        vm.prank(OWNER);
        machine.setTrackedCollection(address(collection));
    }

    function test_RejectsMalformedERC165AndInvalidInterfaceSupport() external {
        for (uint256 kind = 1; kind <= 4; ++kind) {
            ReviewCollection bad = new ReviewCollection();
            bad.setup(10000, 0, kind);
            vm.expectRevert(abi.encodeWithSelector(SelloutMachine.InvalidCollection.selector, address(bad)));
            vm.prank(OWNER);
            machine.setTrackedCollection(address(bad));
            assertEq(machine.trackedCollection(), address(collection));
        }
    }

    function test_BoundedFailureModesDoNotCorruptOrRevertPayload() external {
        for (uint256 kind = 1; kind <= 7; ++kind) {
            if (kind == 6) continue;
            collection.setup(10000, kind, 0);
            uint256 before = gasleft();
            bytes memory payload = machine.craftToPayload(10000);
            uint256 used = before - gasleft();
            assertLt(used, 180000, "unbounded payload gas use");
            assertEq(machine.mintedCount(), 0);
            assertEq(payload.length, 10000);
            for (uint256 i; i < payload.length; ++i) {
                assertEq(uint8(payload[i]), 255);
            }
            assertEq(collection.writes(), 0);
            assertEq(machine.owner(), OWNER);
            assertEq(machine.trackedCollection(), address(collection));
        }
    }

    function test_EvenOwnerContractCannotReconfigureThroughStaticCallback() external {
        ReviewCollection ownerContract = new ReviewCollection();
        SelloutMachine owned = new SelloutMachine(address(ownerContract));
        ownerContract.setMachine(owned, address(collection));
        ownerContract.setup(101, 0, 0);
        ownerContract.configureAsOwner(address(ownerContract));
        ownerContract.setup(101, 6, 0);
        assertEq(owned.mintedCount(), 101);
        assertEq(owned.trackedCollection(), address(ownerContract));
        assertEq(owned.owner(), address(ownerContract));
    }

    function test_RecursiveReadCannotExceedOuterSupplyBudget() external {
        collection.setup(10000, 8, 0);
        uint256 before = gasleft();
        uint256 count = machine.mintedCount();
        uint256 used = before - gasleft();
        assertLe(count, 10000);
        assertLt(used, 110000);
        assertEq(machine.trackedCollection(), address(collection));
    }

    function test_FactoryHasNoConfigurationAuthority() external {
        ReviewFactory factory = new ReviewFactory();
        SelloutMachine deployed = factory.deploy(OWNER);
        assertEq(deployed.owner(), OWNER);
        assertEq(deployed.trackedCollection(), address(0));
        vm.expectRevert(SelloutMachine.Unauthorized.selector);
        vm.prank(address(factory));
        deployed.setTrackedCollection(address(collection));
        vm.prank(OWNER);
        deployed.setTrackedCollection(address(collection));
        assertEq(deployed.mintedCount(), 101);
    }

    function testFuzz_RawABIHasExactPixelsAndZeroPadding(uint256 supply) external {
        supply = bound(supply, 0, 10000);
        collection.setup(supply, 0, 0);
        (bool ok, bytes memory raw) =
            address(machine).staticcall(abi.encodeCall(SelloutMachine.craftToPayload, (10000)));
        assertTrue(ok);
        assertEq(raw.length, 10080);
        uint256 offset;
        uint256 size;
        assembly {
            offset := mload(add(raw, 32))
            size := mload(add(raw, 64))
        }
        assertEq(offset, 32);
        assertEq(size, 10000);
        uint256 count = supply > 10000 ? 10000 : supply;
        for (uint256 i; i < 10000; ++i) {
            assertEq(uint8(raw[64 + i]), i < count ? 0 : 255);
        }
        for (uint256 i = 10064; i < raw.length; ++i) {
            assertEq(uint8(raw[i]), 0);
        }
    }

    function test_EveryAssemblyAlignment() external {
        for (uint256 count; count <= 32; ++count) {
            _assertBoundary(count);
            _assertBoundary(9968 + count);
        }
    }

    function _assertBoundary(uint256 count) internal {
        collection.setup(count, 0, 0);
        bytes memory payload = machine.craftToPayload(10000);
        assertEq(payload.length, 10000);
        if (count != 0) assertEq(uint8(payload[count - 1]), 0);
        if (count != 10000) assertEq(uint8(payload[count]), 255);
        assertEq(uint8(payload[9999]), count == 10000 ? 0 : 255);
    }
}
