// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Test-only supply/erc165 stub; intentionally not a transferable NFT implementation.
contract SupplyMock {
    enum Behavior {
        Normal,
        Reverts,
        Empty,
        Short,
        Long,
        ReturnBomb,
        RevertBomb,
        GasBomb,
        WritesState,
        Callback
    }

    uint256 public supply;
    Behavior public behavior;
    address public callbackTarget;
    bytes public callbackData;
    uint256 public writes;

    function setSupply(uint256 value) external {
        supply = value;
    }

    function setBehavior(Behavior value) external {
        behavior = value;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
        behavior = Behavior.Callback;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == 0x80ac58cd;
    }

    function totalSupply() external returns (uint256) {
        Behavior b = behavior;
        if (b == Behavior.Reverts) revert("supply unavailable");
        if (b == Behavior.Empty) {
            assembly { return(0, 0) }
        }
        if (b == Behavior.Short) {
            assembly {
                mstore(0, 5000)
                return(0, 31)
            }
        }
        if (b == Behavior.Long) {
            assembly {
                mstore(0, 5000)
                mstore(32, 0)
                return(0, 64)
            }
        }
        if (b == Behavior.ReturnBomb) {
            assembly {
                mstore(0, 5000)
                return(0, 65536)
            }
        }
        if (b == Behavior.RevertBomb) {
            assembly { revert(0, 65536) }
        }
        if (b == Behavior.GasBomb) {
            assembly { for {} 1 {} {} }
        }
        if (b == Behavior.WritesState) ++writes;
        if (b == Behavior.Callback) {
            (bool success,) = callbackTarget.call(callbackData);
            require(success, "callback rejected");
        }
        return supply;
    }
}

contract InterfaceMock {
    enum Behavior {
        NoERC165,
        NoERC721,
        AlwaysTrue,
        NonBoolean,
        Short,
        Long,
        Reverts,
        GasBomb
    }
    Behavior public immutable behavior;

    constructor(Behavior value) {
        behavior = value;
    }

    function supportsInterface(bytes4 id) external view returns (bool result) {
        Behavior b = behavior;
        if (b == Behavior.NoERC165) return id == 0x80ac58cd;
        if (b == Behavior.NoERC721) return id == 0x01ffc9a7;
        if (b == Behavior.AlwaysTrue) return true;
        if (b == Behavior.NonBoolean) {
            assembly {
                mstore(0, 2)
                return(0, 32)
            }
        }
        if (b == Behavior.Short) {
            assembly {
                mstore(0, 1)
                return(0, 31)
            }
        }
        if (b == Behavior.Long) {
            assembly {
                mstore(0, 1)
                return(0, 64)
            }
        }
        if (b == Behavior.Reverts) revert();
        assembly { for {} 1 {} {} }
    }

    function totalSupply() external pure returns (uint256) {
        return 1;
    }
}

contract SupplyOnlyMock {
    function totalSupply() external pure returns (uint256) {
        return 5000;
    }
}

contract MissingSupplyMock {
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == 0x80ac58cd;
    }
}
