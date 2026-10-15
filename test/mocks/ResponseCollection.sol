// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Test-only ABI responder. Each ERC-165 query can fail independently after earlier queries pass.
contract ResponseCollection {
    enum Action {
        Return,
        Revert,
        ExhaustGas,
        Store,
        EmitLog,
        TransientStore
    }

    struct Reply {
        uint256 word;
        uint256 size;
        Action action;
    }

    mapping(bytes4 => Reply) private interfaces;
    Reply private supply;
    uint256 public writes;
    event AttemptedWrite();

    constructor() {
        interfaces[0x01ffc9a7] = Reply(1, 32, Action.Return);
        interfaces[0xffffffff] = Reply(0, 32, Action.Return);
        interfaces[0x80ac58cd] = Reply(1, 32, Action.Return);
        supply = Reply(101, 32, Action.Return);
    }

    function setInterface(bytes4 id, uint256 word, uint256 size, Action action) external {
        interfaces[id] = Reply(word, size, action);
    }

    function setSupply(uint256 word, uint256 size, Action action) external {
        supply = Reply(word, size, action);
    }

    // Non-view deliberately: the Machine, not this fixture, must enforce STATICCALL.
    function supportsInterface(bytes4 id) external returns (bool) {
        _reply(interfaces[id]);
    }

    function totalSupply() external returns (uint256) {
        _reply(supply);
    }

    function _reply(Reply memory response) private {
        uint256 word = response.word;
        uint256 size = response.size;
        if (response.action == Action.Revert) {
            assembly {
                mstore(0, word)
                revert(0, size)
            }
        }
        if (response.action == Action.ExhaustGas) {
            assembly { for {} 1 {} {} }
        }
        if (response.action == Action.Store) ++writes;
        if (response.action == Action.EmitLog) emit AttemptedWrite();
        if (response.action == Action.TransientStore) {
            assembly { tstore(0, 1) }
        }
        assembly {
            mstore(0, word)
            return(0, size)
        }
    }
}
