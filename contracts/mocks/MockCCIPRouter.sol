// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Client} from "../ccip/vendor/Client.sol";
import {IAny2EVMMessageReceiver} from "../ccip/vendor/IAny2EVMMessageReceiver.sol";

/// @title MockCCIPRouter
/// @notice Local stand-in for the CCIP router, for tests only. On `ccipSend` it pulls the fee and
///         the transferred tokens from the sender, forwards the tokens to the destination receiver,
///         and synchronously invokes the receiver's `ccipReceive` — simulating cross-chain delivery
///         on a single local chain. Production CCIP testing uses the chainlink/local package (npm).
contract MockCCIPRouter {
    using SafeERC20 for IERC20;

    uint256 public fee;
    uint64 public sourceChainSelector; // the selector this router reports as the message origin
    uint256 public nonce;

    event MessageSent(bytes32 indexed messageId, uint64 destChainSelector, address receiver);

    constructor(uint256 fee_) {
        fee = fee_;
    }

    function setFee(uint256 fee_) external {
        fee = fee_;
    }

    function setSourceChainSelector(uint64 selector) external {
        sourceChainSelector = selector;
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return fee;
    }

    function ccipSend(uint64 destChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32 messageId)
    {
        // Collect the fee from the sender (the application contract).
        if (fee > 0 && message.feeToken != address(0)) {
            IERC20(message.feeToken).safeTransferFrom(msg.sender, address(this), fee);
        }

        address receiver = abi.decode(message.receiver, (address));

        // Move the transferred tokens to the destination receiver and build destTokenAmounts.
        Client.EVMTokenAmount[] memory dest = new Client.EVMTokenAmount[](message.tokenAmounts.length);
        for (uint256 i = 0; i < message.tokenAmounts.length; i++) {
            Client.EVMTokenAmount memory ta = message.tokenAmounts[i];
            IERC20(ta.token).safeTransferFrom(msg.sender, receiver, ta.amount);
            dest[i] = ta;
        }

        nonce += 1;
        messageId = keccak256(abi.encode(msg.sender, destChainSelector, nonce));

        Client.Any2EVMMessage memory delivered = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(msg.sender),
            data: message.data,
            destTokenAmounts: dest
        });

        emit MessageSent(messageId, destChainSelector, receiver);
        IAny2EVMMessageReceiver(receiver).ccipReceive(delivered);
    }
}
