# Chainlink Data Feeds in Cornerstone

Data Feeds are the most mature Chainlink product: decentralized, aggregated price data pushed
on-chain. Cornerstone uses them wherever a contract needs a reliable market price.

## Where they're used

- **USD ⇆ crypto settlement.** Property values are denominated in USD, but investors pay in
  ETH or a stablecoin. `RealEstateNAV` reads the `ETH/USD` feed to convert a USD price into
  the wei a buyer must send, and vice-versa.
- **NAV denomination.** Net Asset Value per token is tracked in USD; Data Feeds let any
  consumer convert that to the chain's native asset at settlement time.

## The non-negotiable safety checks

A surprising number of exploits come from reading a feed naively. `RealEstateNAV` demonstrates
the checks every Data Feed consumer should make:

```solidity
(uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) =
    feed.latestRoundData();

require(answer > 0, "negative/zero price");          // sanity
require(updatedAt != 0, "round not complete");        // round actually finished
require(block.timestamp - updatedAt <= heartbeat, "stale price"); // not stale
// scale by feed.decimals() — never assume 8 or 18
```

| Pitfall | Consequence | Mitigation in `RealEstateNAV` |
|---|---|---|
| Assuming 18 decimals | Off-by-10^10 valuation errors | Read and apply `feed.decimals()` |
| Ignoring `updatedAt` | Trading on a frozen price | Heartbeat staleness check |
| Trusting `answer <= 0` | Underflow / nonsense math | Explicit `answer > 0` |
| Hard-coding feed addresses | Wrong feed on wrong chain | Addresses injected per-network in deploy config |

## Data Feeds vs. Data Streams

Push-based **Data Feeds** update on a heartbeat/deviation schedule and are perfect for the
periodic NAV and FX conversions Cornerstone needs. For latency-sensitive settlement (e.g.
auctioning a property token against a fast-moving market) Chainlink **Data Streams** offer
pull-based, sub-second prices fetched and verified on demand. Cornerstone documents Streams as
the upgrade path; see [data-streams.md](./data-streams.md).

## Files

| File | Role |
|---|---|
| `contracts/oracle/RealEstateNAV.sol` | Reads ETH/USD + property NAV feeds with full safety checks |
| `contracts/mocks/MockAggregatorV3.sol` | Configurable mock feed used in tests |
