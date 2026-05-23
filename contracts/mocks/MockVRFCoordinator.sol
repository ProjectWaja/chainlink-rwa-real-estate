// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @dev The fulfilment entrypoint on a VRF consumer (router/coordinator-gated in production).
interface IVRFConsumerLike {
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external;
}

/// @title MockVRFCoordinator
/// @notice Minimal local stand-in for the VRF 2.5 coordinator, for tests only. Records requests
///         and lets a test deliver randomness via `fulfillRandomWords`, invoking the consumer's
///         `rawFulfillRandomWords` (which checks the caller is the coordinator — i.e. this mock).
contract MockVRFCoordinator {
    uint256 public nonce;
    mapping(uint256 => address) public requestConsumer;

    event RandomWordsRequested(uint256 indexed requestId, address indexed consumer);

    /// @dev Signature matches IVRFCoordinatorV2Plus.requestRandomWords so the selector lines up.
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) external returns (uint256 requestId) {
        nonce += 1;
        requestId = nonce;
        requestConsumer[requestId] = msg.sender;
        emit RandomWordsRequested(requestId, msg.sender);
    }

    /// @notice Test helper: deliver randomness to the requesting consumer.
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        address consumer = requestConsumer[requestId];
        require(consumer != address(0), "unknown request");
        IVRFConsumerLike(consumer).rawFulfillRandomWords(requestId, randomWords);
    }

    /// @notice Convenience: fulfil with a single word.
    function fulfillWithWord(uint256 requestId, uint256 word) external {
        address consumer = requestConsumer[requestId];
        require(consumer != address(0), "unknown request");
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        IVRFConsumerLike(consumer).rawFulfillRandomWords(requestId, words);
    }
}
