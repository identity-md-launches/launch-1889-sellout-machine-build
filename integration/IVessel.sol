// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Exact subset of the mainnet ABI recorded in docs/reference/vessel.abi.json.
interface IVessel {
    function ownerOf(uint256 tokenId) external view returns (address);
    function craftToMachineStatus(uint256 tokenId) external view returns (bool);
    function craftToColorMode(uint256 tokenId) external view returns (uint8);
    function craftToLocked(uint256 tokenId) external view returns (bool);
    function craftToType(uint256 tokenId) external view returns (string memory);
    function craftToMachine(uint256 tokenId) external view returns (address);
    function craftToPayload(uint256 tokenId) external view returns (bytes memory);
    function craftToSVG(uint256 tokenId) external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function setMachineHolder(uint256 tokenId, address machine) external;
    function renderer() external view returns (address);
    function relics() external view returns (address);
}

interface IVesselRelics {
    function isRelic(uint256 tokenId) external view returns (bool);
}
