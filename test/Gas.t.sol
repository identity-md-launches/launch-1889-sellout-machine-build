// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SelloutMachine} from "../src/SelloutMachine.sol";
import {SupplyMock} from "./mocks/SupplyMocks.sol";

contract SelloutMachineGasTest is Test {
    address private constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    SelloutMachine private machine;
    SupplyMock private collection;

    function setUp() public {
        machine = new SelloutMachine(OWNER);
        collection = new SupplyMock();
        vm.prank(OWNER);
        machine.setTrackedCollection(address(collection));
    }

    function _measure(uint256 supply) private {
        collection.setSupply(supply);
        vm.cool(address(machine));
        vm.cool(address(collection));
        uint256 beforeGas = gasleft();
        bytes memory payload = machine.craftToPayload(10_000);
        uint256 used = beforeGas - gasleft();
        uint256 calleeGas = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("supply", supply);
        emit log_named_uint("cold payload call gas (includes caller ABI decoding)", used);
        emit log_named_uint("cold Machine execution gas (callee only)", calleeGas);
        assertEq(payload.length, 10_000);
        assertLt(used, 60_000, "payload generation gas regression");
    }

    function test_gasPayload0() public {
        _measure(0);
    }

    function test_gasPayload1() public {
        _measure(1);
    }

    function test_gasPayload100() public {
        _measure(100);
    }

    function test_gasPayload101() public {
        _measure(101);
    }

    function test_gasPayload5000() public {
        _measure(5000);
    }

    function test_gasPayload9999() public {
        _measure(9999);
    }

    function test_gasPayload10000() public {
        _measure(10_000);
    }

    function test_gasDeployment() public {
        uint256 beforeGas = gasleft();
        SelloutMachine deployed = new SelloutMachine(OWNER);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("CREATE deployment gas (excludes transaction intrinsic gas)", used);
        assertEq(deployed.owner(), OWNER);
        assertLt(used, 450_000);
    }

    function test_gasFirstCollectionSelection() public {
        SelloutMachine unconfigured = new SelloutMachine(OWNER);
        vm.cool(address(unconfigured));
        vm.cool(address(collection));
        vm.prank(OWNER);
        uint256 beforeGas = gasleft();
        unconfigured.setTrackedCollection(address(collection));
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("first selection call gas (cold)", used);
        assertEq(unconfigured.trackedCollection(), address(collection));
        assertLt(used, 70_000);
    }

    function test_gasCollectionReplacement() public {
        SupplyMock next = new SupplyMock();
        vm.cool(address(machine));
        vm.cool(address(next));
        vm.prank(OWNER);
        uint256 beforeGas = gasleft();
        machine.setTrackedCollection(address(next));
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("replacement selection call gas (cold)", used);
        assertEq(machine.trackedCollection(), address(next));
        assertLt(used, 55_000);
    }

    function test_gasMaliciousSupplyIsBounded() public {
        collection.setBehavior(SupplyMock.Behavior.GasBomb);
        vm.cool(address(machine));
        vm.cool(address(collection));
        uint256 beforeGas = gasleft();
        bytes memory payload = machine.craftToPayload(10_000);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("gas-bomb fallback payload call gas", used);
        assertEq(payload.length, 10_000);
        assertLt(used, 160_000, "gas bomb escaped its budget");
    }
}
