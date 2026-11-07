# Module 01 methodology — v0.1.1 (draft, 2026-11-06)

Status: **UNVALIDATED.** These are the conventions implemented in `R/01_market_risk.R`. No result produced under them has passed the G2 reconciliation gate yet.

## Sample and data

| Item | Convention |
|---|---|
| Securities | H.TO (Hydro One), FTS.TO (Fortis), XIC.TO (iShares Core S&P/TSX Capped Composite ETF), all CAD |
| Benchmark | XIC is a Canadian equity-market **proxy**, not the CAPM market portfolio |
| Prices | Yahoo Finance adjusted close via `quantmod::getSymbols` (convenience source; split- and distribution-adjusted by Yahoo; to be verified against an independent source) |
| Window | Requested 2020-01-01 to 2026-11-05 (last completed session before 2026-11-06). The first return is dated on the second available trading day. |
| Alignment | Inner join of trading dates across the three securities. Prices are never forward-filled. Dropped dates are counted in `outputs/coverage_report.csv`. |
| Snapshot | Raw files are frozen in `data/raw/<as_of>/` with `manifest.csv` (retrieval time, URL, MD5). Re-download only with `REFRESH_DATA=1`. |

## Returns

- Simple return: `R_t = P_t / P_{t-1} - 1` on adjusted closes (CAPM, performance, rolling beta).
- Log gross return: `r_t = log(1 + R_t)` (AR(1) only).

## Risk-free rate

- Series: Bank of Canada Valet `TB.CDN.90D.MID` — 3-month Government of Canada T-bill, mid-market yield averaged over the business day, percent per annum. The legacy reference `V39065` appears in the series description, but Valet returns HTTP 404 for it as a series ID (checked 2026-11-06).
- **Timing (main):** for a return dated *t*, use the latest BoC observation dated strictly before *t*. Reason: the BoC value is an intraday average, so a same-day value is not cleanly "known" at the time of the close. Same-day timing is a sensitivity.
- **Day count (main):** `rf_t = y/100 × (calendar days since previous close) / 365`, i.e. simple money-market accrual. A Monday return accrues three days. Sensitivity: `(1 + y/100)^(1/252) − 1` per trading day (the original starter's convention).

## CAPM

`(R_i,t − rf_t) = α + β (R_XIC,t − rf_t) + ε_t`, estimated by OLS on daily data.

Reported for each stock: n, α (bps/day and ×252 approximate annualized %), β, OLS SE and 95% CI, Newey-West HAC SE and 95% CI (`sandwich::NeweyWest`, automatic bandwidth, no prewhitening, small-sample adjustment), p-values for β = 0 and β = 1, R², Durbin-Watson.

Inference note (observed in the v0.1.1 draft run, unvalidated): on the full sample the HC1 (White) β SE is roughly 2.3× the OLS SE and the Newey-West SE roughly 5–7× OLS, even though Durbin-Watson is near 2. Durbin-Watson only tests first-order residual autocorrelation; the Newey-West widening points to heteroskedasticity plus serial dependence in the regression score (volatility clustering, concentrated in March 2020). OLS, HC1 and HAC SEs are therefore all reported, and conclusions must not rely on OLS intervals alone.

Sensitivity (`outputs/capm_sensitivity.csv`): rf timing × day count on the full sample, and three subsamples under the main rf: excluding March 2020, 2020–2022, 2023–as-of. The subsample cut points are researcher choices, not data-driven.

## Performance

- Total return: `∏(1 + R_t) − 1`.
- Annualized return: `(1 + total)^(1/years) − 1`, with years = calendar days from first to last price date / 365.25.
- Annualized volatility: `sd(R_t) × √252`.
- Sharpe: `mean(R_t − rf_t) / sd(R_t − rf_t) × √252` (the original starter used `sd(R_t)` in the denominator).
- Maximum drawdown on the cumulative wealth index, starting from 1.

## Rolling beta

Trailing windows of 126 and 252 trading days ending at *t*: `cov(excess_i, excess_XIC) / var(excess_XIC)`. Only data up to *t* is used. No confidence bands yet (planned).

## AR(1) (exploratory)

`r_t = c + φ r_{t−1} + u_t` on log gross returns. Reports OLS and HAC p-values for φ, Ljung-Box (lag 10, fitdf = 1) on residuals, and Ljung-Box on squared residuals as a volatility-clustering flag. In-sample fit is not evidence of tradable predictability.

## Known limitations

Hindsight ticker selection; XIC proxy; Yahoo adjusted-price methodology unverified; March 2020 dominates extreme observations; daily non-normality and volatility clustering; a full-sample β is an average over changing regimes; none of this measures AI-related exposure or causation.

## Known data issues

- **XIC 2021-12-30 (open).** Yahoo encodes iShares' reinvested year-end 2021 distribution as a 1.013171 "split". The resulting XIC adjusted return on 2021-12-30 (−1.44%) is about 1.2 pp below the S&P/TSX Composite index move (−0.24%). Beta impact ≈ +0.0005 (immaterial); XIC total return understated by ≈4 pp. Treatment for the performance table not yet decided. Details: `tests/adjustment_checks.md`.
- Fortis adjustment dates sometimes fall on the record date rather than the listed ex-date (one trading day); amounts match Fortis's records.

## Change log

- v0.1.1 (2026-11-06): Valet series ID fix; data snapshot + manifest; prior-day/act365 risk-free; HAC SE and Durbin-Watson; Sharpe on excess returns; annualized return; 252-day rolling beta; sensitivity grid; coverage report; G2 automated tests.
- v0.1.0: original starter (`legacy_starter/01_market_risk_original.R`), not executable as delivered (Valet 404).
