// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/// @title RentalDistributor
/// @notice Distributes rental income (an ERC-20 stablecoin) pro-rata to PropertyToken holders,
///         on a schedule driven by **Chainlink Automation**. Distribution is **pull-based**: a
///         distribution only updates a per-share accumulator (O(1)); holders later `claim()` what
///         they're owed. This keeps cost independent of the number of holders (no unbounded loop).
/// @dev Uses the classic "cumulative income per share" pattern. NOTE (educational caveat): because
///      this distributor cannot hook the share token's transfers, it allocates by *current* balance
///      against the accumulator. In production, pair it with a snapshot/checkpoint share token
///      (e.g. ERC20Votes/ERC20Snapshot) or fold the accounting into the token's `_update` hook so
///      mid-period transfers are corrected. See docs/automation.md.
contract RentalDistributor is Ownable, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;

    uint256 private constant SCALE = 1e18;

    IERC20 public immutable shareToken; // PropertyToken (the pro-rata basis)
    IERC20 public immutable incomeToken; // stablecoin paid out as rent

    uint256 public interval; // minimum seconds between distributions
    uint256 public lastDistribution; // timestamp of the last distribution
    uint256 public pendingIncome; // deposited but not yet distributed
    uint256 public cumulativeIncomePerShare; // scaled by SCALE

    mapping(address => uint256) public withdrawnPerShare; // per-holder high-water mark
    mapping(address => uint256) public totalClaimed; // lifetime claimed, for views

    event IncomeDeposited(address indexed from, uint256 amount);
    event IncomeDistributed(uint256 amount, uint256 supply, uint256 cumulativePerShare);
    event Claimed(address indexed holder, uint256 amount);
    event IntervalSet(uint256 interval);

    error NotReady();
    error NothingToClaim();

    constructor(address shareToken_, address incomeToken_, uint256 interval_) Ownable(msg.sender) {
        require(shareToken_ != address(0) && incomeToken_ != address(0), "zero addr");
        shareToken = IERC20(shareToken_);
        incomeToken = IERC20(incomeToken_);
        interval = interval_;
        lastDistribution = block.timestamp;
    }

    function setInterval(uint256 interval_) external onlyOwner {
        interval = interval_;
        emit IntervalSet(interval_);
    }

    /// @notice Deposit rental income to be distributed at the next interval.
    function depositIncome(uint256 amount) external {
        require(amount > 0, "amount=0");
        incomeToken.safeTransferFrom(msg.sender, address(this), amount);
        pendingIncome += amount;
        emit IncomeDeposited(msg.sender, amount);
    }

    // --- Chainlink Automation -------------------------------------------------

    /// @inheritdoc AutomationCompatibleInterface
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = _ready();
        return (upkeepNeeded, "");
    }

    /// @inheritdoc AutomationCompatibleInterface
    /// @dev Re-validates the condition on-chain; anyone may call performUpkeep.
    function performUpkeep(bytes calldata) external override {
        if (!_ready()) revert NotReady();
        uint256 supply = shareToken.totalSupply();
        uint256 amount = pendingIncome;
        pendingIncome = 0;
        lastDistribution = block.timestamp;
        cumulativeIncomePerShare += (amount * SCALE) / supply;
        emit IncomeDistributed(amount, supply, cumulativeIncomePerShare);
    }

    function _ready() internal view returns (bool) {
        return block.timestamp - lastDistribution >= interval && pendingIncome > 0 && shareToken.totalSupply() > 0;
    }

    // --- claims --------------------------------------------------------------

    /// @notice Income currently claimable by `holder`.
    function claimable(address holder) public view returns (uint256) {
        uint256 owedPerShare = cumulativeIncomePerShare - withdrawnPerShare[holder];
        return (shareToken.balanceOf(holder) * owedPerShare) / SCALE;
    }

    /// @notice Claim your accrued rental income.
    function claim() external returns (uint256 owed) {
        owed = claimable(msg.sender);
        if (owed == 0) revert NothingToClaim();
        withdrawnPerShare[msg.sender] = cumulativeIncomePerShare;
        totalClaimed[msg.sender] += owed;
        incomeToken.safeTransfer(msg.sender, owed);
        emit Claimed(msg.sender, owed);
    }
}
