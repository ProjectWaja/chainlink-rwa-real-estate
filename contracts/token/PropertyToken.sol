// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title PropertyToken
/// @notice An ERC-20 representing fractional ownership of a real-estate property (or fund),
///         whose minting is gated by a Chainlink **Proof of Reserve** feed. New tokens can only
///         be minted while the attested off-chain reserves cover the resulting supply, so the
///         token cannot be inflated beyond the real assets backing it.
/// @dev Fail-closed: any feed problem (non-positive, incomplete, or stale answer) blocks minting.
///      Burns and transfers are never blocked — reducing supply only improves collateralization.
///      See docs/proof-of-reserve.md.
contract PropertyToken is ERC20, Ownable {
    /// @notice Proof-of-Reserve feed reporting attested reserve value (in USD, scaled by its decimals).
    AggregatorV3Interface public porFeed;
    /// @notice Maximum acceptable age (seconds) of the PoR attestation before minting pauses.
    uint256 public porHeartbeat;
    /// @notice Price of one whole token in whole US dollars (the valuation peg used by the guard).
    uint256 public pricePerTokenUsd;
    /// @notice Emergency switch to halt minting (e.g. set by a CRE solvency workflow).
    bool public mintingPaused;

    event PorFeedSet(address indexed feed, uint256 heartbeat);
    event PricePerTokenSet(uint256 pricePerTokenUsd);
    event MintingPaused(bool paused);

    error InvalidReserves(int256 answer);
    error StaleReserves(uint256 updatedAt, uint256 heartbeat);
    error MintingIsPaused();
    error ExceedsReserves(uint256 requestedSupply, uint256 maxBackedSupply);

    constructor(
        string memory name_,
        string memory symbol_,
        address porFeed_,
        uint256 porHeartbeat_,
        uint256 pricePerTokenUsd_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(porFeed_ != address(0), "porFeed=0");
        require(pricePerTokenUsd_ > 0, "price=0");
        porFeed = AggregatorV3Interface(porFeed_);
        porHeartbeat = porHeartbeat_;
        pricePerTokenUsd = pricePerTokenUsd_;
    }

    // --- admin ---------------------------------------------------------------

    function setPorFeed(address feed, uint256 heartbeat) external onlyOwner {
        require(feed != address(0), "porFeed=0");
        porFeed = AggregatorV3Interface(feed);
        porHeartbeat = heartbeat;
        emit PorFeedSet(feed, heartbeat);
    }

    function setPricePerTokenUsd(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "price=0");
        pricePerTokenUsd = newPrice;
        emit PricePerTokenSet(newPrice);
    }

    /// @notice Halt minting. Callable by the owner (in Cornerstone, also via a CRE solvency check).
    function pauseMinting() external onlyOwner {
        mintingPaused = true;
        emit MintingPaused(true);
    }

    function unpauseMinting() external onlyOwner {
        mintingPaused = false;
        emit MintingPaused(false);
    }

    // --- Proof of Reserve ----------------------------------------------------

    /// @notice The validated attested reserve value (raw feed answer) and the feed's decimals.
    function attestedReserves() public view returns (uint256 reserves, uint8 reservesDecimals) {
        (, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = porFeed.latestRoundData();
        if (answer <= 0) revert InvalidReserves(answer);
        if (updatedAt == 0 || answeredInRound == 0) revert StaleReserves(updatedAt, porHeartbeat);
        if (block.timestamp - updatedAt > porHeartbeat) revert StaleReserves(updatedAt, porHeartbeat);
        return (uint256(answer), porFeed.decimals());
    }

    /// @notice The maximum token supply (in 18-decimal base units) the attested reserves can back.
    function maxBackedSupply() public view returns (uint256) {
        (uint256 reserves, uint8 dec) = attestedReserves();
        // reserves is USD scaled by 10^dec; pricePerTokenUsd is whole USD.
        // tokens = reserves / (pricePerTokenUsd * 10^dec); * 1e18 for base units.
        return (reserves * 1e18) / (pricePerTokenUsd * (10 ** dec));
    }

    // --- mint / burn ---------------------------------------------------------

    /// @notice Mint `amount` (18-decimal base units) to `to`, only if reserves still cover supply.
    function mint(address to, uint256 amount) external onlyOwner {
        if (mintingPaused) revert MintingIsPaused();
        uint256 maxSupply = maxBackedSupply();
        uint256 newSupply = totalSupply() + amount;
        if (newSupply > maxSupply) revert ExceedsReserves(newSupply, maxSupply);
        _mint(to, amount);
    }

    /// @notice Burn your own tokens. Always allowed — it can only improve collateralization.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
