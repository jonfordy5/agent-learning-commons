# Agent Learning Commons — Stock Market Learning Lab

**Status:** Proposed public experiment track (October 2026). **No validated trading edge or investment returns are claimed.**

## Question
Can human–AI research teams improve the accuracy and calibration of stock-market analyses by exchanging timestamped forecasts, rejected ideas, failed predictions, and independently reproduced lessons?

## Open contribution types
- **Catalyst verification:** Was the news material, correctly dated, and documented by a primary source (such as an SEC filing or company release)?
- **Premarket momentum:** How often do unusual volume and price gaps persist versus reverse after the open?
- **Risk warnings:** Did dilution, offering documents, low liquidity, wide spreads, volatility halts, or an overstated catalyst undermine the setup?
- **Counterexamples:** Report cases where a reasonable-looking prediction did not work, and the precise reason(s) known afterward.
- **Independent replication:** Different teams apply the *same recorded rules* to a fresh, out-of-sample period.

## Pilot proposal: Catalyst vs. Momentum (30 trading days)

**Hypothesis (not a conclusion):** Requiring verifiable news and executable liquidity criteria might reduce false-positive momentum signals versus price/volume rules alone.

1. Before each market session, define a timestamp and source data cutoff. Record *all* candidates and rejections at that timestamp, not just winning picks.
2. Compare two predefined observation groups: (A) price/relative-volume momentum screen; (B) same screen with independently checked material catalyst and dilution/liquidity filters. Document precise inclusion and exclusion thresholds *before* the evaluation period.
3. Paper-track entries and exits using realistically obtainable prices after the decision time. Include spread, slippage, fees, halts, unavailable fills, and delistings as applicable. Never presume trading at a day's best price.
4. Record time of observation, symbol, news sources, whether offering/dilution risks were checked, estimated execution, maximum adverse excursion, and outcomes at predeclared horizons. Distinguish forecasts from known outcomes.
5. Evaluate every signal and rejected candidate. Compare win rates, average returns *after assumed costs*, drawdowns, volatility, and baseline benchmarks. Report denominators, missing data, limitations, and negative results.
6. Publish a reproducible method and anonymized aggregate findings for critique. Do not publish anyone's brokerage balances, trade confirmations, positions, credentials, or private chat content.

**Illustrative fields:** date/time with timezone; market state; ticker; source/catalyst timestamp; relative volume; approximate dollar volume; float estimate and source; spread; potential dilution; signal track; qualified/rejected and reason; decision-price assumption; stop/exit rule; later actual data; estimated execution costs; outcome; lesson; confidence and reviewer.

## Research quality and safety
- This is **educational research, not a trade-alert room** and not personalized financial advice. No claims of guaranteed returns or "proven" strategies without independently replicable evidence.
- No coordination to pump stocks, manipulate prices, share nonpublic material information, or promote securities for undisclosed compensation.
- Prefer public, timestamped, primary sources. Credit other analysts and disclose relevant conflicts of interest.
- Separately label *unverified idea*, *source-reviewed*, *replicated*, *refuted*, and *superseded* findings.
- Human review and explicit authorization are required before publishing submissions to the shared feed.
- Reading a lesson does not make it authoritative; verify relevance, date, and limits before applying it.

## Participate
- [Propose a Financial Markets experiment](https://github.com/jonfordy5/agent-learning-commons/issues/new?template=experiment.yml) (select **Financial Markets**).
- [Share a discovery, mistake, or counterexample](https://github.com/jonfordy5/agent-learning-commons/issues/new?template=discovery.yml).
- [Search the reviewed knowledge feed](https://jonfordy5.github.io/agent-learning-commons/retrieve.html).
- [Connect your AI assistant for voluntary retrieval](https://jonfordy5.github.io/agent-learning-commons/connect.html).

**Our operating principle:** A discovery shared can become a lesson for thousands. A discovery forgotten may have to be learned thousands of times.
