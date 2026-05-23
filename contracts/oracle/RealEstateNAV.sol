// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title RealEstateNAV
/// @notice Demonstrates safe Chainlink **Data Feeds** consumption for an RWA system:
///         - reads an ETH/USD feed to convert between USD-denominated property values and crypto;
///         - stores a per-property Net Asset Value (NAV) in whole USD, written by an authorized
///           valuation updater (in Cornerstone, the Chainlink Functions / AI consumer).
/// @dev Every feed read applies the three non-negotiable checks: positive answer, completed
///      round, and freshness within a configured heartbeat. See docs/data-feeds.md.
contract RealEstateNAV is Ownable {
    /// @notice The ETH/USD price feed used for USD <-> crypto conversion.
    AggregatorV3Interface public immutable ethUsdFeed;

    /// @notice Maximum acceptable age (seconds) of the ETH/USD answer before it is "stale".
    uint256 public ethUsdHeartbeat;

    /// @notice Address permitted to push property valuations (e.g. PropertyValuationConsumer).
    address public valuationUpdater;

    /// @notice Latest NAV per property, in whole US dollars.
    mapping(bytes32 => uint256) public propertyValueUsd;
    /// @notice Block timestamp of the latest valuation per property.
    mapping(bytes32 => uint256) public lastValuationAt;

    event ValuationUpdaterSet(address indexed updater);
    event EthUsdHeartbeatSet(uint256 heartbeat);
    event PropertyValuationUpdated(bytes32 indexed propertyId, uint256 valueUsd);

    error InvalidPrice(int256 answer);
    error StalePrice(uint256 updatedAt, uint256 heartbeat);
    error NotValuationUpdater(address caller);

    constructor(address ethUsdFeed_, uint256 ethUsdHeartbeat_) Ownable(msg.sender) {
        require(ethUsdFeed_ != address(0), "feed=0");
        ethUsdFeed = AggregatorV3Interface(ethUsdFeed_);
        ethUsdHeartbeat = ethUsdHeartbeat_;
    }

    // --- admin ---------------------------------------------------------------

    function setValuationUpdater(address updater) external onlyOwner {
        valuationUpdater = updater;
        emit ValuationUpdaterSet(updater);
    }

    function setEthUsdHeartbeat(uint256 heartbeat) external onlyOwner {
        ethUsdHeartbeat = heartbeat;
        emit EthUsdHeartbeatSet(heartbeat);
    }

    // --- Data Feeds: ETH/USD with safety checks ------------------------------

    /// @notice Returns the validated ETH/USD price and the feed's decimals.
    /// @dev Reverts (fail-closed) on a non-positive answer, an incomplete round, or a stale price.
    function getEthUsdPrice() public view returns (uint256 price, uint8 priceDecimals) {
        (, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = ethUsdFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice(answer);
        if (updatedAt == 0 || answeredInRound == 0) revert StalePrice(updatedAt, ethUsdHeartbeat);
        if (block.timestamp - updatedAt > ethUsdHeartbeat) revert StalePrice(updatedAt, ethUsdHeartbeat);
        return (uint256(answer), ethUsdFeed.decimals());
    }

    /// @notice Convert a whole-USD amount to wei using the live ETH/USD price.
    function usdToWei(uint256 usdAmount) external view returns (uint256) {
        (uint256 price, uint8 dec) = getEthUsdPrice();
        // wei = usd * 10^dec * 1e18 / price   (price is USD-per-ETH scaled by 10^dec)
        return (usdAmount * (10 ** dec) * 1e18) / price;
    }

    /// @notice Convert a wei amount to whole USD using the live ETH/USD price.
    function weiToUsd(uint256 weiAmount) external view returns (uint256) {
        (uint256 price, uint8 dec) = getEthUsdPrice();
        return (weiAmount * price) / (1e18 * (10 ** dec));
    }

    // --- Property NAV (written by the valuation updater) ---------------------

    /// @notice Record a property's latest NAV in whole USD.
    /// @dev Restricted to the valuation updater (the Functions/AI consumer) or the owner.
    function setPropertyValueUsd(bytes32 propertyId, uint256 valueUsd) external {
        if (msg.sender != valuationUpdater && msg.sender != owner()) {
            revert NotValuationUpdater(msg.sender);
        }
        propertyValueUsd[propertyId] = valueUsd;
        lastValuationAt[propertyId] = block.timestamp;
        emit PropertyValuationUpdated(propertyId, valueUsd);
    }
}
