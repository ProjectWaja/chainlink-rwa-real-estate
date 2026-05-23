// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Client (vendored)
/// @notice A minimal mirror of the subset of Chainlink's CCIP `Client` library that Cornerstone
///         uses. Vendored into the repo so it compiles cleanly under Hardhat — the published
///         chainlink/contracts-ccip package (npm) relies on Foundry-style import remappings that
///         Hardhat does not support. Field layouts match the official library exactly.
/// @dev Source of truth: chainlink/contracts-ccip/contracts/libraries/Client.sol
library Client {
    struct EVMTokenAmount {
        address token; // token address on the local chain
        uint256 amount; // amount of tokens
    }

    struct Any2EVMMessage {
        bytes32 messageId; // messageId from ccipSend on the source chain
        uint64 sourceChainSelector; // source chain selector
        bytes sender; // abi.decode(sender) -> address if coming from an EVM chain
        bytes data; // payload sent in the original message
        EVMTokenAmount[] destTokenAmounts; // tokens (and amounts) delivered on the destination chain
    }

    struct EVM2AnyMessage {
        bytes receiver; // abi.encode(receiver address) for destination EVM chains
        bytes data; // data payload
        EVMTokenAmount[] tokenAmounts; // token transfers
        address feeToken; // fee token address; address(0) means pay in native
        bytes extraArgs; // populate via _argsToBytes(GenericExtraArgsV2)
    }

    bytes4 public constant GENERIC_EXTRA_ARGS_V2_TAG = 0x181dcf10;

    struct GenericExtraArgsV2 {
        uint256 gasLimit; // gas for the receiver callback on the destination chain
        bool allowOutOfOrderExecution;
    }

    function _argsToBytes(GenericExtraArgsV2 memory extraArgs) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(GENERIC_EXTRA_ARGS_V2_TAG, extraArgs);
    }
}
