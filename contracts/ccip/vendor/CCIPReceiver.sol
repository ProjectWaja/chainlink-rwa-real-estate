// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAny2EVMMessageReceiver} from "./IAny2EVMMessageReceiver.sol";
import {Client} from "./Client.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title CCIPReceiver (vendored)
/// @notice Base contract for CCIP applications that receive messages. Only the configured router
///         may invoke `ccipReceive`; implementers override `_ccipReceive`.
/// @dev Faithful, minimal mirror of chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol,
///      vendored so the repo compiles under Hardhat without the package's Foundry remappings.
abstract contract CCIPReceiver is IAny2EVMMessageReceiver, IERC165 {
    address internal immutable i_ccipRouter;

    error InvalidRouter(address router);

    constructor(address router) {
        if (router == address(0)) revert InvalidRouter(address(0));
        i_ccipRouter = router;
    }

    /// @notice IERC165 support so CCIP can detect that `ccipReceive` is available.
    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message) external virtual override onlyRouter {
        _ccipReceive(message);
    }

    /// @notice Override in the implementation to handle an incoming message.
    function _ccipReceive(Client.Any2EVMMessage memory message) internal virtual;

    function getRouter() public view virtual returns (address) {
        return i_ccipRouter;
    }

    modifier onlyRouter() {
        if (msg.sender != getRouter()) revert InvalidRouter(msg.sender);
        _;
    }
}
