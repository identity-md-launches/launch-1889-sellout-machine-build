// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IMachine} from "./interfaces/IMachine.sol";

/// @title The Sellout Machine
/// @notice Live ERC-721 supply rendered as 10,000 row-major grayscale bytes for Vessel Craft #10000.
/// @dev No pixel state is stored. Burns can reverse progress. An unavailable supply renders white.
contract SelloutMachine is IMachine {
    uint256 public constant CAPACITY = 10_000;
    uint256 public constant SUPPLY_GAS_LIMIT = 100_000;
    uint256 private constant INTERFACE_GAS_LIMIT = 30_000;
    bytes4 private constant TOTAL_SUPPLY = 0x18160ddd;
    bytes4 private constant SUPPORTS_INTERFACE = 0x01ffc9a7;
    bytes4 private constant ERC721_INTERFACE = 0x80ac58cd;

    address public immutable owner;
    address public trackedCollection;

    error InvalidOwner();
    error Unauthorized();
    error InvalidCollection(address collection);
    error UnsupportedCraft(uint256 tokenId);

    event TrackedCollectionUpdated(address indexed previousCollection, address indexed newCollection);

    /// @param owner_ IMD supplies $owner: 0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a on mainnet.
    /// @dev No external calls or initialization transaction are required. The initial image is all white.
    constructor(address owner_) {
        if (owner_ == address(0)) revert InvalidOwner();
        owner = owner_;
    }

    function name() external pure override returns (string memory) {
        return "The Sellout Machine";
    }

    /// @notice Select an ERC-721 that exposes a bounded, ABI-conforming totalSupply() read.
    /// @dev ERC-165 and supply checks reject mistakes, but cannot prove that a contract reports honestly.
    function setTrackedCollection(address newCollection) external {
        if (msg.sender != owner) revert Unauthorized();
        if (
            newCollection == address(0) || newCollection.code.length == 0
                || !_supports(newCollection, SUPPORTS_INTERFACE, 1)
                || !_supports(newCollection, 0xffffffff, 0) || !_supports(newCollection, ERC721_INTERFACE, 1)
        ) revert InvalidCollection(newCollection);

        (bool valid,) = _readWord(newCollection, abi.encodeWithSelector(TOTAL_SUPPLY), SUPPLY_GAS_LIMIT);
        if (!valid) revert InvalidCollection(newCollection);

        address previous = trackedCollection;
        trackedCollection = newCollection;
        emit TrackedCollectionUpdated(previous, newCollection);
    }

    /// @notice Current totalSupply, clamped to 10,000. Unset, failed or malformed reads return zero.
    /// @dev This is outstanding supply, not lifetime mints; burns can decrease it.
    function mintedCount() public view returns (uint256) {
        address collection = trackedCollection;
        if (collection == address(0)) return 0;
        (bool valid, uint256 supply) =
            _readWord(collection, abi.encodeWithSelector(TOTAL_SUPPLY), SUPPLY_GAS_LIMIT);
        if (!valid) return 0;
        return supply > CAPACITY ? CAPACITY : supply;
    }

    /// @notice Progress in basis points: one NFT of this 10,000-token target is one basis point.
    function mintProgress() external view returns (uint256) {
        return mintedCount();
    }

    /// @notice Exactly 10,000 bytes: 0x00 for i < mintedCount(), otherwise 0xff.
    function craftToPayload(uint256 tokenId) external view override returns (bytes memory payload) {
        if (tokenId != CAPACITY) revert UnsupportedCraft(tokenId);
        uint256 count = mintedCount();
        payload = new bytes(CAPACITY);

        // Allocation initializes the black prefix to zero. Fill the white suffix 32 bytes at a time,
        // then at most 31 bytes individually. All writes stay inside the allocated payload.
        assembly ("memory-safe") {
            let data := add(payload, 0x20)
            let end := add(data, 10000)
            let cursor := add(data, count)
            for {} lt(add(cursor, 31), end) { cursor := add(cursor, 32) } { mstore(cursor, not(0)) }
            for {} lt(cursor, end) { cursor := add(cursor, 1) } { mstore8(cursor, 0xff) }
        }
    }

    function _supports(address collection, bytes4 interfaceId, uint256 expected) private view returns (bool) {
        (bool valid, uint256 value) = _readWord(
            collection, abi.encodeWithSelector(SUPPORTS_INTERFACE, interfaceId), INTERFACE_GAS_LIMIT
        );
        return valid && value == expected;
    }

    /// @dev Copy at most one word, independently of returndata size. Reject short AND overlong replies.
    /// A callee can exhaust only the specified gas budget; STATICCALL forbids state-changing callbacks.
    function _readWord(address target, bytes memory input, uint256 gasLimit)
        private
        view
        returns (bool valid, uint256 value)
    {
        assembly ("memory-safe") {
            valid := staticcall(gasLimit, target, add(input, 0x20), mload(input), 0, 0x20)
            valid := and(valid, eq(returndatasize(), 0x20))
            value := mload(0)
        }
    }
}
