// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The Vessel's Machine ABI, as defined by the deployed Vessel and its public template.
interface IMachine {
    function name() external view returns (string memory);
    function craftToPayload(uint256 tokenId) external view returns (bytes memory);
}
