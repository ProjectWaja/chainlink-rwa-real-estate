// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev The single method FunctionsClient invokes on its router, plus the fulfilment callback.
interface IFunctionsClientLike {
    function handleOracleFulfillment(bytes32 requestId, bytes memory response, bytes memory err) external;
}

/// @title MockFunctionsRouter
/// @notice A minimal local stand-in for the Chainlink Functions router, for tests only. It
///         records requests and lets a test deliver a response by calling `fulfill`, which
///         invokes the consumer's `handleOracleFulfillment` (router-gated in production).
contract MockFunctionsRouter {
    uint256 public nonce;
    mapping(bytes32 => address) public requestClient;

    event RequestReceived(bytes32 indexed requestId, address indexed client);

    /// @dev Signature matches IFunctionsRouter.sendRequest so the selector lines up.
    function sendRequest(uint64, bytes calldata, uint16, uint32, bytes32) external returns (bytes32) {
        nonce += 1;
        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, nonce, blockhash(block.number - 1)));
        requestClient[requestId] = msg.sender;
        emit RequestReceived(requestId, msg.sender);
        return requestId;
    }

    /// @notice Test helper: deliver a DON response to the requesting consumer.
    function fulfill(bytes32 requestId, bytes calldata response, bytes calldata err) external {
        address client = requestClient[requestId];
        require(client != address(0), "unknown request");
        IFunctionsClientLike(client).handleOracleFulfillment(requestId, response, err);
    }
}
