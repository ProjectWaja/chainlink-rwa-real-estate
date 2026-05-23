// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @title AllocationLottery
/// @notice Fairly allocates an **oversubscribed** PropertyToken sale using **Chainlink VRF 2.5**.
///         Investors enter while the sale is open; the owner closes it and requests a verifiable
///         random word; winners are then derived deterministically from that seed via a partial
///         Fisher–Yates shuffle — reproducible given the seed, yet unbiasable by anyone.
/// @dev Inherits ownership from VRFConsumerBaseV2Plus (ConfirmedOwner). The VRF callback only
///      *stores the seed* (cheap, within the callback gas limit); winner derivation is a separate
///      view. State guards prevent acting before fulfilment and prevent re-rolling. See docs/vrf.md.
contract AllocationLottery is VRFConsumerBaseV2Plus {
    enum Phase {
        Open, // accepting entrants
        Drawing, // randomness requested, awaiting fulfilment
        Drawn // seed received, winners derivable

    }

    // VRF request configuration.
    bytes32 public keyHash;
    uint256 public subId;
    uint16 public requestConfirmations = 3;
    uint32 public callbackGasLimit = 200_000;
    bool public nativePayment;

    Phase public phase = Phase.Open;
    uint256 public numWinners; // size of the available allocation

    address[] public entrants;
    mapping(address => bool) public hasEntered;

    uint256 public lastRequestId;
    uint256 public randomSeed;
    bool public seeded;

    event Entered(address indexed investor);
    event DrawRequested(uint256 indexed requestId);
    event Seeded(uint256 indexed requestId, uint256 seed);

    error WrongPhase(Phase expected, Phase actual);
    error AlreadyEntered();
    error NoEntrants();
    error AlreadySeeded();

    constructor(address vrfCoordinator, bytes32 keyHash_, uint256 subId_, uint256 numWinners_)
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        require(numWinners_ > 0, "numWinners=0");
        keyHash = keyHash_;
        subId = subId_;
        numWinners = numWinners_;
    }

    // --- config (owner) ------------------------------------------------------

    function setRequestConfig(
        bytes32 keyHash_,
        uint256 subId_,
        uint16 requestConfirmations_,
        uint32 callbackGasLimit_,
        bool nativePayment_
    ) external onlyOwner {
        keyHash = keyHash_;
        subId = subId_;
        requestConfirmations = requestConfirmations_;
        callbackGasLimit = callbackGasLimit_;
        nativePayment = nativePayment_;
    }

    // --- entry ---------------------------------------------------------------

    function enter() external {
        if (phase != Phase.Open) revert WrongPhase(Phase.Open, phase);
        if (hasEntered[msg.sender]) revert AlreadyEntered();
        hasEntered[msg.sender] = true;
        entrants.push(msg.sender);
        emit Entered(msg.sender);
    }

    // --- draw ----------------------------------------------------------------

    /// @notice Close the sale and request randomness. Owner only.
    function closeAndDraw() external onlyOwner returns (uint256 requestId) {
        if (phase != Phase.Open) revert WrongPhase(Phase.Open, phase);
        if (entrants.length == 0) revert NoEntrants();
        phase = Phase.Drawing;
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment}))
            })
        );
        lastRequestId = requestId;
        emit DrawRequested(requestId);
    }

    /// @inheritdoc VRFConsumerBaseV2Plus
    /// @dev Keep this minimal: only store the seed. Winner derivation happens off the hot path.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        if (phase != Phase.Drawing) revert WrongPhase(Phase.Drawing, phase);
        if (seeded) revert AlreadySeeded();
        randomSeed = randomWords[0];
        seeded = true;
        phase = Phase.Drawn;
        emit Seeded(requestId, randomSeed);
    }

    // --- results -------------------------------------------------------------

    function entrantCount() external view returns (uint256) {
        return entrants.length;
    }

    /// @notice Deterministically derive the winners from the verified seed.
    /// @dev Partial Fisher–Yates shuffle. If entrants <= numWinners, everyone wins.
    function drawWinners() public view returns (address[] memory winners) {
        require(seeded, "not seeded");
        uint256 n = entrants.length;
        uint256 k = numWinners >= n ? n : numWinners;

        address[] memory pool = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            pool[i] = entrants[i];
        }

        winners = new address[](k);
        for (uint256 i = 0; i < k; i++) {
            uint256 j = i + (uint256(keccak256(abi.encode(randomSeed, i))) % (n - i));
            (pool[i], pool[j]) = (pool[j], pool[i]);
            winners[i] = pool[i];
        }
    }

    /// @notice Whether `account` is among the derived winners.
    function isWinner(address account) external view returns (bool) {
        address[] memory w = drawWinners();
        for (uint256 i = 0; i < w.length; i++) {
            if (w[i] == account) return true;
        }
        return false;
    }
}
