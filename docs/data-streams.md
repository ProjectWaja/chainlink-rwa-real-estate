# Chainlink Data Streams (upgrade path)

Cornerstone's day-to-day pricing uses push-based [Data Feeds](./data-feeds.md). **Data Streams**
are the low-latency, pull-based complement — documented here as the upgrade path rather than
implemented as a separate consumer, because they shine in a narrower set of RWA scenarios.

## Push (Data Feeds) vs. pull (Data Streams)

| | Data Feeds | Data Streams |
|---|---|---|
| Delivery | Chainlink pushes updates on heartbeat/deviation | Your tx *pulls* a signed report on demand |
| Latency | Seconds–minutes | Sub-second |
| Cost model | Free to read | Pay per verified report |
| Best for | NAV, FX conversion, slow-moving values | Auctions, liquidations, fast settlement |

## Where Cornerstone would use Streams

- **Property-token auctions / secondary trading.** If tokens trade against a fast market,
  settling at a sub-second verified price reduces the window for stale-price arbitrage.
- **Collateralised lending against property tokens.** Liquidations need fresh prices exactly at
  the moment of action — the pull model fits.

## The pattern (for when you add it)

1. An Automation **`StreamsLookup`** upkeep (or your own keeper) fetches the signed report
   off-chain.
2. The report is passed into your contract, which calls the **verifier** contract to validate
   the signatures on-chain before trusting the price.
3. Settlement proceeds against the just-verified price in the same transaction.

Because Streams couples cleanly with Automation's `StreamsLookup`, the natural place to graft
it on is the auction/lending modules — left as a documented extension so the core repo stays
focused on the mature, free-to-read Data Feeds.
