// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SelloutMachine} from "src/SelloutMachine.sol";
import {IMachine} from "src/interfaces/IMachine.sol";
import {SupplyMock} from "./mocks/SupplyMocks.sol";

/// @dev Offline model of the specific boundary used by Craft #10000: holder-authorized attachment,
/// IMachine dispatch, and mode-zero 100x100 SVG output. This is NOT the deployed Vessel contract.
/// Locking, delegates, Relics, other Craft types, and metadata are intentionally outside this model.
/// Format/ordering basis: docs/reference/{vessel,renderer}.verified.sol.txt. The actual-contract
/// checks remain in integration/VesselMainnet.t.sol and must be run on a mainnet fork separately.
contract OfflineVesselAdapter {
    address private immutable holder;
    IMachine public machine;

    error MustBeHolderOrDelegate();
    error InvalidMachine();
    error UnsupportedFixtureCraft();

    constructor(address holder_) {
        holder = holder_;
    }

    function setMachineHolder(uint256 tokenId, address selected) external {
        if (msg.sender != holder) revert MustBeHolderOrDelegate();
        if (tokenId != 10_000) revert UnsupportedFixtureCraft();
        if (selected == address(0) || selected.code.length == 0) revert InvalidMachine();
        machine = IMachine(selected);
    }

    function craftToPayload(uint256 tokenId) public view returns (bytes memory) {
        return machine.craftToPayload(tokenId);
    }

    function machineName() external view returns (string memory) {
        return machine.name();
    }

    // Independent, simple nested-row renderer. It consumes payload bytes, never mintedCount().
    // Its gas is fixture overhead and must not be presented as deployed renderer gas.
    function craftToSVG(uint256 tokenId) external view returns (string memory) {
        bytes memory pixels = craftToPayload(tokenId);
        require(pixels.length == 10_000, "wrong capacity");
        bytes memory output = new bytes(700_122);
        uint256 cursor = _append(
            output,
            0,
            bytes(
                "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='600' viewBox='0 0 100 100' shape-rendering='crispEdges'>"
            )
        );
        for (uint256 row; row < 100; ++row) {
            for (uint256 column; column < 100; ++column) {
                uint8 shade = uint8(pixels[row * 100 + column]);
                require(shade == 0 || shade == 255, "not black or white");
                bytes memory rectangle = abi.encodePacked(
                    "<rect x='",
                    _coordinate(column),
                    "' y='",
                    _coordinate(row),
                    "' width='1' height='1' fill='rgb(",
                    shade == 0 ? "0,0,0" : "255,255,255",
                    ")'/>"
                );
                cursor = _append(output, cursor, rectangle);
            }
        }
        cursor = _append(output, cursor, bytes("</svg>"));
        assembly ("memory-safe") { mstore(output, cursor) }
        return string(output);
    }

    function _coordinate(uint256 value) private pure returns (bytes memory) {
        if (value < 10) return abi.encodePacked(bytes1(uint8(48 + value)));
        return abi.encodePacked(bytes1(uint8(48 + value / 10)), bytes1(uint8(48 + value % 10)));
    }

    function _append(bytes memory output, uint256 cursor, bytes memory part) private pure returns (uint256) {
        for (uint256 i; i < part.length; ++i) {
            output[cursor++] = part[i];
        }
        return cursor;
    }
}

contract OfflineVesselCompatibilityTest is Test {
    address private constant OWNER = 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a;
    SelloutMachine private machine;
    SupplyMock private collection;
    OfflineVesselAdapter private vessel;

    function setUp() public {
        machine = new SelloutMachine(OWNER);
        collection = new SupplyMock();
        vessel = new OfflineVesselAdapter(OWNER);
        vm.prank(OWNER);
        vessel.setMachineHolder(10_000, address(machine));
    }

    function _select(SupplyMock selected) private {
        vm.prank(OWNER);
        machine.setTrackedCollection(address(selected));
    }

    function _assertRoutedPixels(uint256 count) private view {
        bytes memory pixels = vessel.craftToPayload(10_000);
        assertEq(pixels.length, 10_000);
        for (uint256 i; i < pixels.length; ++i) {
            if (pixels[i] != (i < count ? bytes1(0) : bytes1(0xff))) revert("wrong routed image");
        }
        assertEq(address(vessel.machine()), address(machine));
    }

    function test_offlineAttachmentSupportsMachineABIAndEmptyCollection() public view {
        assertEq(vessel.machineName(), "The Sellout Machine");
        _assertRoutedPixels(0);
    }

    function test_offlineCollectionLifecycleNeedsOnlyOneAttachment() public {
        _select(collection);
        collection.setSupply(101);
        _assertRoutedPixels(101);
        collection.setSupply(100);
        _assertRoutedPixels(100);
        collection.setBehavior(SupplyMock.Behavior.Reverts);
        _assertRoutedPixels(0);
        collection.setBehavior(SupplyMock.Behavior.Normal);
        _assertRoutedPixels(100);
        SupplyMock replacement = new SupplyMock();
        replacement.setSupply(type(uint256).max);
        _select(replacement);
        _assertRoutedPixels(10_000);
        collection.setSupply(0);
        _assertRoutedPixels(10_000);
    }

    function test_offlineUnauthorizedAttachmentAndConfigurationAreSeparateChecks() public {
        vm.expectRevert(OfflineVesselAdapter.MustBeHolderOrDelegate.selector);
        vessel.setMachineHolder(10_000, address(machine));
        vm.prank(address(vessel));
        vm.expectRevert(SelloutMachine.Unauthorized.selector);
        machine.setTrackedCollection(address(collection));
        assertEq(address(vessel.machine()), address(machine));
        assertEq(machine.trackedCollection(), address(0));
    }

    function test_offlineDispatchPreservesUnsupportedCraftError() public {
        vm.expectRevert(abi.encodeWithSelector(SelloutMachine.UnsupportedCraft.selector, 9999));
        vessel.craftToPayload(9999);
    }

    // Independent full SVG vectors from tools/svg_vectors.py, also checked on the real renderer.
    function _assertSVG(uint256 count, bytes32 expectedHash) private {
        collection.setSupply(count);
        _select(collection);
        bytes memory svg = bytes(vessel.craftToSVG(10_000));
        assertEq(svg.length, 658_122 - 6 * count);
        assertEq(sha256(svg), expectedHash, "SVG pixel coordinates or grayscale encoding differ");
    }

    function test_offlineSVGRowBoundary101() public {
        _assertSVG(101, 0x3bf7607f1ab679f1d10cf784d8de01adf543c7befcd932cd918303dee244d1bc);
    }

    function test_offlineSVGLastWhitePixel9999() public {
        _assertSVG(9999, 0xa21dc837327e077930da62c44f71a01f9db0d070b10074df94e566b30e26e3a4);
    }
}
