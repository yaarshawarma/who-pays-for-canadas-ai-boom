# Who Pays for Canada's AI Boom?
### Public research for Canadian individual investors — Starter project

> **Status (v0.1.1, 2026-11-07): work in progress. No validated findings yet.** The Module 01 pipeline runs and passes its automated reconciliation tests, but external price checks are incomplete, so all numerical outputs are marked `UNVALIDATED`. Educational research only; not investment advice. Code: MIT. Documentation: CC BY 4.0 (see `LICENSE`).

**Research question:** Are listed Canadian electricity-infrastructure businesses an attractive way to gain exposure to AI-driven power demand **after accounting for risk, financial fundamentals, and valuation**?

This is an **independent educational research project**, not a sponsored Jarislowsky Fraser or Scotiabank project, and not personal investment advice. The first empirical study compares Hydro One (TSX: H) and Fortis (TSX: FTS) with a broad Canadian stock-market proxy, XIC (TSX: XIC). It does **not** claim that any historical returns were caused by AI-related demand.

## Why this is useful

Canadian investors can follow headlines about expanding data centres without knowing whether the investment opportunity is already priced in, whether shareholders earn reasonable returns for the risks, or how regulated utility economics shape profits. We aim to make the underlying evidence, limitations, and assumptions accessible and reproducible.

## First deliverable — market risk and historical performance

Run an original R implementation of relevant ECON 4140 techniques:
- adjusted historical prices and **simple daily returns** for investment performance
- log returns for **AR(1)** exploratory time-series modelling
- CAPM excess-return regression using a **Canadian three-month Treasury bill yield**
- beta, 95% beta confidence intervals, tests against beta=0 and beta=1
- 126-trading-day rolling beta, annualized volatility, Sharpe ratio, historical drawdown
- residual autocorrelation diagnostics (Ljung-Box)

**What is not yet included:** a financial statement/valuation model, causal claims about AI expansion, ARCH/GARCH, Value-at-Risk, a live website, or validated numerical findings. Those belong in subsequent research modules.

## How to run

1. Install R 4.3+ (developed on R 4.6.2). Package versions are pinned in `renv.lock`; run `renv::restore()` to reproduce them, or install `quantmod xts zoo jsonlite ggplot2 sandwich lmtest`.
2. From this folder (the project root), run:

```bash
Rscript R/01_market_risk.R
Rscript tests/test_g2_reconciliation.R
```

The first run downloads raw data into `data/raw/<as_of>/` with a `manifest.csv` (source, retrieval time, MD5). Later runs reuse that snapshot so results are reproducible; set `REFRESH_DATA=1` to download again.

3. Outputs (all marked `validation_status = UNVALIDATED` until the G2 checks and manual price checks pass):
   - `data/processed/aligned_daily_returns.csv`: aligned returns, risk-free observation date/yield/daily rate
   - `outputs/coverage_report.csv`: rows, date range, missing values, dates dropped by the inner join
   - `outputs/capm_results.csv`: CAPM with OLS and Newey-West (HAC) inference, tests of beta=0 and beta=1, Durbin-Watson
   - `outputs/capm_sensitivity.csv`: risk-free timing/day-count variants and subsamples
   - `outputs/performance_results.csv`: total and annualized return, volatility, Sharpe (excess-return), max drawdown
   - `outputs/rolling_beta.csv`, `outputs/rolling_beta.png`: 126- and 252-day trailing beta (draft chart)
   - `outputs/ar1_checks.csv`: exploratory AR(1) with Ljung-Box on residuals and squared residuals
   - `outputs/g2_automated_checks.csv`: independent recomputation checks
   - `tests/manual_price_checks.csv`: template for checking 9 prices against an external source by hand

Conventions and the changes from the original starter are documented in `docs/methodology.md`. The original starter script is kept unchanged in `legacy_starter/` for reference.

## Initial data sources

- Hydro One stock listing: https://money.tmx.com/en/quote/H
- Fortis investor resources: https://fortisinc.com/investors/investor-resources
- iShares XIC fund: https://www.blackrock.com/ca/investors/en/products/239837/ishares-core-s-p-tsx-capped-composite-index-etf
- Bank of Canada T-bill yields, daily 3-month series, Valet ID `TB.CDN.90D.MID` (legacy reference V39065; Valet returns 404 for `V39065`): https://www.bankofcanada.ca/rates/interest-rates/t-bill-yields/selected-treasury-bill-yields-10-year-lookup/
- Bank of Canada no-key API documentation: https://www.bankofcanada.ca/valet-api-how-to/
- Market-price data in code: Yahoo via `quantmod` (secondary convenience source; validate independently)

## Public publishing sequence

**Module 01:** Do utilities behave defensively? Historical CAPM, risk and uncertainty. (This starter)

**Module 02:** Does higher AI-related grid investment translate to shareholder value? Annual reports; regulated return, capex, debt and rate-base model; sensitivity analysis.

**Module 03:** Can LLMs reliably extract relevant disclosures? Prompt, source reference, ground-truth table, accuracy and error analysis.

**Module 04:** Open dashboard and periodic updates, incorporating expert review and model corrections.

## Academic integrity

Use course concepts to learn and inform *independent, original* work. Do not copy or publicly distribute instructor SAS materials or restricted exam solutions. The ECON 4140 Fall 2026 outline prohibits generative AI in assessed work. **Do not submit this independent AI-assisted project as course assessment.**

## Publication checklist

Before posting findings: check source data and dividend adjustments, verify observation dates, inspect missing data, stress-test model selection, report uncertainty and limitations, and clearly distinguish historical correlations from forward-looking valuation assumptions.
