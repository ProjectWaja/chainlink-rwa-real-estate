// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/// @title ConstructionEscrow
/// @notice Milestone-based escrow for financing construction. Investor capital is locked and
///         released to the builder only when a milestone is verified complete, and reclaimable
///         if a milestone blows its deadline. Two Chainlink products plug in here:
///           - **Functions + AI**: an off-chain inspection/AI check (milestone-verification.js)
///             confirms completion; that consumer is the `verifier` allowed to confirm milestones.
///           - **Automation**: `checkUpkeep`/`performUpkeep` move overdue milestones to `Overdue`
///             with no human in the loop, freeing capital to be reclaimed.
/// @dev See docs/automation.md and docs/functions-and-ai.md.
contract ConstructionEscrow is Ownable, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;

    enum State {
        Pending, // awaiting verification
        Completed, // verified complete, funds releasable to builder
        Released, // funds paid to builder
        Overdue // deadline passed without verification, funds reclaimable by funder

    }

    struct Milestone {
        string title;
        uint256 amount;
        uint256 deadline;
        State state;
    }

    IERC20 public immutable fundingToken;
    address public immutable builder;
    /// @notice Address allowed to confirm milestone completion (the Functions/AI verifier consumer).
    address public verifier;
    /// @notice Whoever funded the escrow; receives refunds for overdue milestones.
    address public funder;
    bool public funded;

    Milestone[] public milestones;
    uint256 public totalLocked;

    event MilestoneAdded(uint256 indexed index, string title, uint256 amount, uint256 deadline);
    event Funded(address indexed funder, uint256 total);
    event MilestoneConfirmed(uint256 indexed index, uint16 confidence);
    event MilestoneReleased(uint256 indexed index, address indexed builder, uint256 amount);
    event MilestoneOverdue(uint256 indexed index);
    event MilestoneReclaimed(uint256 indexed index, address indexed funder, uint256 amount);
    event VerifierSet(address indexed verifier);

    error NotVerifier(address caller);
    error AlreadyFunded();
    error NotFunded();
    error BadState(uint256 index, State actual);
    error NotYetDue(uint256 index);

    constructor(address fundingToken_, address builder_, address verifier_) Ownable(msg.sender) {
        require(fundingToken_ != address(0) && builder_ != address(0), "zero addr");
        fundingToken = IERC20(fundingToken_);
        builder = builder_;
        verifier = verifier_;
    }

    modifier onlyVerifier() {
        if (msg.sender != verifier && msg.sender != owner()) revert NotVerifier(msg.sender);
        _;
    }

    // --- setup ---------------------------------------------------------------

    function setVerifier(address verifier_) external onlyOwner {
        verifier = verifier_;
        emit VerifierSet(verifier_);
    }

    /// @notice Define a milestone (only before funding).
    function addMilestone(string calldata title, uint256 amount, uint256 deadline) external onlyOwner {
        if (funded) revert AlreadyFunded();
        require(amount > 0 && deadline > block.timestamp, "bad milestone");
        milestones.push(Milestone({title: title, amount: amount, deadline: deadline, state: State.Pending}));
        emit MilestoneAdded(milestones.length - 1, title, amount, deadline);
    }

    /// @notice Lock the total of all milestone amounts into escrow. Caller becomes the funder.
    function fund() external {
        if (funded) revert AlreadyFunded();
        uint256 total;
        for (uint256 i = 0; i < milestones.length; i++) {
            total += milestones[i].amount;
        }
        require(total > 0, "no milestones");
        funded = true;
        funder = msg.sender;
        totalLocked = total;
        fundingToken.safeTransferFrom(msg.sender, address(this), total);
        emit Funded(msg.sender, total);
    }

    // --- verification & release ---------------------------------------------

    /// @notice Confirm a milestone is complete. Called by the AI/Functions verifier consumer.
    /// @param index Milestone index.
    /// @param confidence Confidence (0..100) from the verification model (recorded for audit).
    function confirmMilestone(uint256 index, uint16 confidence) external onlyVerifier {
        Milestone storage m = milestones[index];
        if (m.state != State.Pending) revert BadState(index, m.state);
        m.state = State.Completed;
        emit MilestoneConfirmed(index, confidence);
    }

    /// @notice Release a confirmed milestone's funds to the builder. Anyone may trigger.
    function releaseMilestone(uint256 index) external {
        if (!funded) revert NotFunded();
        Milestone storage m = milestones[index];
        if (m.state != State.Completed) revert BadState(index, m.state);
        m.state = State.Released;
        totalLocked -= m.amount;
        fundingToken.safeTransfer(builder, m.amount);
        emit MilestoneReleased(index, builder, m.amount);
    }

    /// @notice Reclaim funds for an overdue milestone back to the funder.
    function reclaim(uint256 index) external {
        Milestone storage m = milestones[index];
        if (m.state != State.Overdue) revert BadState(index, m.state);
        m.state = State.Released; // terminal; funds leave escrow
        totalLocked -= m.amount;
        fundingToken.safeTransfer(funder, m.amount);
        emit MilestoneReclaimed(index, funder, m.amount);
    }

    // --- Chainlink Automation: deadline enforcement --------------------------

    /// @inheritdoc AutomationCompatibleInterface
    /// @dev Off-chain & free: returns the first Pending milestone whose deadline has passed.
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        if (!funded) return (false, "");
        for (uint256 i = 0; i < milestones.length; i++) {
            Milestone storage m = milestones[i];
            if (m.state == State.Pending && block.timestamp > m.deadline) {
                return (true, abi.encode(i));
            }
        }
        return (false, "");
    }

    /// @inheritdoc AutomationCompatibleInterface
    /// @dev Re-validates on-chain (never trusts performData blindly) before mutating state.
    function performUpkeep(bytes calldata performData) external override {
        uint256 index = abi.decode(performData, (uint256));
        Milestone storage m = milestones[index];
        if (m.state != State.Pending) revert BadState(index, m.state);
        if (block.timestamp <= m.deadline) revert NotYetDue(index);
        m.state = State.Overdue;
        emit MilestoneOverdue(index);
    }

    // --- views ---------------------------------------------------------------

    function milestoneCount() external view returns (uint256) {
        return milestones.length;
    }
}
