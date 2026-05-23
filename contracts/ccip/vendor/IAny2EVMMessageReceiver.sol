// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "./Client.sol";

/// @title IAny2EVMMessageReceiver (vendored)
/// @notice Interface a contract implements to receive CCIP messages from the router.
/// @dev Source of truth: chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiver.sol
interface IAny2EVMMessageReceiver {
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}
