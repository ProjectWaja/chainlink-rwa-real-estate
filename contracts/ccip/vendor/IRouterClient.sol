// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "./Client.sol";

/// @title IRouterClient (vendored)
/// @notice Minimal mirror of Chainlink's CCIP router client interface used by Cornerstone.
/// @dev Source of truth: chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol
interface IRouterClient {
    function isChainSupported(uint64 destChainSelector) external view returns (bool supported);

    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message)
        external
        view
        returns (uint256 fee);

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32);
}
