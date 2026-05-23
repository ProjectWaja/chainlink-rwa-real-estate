// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Minimal sink interface implemented by RealEstateNAV.
interface INavSink {
    function propertyValueUsd(bytes32 propertyId) external view returns (uint256);
    function setPropertyValueUsd(bytes32 propertyId, uint256 valueUsd) external;
}

/// @title PropertyValuationConsumer
/// @notice A Chainlink **Functions** consumer that asks the DON to run an off-chain AI/AVM
///         valuation (see functions-source/property-valuation.js) and writes the result into
///         RealEstateNAV. This is where "AI" enters the system.
/// @dev The DON returns a single uint256 packing the result:
///        bits   0..127 = valuationUsd (whole USD)
///        bits 128..255 = confidence   (0..100)
///      Two guardrails bound how much a single (possibly bad or manipulated) model run can do:
///        - MIN_CONFIDENCE: low-confidence answers are rejected;
///        - MAX_DEVIATION_BPS: a move beyond this vs. the current NAV is *flagged* for human/
///          multisig review instead of being auto-applied.
///      See docs/functions-and-ai.md.
contract PropertyValuationConsumer is FunctionsClient, Ownable {
    using FunctionsRequest for FunctionsRequest.Request;

    /// @notice Minimum confidence (0..100) required to accept a valuation.
    uint16 public constant MIN_CONFIDENCE = 60;
    /// @notice Max single-update NAV move (basis points) applied automatically; larger moves are flagged.
    uint256 public constant MAX_DEVIATION_BPS = 2000; // 20%

    INavSink public immutable nav;

    // Functions request configuration.
    uint64 public subscriptionId;
    bytes32 public donId;
    uint32 public callbackGasLimit;
    string public source; // the JavaScript the DON runs
    uint8 public donHostedSecretsSlotID;
    uint64 public donHostedSecretsVersion;

    struct Valuation {
        uint256 valuationUsd;
        uint16 confidence;
        uint256 timestamp;
        bool applied; // true if written to NAV, false if flagged for review
    }

    mapping(bytes32 => bytes32) public requestToProperty; // Functions requestId -> propertyId
    mapping(bytes32 => Valuation) public latestValuation; // propertyId -> last result
    mapping(bytes32 => uint256) public flaggedValuationUsd; // propertyId -> out-of-tolerance value awaiting review

    event ValuationRequested(bytes32 indexed requestId, bytes32 indexed propertyId);
    event ValuationApplied(bytes32 indexed propertyId, uint256 valuationUsd, uint16 confidence);
    event ValuationFlagged(bytes32 indexed propertyId, uint256 valuationUsd, uint256 prevValuationUsd);
    event ValuationRejected(bytes32 indexed propertyId, uint16 confidence, bytes err);
    event RequestConfigSet(uint64 subscriptionId, bytes32 donId, uint32 callbackGasLimit);
    event SecretsConfigSet(uint8 slotID, uint64 version);

    error LowConfidence(uint16 confidence);

    constructor(
        address functionsRouter,
        address nav_,
        uint64 subscriptionId_,
        bytes32 donId_,
        uint32 callbackGasLimit_,
        string memory source_
    ) FunctionsClient(functionsRouter) Ownable(msg.sender) {
        require(nav_ != address(0), "nav=0");
        nav = INavSink(nav_);
        subscriptionId = subscriptionId_;
        donId = donId_;
        callbackGasLimit = callbackGasLimit_;
        source = source_;
    }

    // --- configuration -------------------------------------------------------

    function setRequestConfig(uint64 subscriptionId_, bytes32 donId_, uint32 callbackGasLimit_) external onlyOwner {
        subscriptionId = subscriptionId_;
        donId = donId_;
        callbackGasLimit = callbackGasLimit_;
        emit RequestConfigSet(subscriptionId_, donId_, callbackGasLimit_);
    }

    function setSource(string calldata source_) external onlyOwner {
        source = source_;
    }

    /// @notice Point the request at the DON-hosted encrypted secrets (the AI API key).
    function setDonHostedSecrets(uint8 slotID, uint64 version) external onlyOwner {
        donHostedSecretsSlotID = slotID;
        donHostedSecretsVersion = version;
        emit SecretsConfigSet(slotID, version);
    }

    // --- request -------------------------------------------------------------

    /// @notice Request an AI/AVM valuation for `propertyId`.
    /// @param propertyId The property identifier (also stored on RealEstateNAV).
    /// @param args Source arguments: [propertyId, addressLine, sqft, beds, baths].
    function requestValuation(bytes32 propertyId, string[] calldata args) external onlyOwner returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        if (args.length > 0) {
            req.setArgs(args);
        }
        if (donHostedSecretsVersion > 0) {
            req.addDONHostedSecrets(donHostedSecretsSlotID, donHostedSecretsVersion);
        }
        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, callbackGasLimit, donId);
        requestToProperty[requestId] = propertyId;
        emit ValuationRequested(requestId, propertyId);
        return requestId;
    }

    // --- fulfilment ----------------------------------------------------------

    /// @inheritdoc FunctionsClient
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        bytes32 propertyId = requestToProperty[requestId];

        if (err.length > 0 || response.length == 0) {
            emit ValuationRejected(propertyId, 0, err);
            return;
        }

        uint256 packed = abi.decode(response, (uint256));
        uint256 valuationUsd = uint128(packed); // low 128 bits
        uint16 confidence = uint16(packed >> 128); // high bits

        // Guardrail 1: reject low-confidence model output.
        if (confidence < MIN_CONFIDENCE) {
            emit ValuationRejected(propertyId, confidence, err);
            return;
        }

        // Guardrail 2: bound how far one update may move NAV; flag large moves for review.
        uint256 prev = nav.propertyValueUsd(propertyId);
        if (prev != 0 && _deviationBps(prev, valuationUsd) > MAX_DEVIATION_BPS) {
            flaggedValuationUsd[propertyId] = valuationUsd;
            latestValuation[propertyId] = Valuation(valuationUsd, confidence, block.timestamp, false);
            emit ValuationFlagged(propertyId, valuationUsd, prev);
            return;
        }

        nav.setPropertyValueUsd(propertyId, valuationUsd);
        latestValuation[propertyId] = Valuation(valuationUsd, confidence, block.timestamp, true);
        emit ValuationApplied(propertyId, valuationUsd, confidence);
    }

    /// @notice Owner/multisig approval path for a previously flagged out-of-tolerance valuation.
    function applyFlaggedValuation(bytes32 propertyId) external onlyOwner {
        uint256 v = flaggedValuationUsd[propertyId];
        require(v != 0, "nothing flagged");
        delete flaggedValuationUsd[propertyId];
        nav.setPropertyValueUsd(propertyId, v);
        latestValuation[propertyId].applied = true;
        emit ValuationApplied(propertyId, v, latestValuation[propertyId].confidence);
    }

    function _deviationBps(uint256 prev, uint256 next) internal pure returns (uint256) {
        uint256 diff = next > prev ? next - prev : prev - next;
        return (diff * 10_000) / prev;
    }
}
