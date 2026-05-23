// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MockAggregatorV3
/// @notice A configurable stand-in for a Chainlink Data Feed / Proof-of-Reserve feed,
///         used only in tests. Lets a test set the answer, decimals, and the
///         `updatedAt` timestamp so staleness handling can be exercised.
/// @dev NOT for production. Real feeds are decentralized aggregators — never deploy a mock.
contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 private immutable _decimals;
    string private _description;
    uint256 private constant _VERSION = 1;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _updatedAt;

    constructor(uint8 decimals_, int256 initialAnswer, string memory description_) {
        _decimals = decimals_;
        _description = description_;
        _set(initialAnswer);
    }

    /// @notice Update the reported answer and stamp it with the current block time.
    function setAnswer(int256 newAnswer) external {
        _set(newAnswer);
    }

    /// @notice Update the answer but force a specific `updatedAt` (to simulate staleness).
    function setAnswerWithTimestamp(int256 newAnswer, uint256 updatedAt_) external {
        _roundId += 1;
        _answer = newAnswer;
        _updatedAt = updatedAt_;
    }

    function _set(int256 newAnswer) private {
        _roundId += 1;
        _answer = newAnswer;
        _updatedAt = block.timestamp;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external pure override returns (uint256) {
        return _VERSION;
    }

    function getRoundData(uint80 roundId_)
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId_, _answer, _updatedAt, _updatedAt, roundId_);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }
}
