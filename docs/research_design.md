# Research design: version 0.1 (November 6, 2026)

## Audience and use case

**Primary audience:** Canadian individual investors trying to evaluate the AI-infrastructure investment theme without confusing exciting demand headlines with attractive stock valuation.

**Decision support:** not personalized buy/sell signals. The resource should help readers compare stock-market exposure, historical downside and financial-statement-based capital requirements; understand uncertainties; and ask more informed questions.

## Study questions

1. **Market exposure:** How do Hydro One and Fortis respond to changes in the broad Canadian equity market?
2. **Stability:** Does beta change materially over time, and how large are the uncertainty bands around whole-period estimates?
3. **Portfolio context:** How does historical volatility, drawdown and Sharpe ratio compare to XIC?
4. **Predictability:** Does a simple AR(1) model exhibit serial dependence, and do residuals pass a Ljung-Box diagnostic? This alone does not demonstrate exploitable predictability.
5. **Later fundamental extension:** What regulatory, capital expenditure, financing and earnings assumptions are needed for greater electricity demand to translate into shareholder value? What is priced in at different hypothetical required returns?
6. **Later public impact extension:** What disclosures would help investors and citizens evaluate those assumptions? Are any material cost-allocation policy uncertainties hidden?

## Initial sample and data treatment

- Study begins 2020-01-01 and cuts off at end of 2026-11-05, excluding partial trading on Nov 6.
- Use adjusted closing prices for H.TO, FTS.TO, XIC.TO, with identical complete dates.
- All securities are CAD-denominated, limiting direct FX confounding in market comparison.
- Compute arithmetic daily returns for CAPM and performance; log returns for AR(1).
- Proxy risk-free rate with Bank of Canada daily 3-month T-bill yield (Valet ID `TB.CDN.90D.MID`; legacy reference V39065). Main specification: use the latest observation dated strictly *before* each return date, converted with simple act/365 accrual over the calendar days since the previous close. Same-day timing and the (1+y)^(1/252)-1 convention are reported as sensitivities (see `docs/methodology.md`).
- Use XIC as a **Canadian equity market proxy**, not a literal complete CAPM market portfolio.
- Report sample period, data sources, missing-data handling, and whether total-return adjustments are consistently applied.

## Statistical specifications

### CAPM

`stock excess return_t = alpha + beta * XIC excess return_t + error_t`

The independent project follows core regression logic in ECON 4140 but is a fresh implementation in R and uses a new dataset. A nonzero realized alpha is not proof of skill, undervaluation or a future premium. Ordinary OLS confidence intervals are a first approximation; consider heteroskedasticity/serial-correlation-robust standard errors before a public research conclusion.

### Time series

`log return_t = intercept + phi * log return_(t-1) + error_t`

Run Ljung-Box on residuals. Test residual heteroskedasticity separately in a later module. In-sample diagnostics cannot establish out-of-sample forecasting accuracy. Avoid claims of return predictability without walk-forward tests.

### Financial statement valuation extension

Keep this separate from price-data regressions. Review primary issuer filings and utility regulator records. Model capex, rate-base growth, debt funding, financing costs and allowed return assumptions. Estimate cash flows or valuation ranges under clearly labelled downside/base/upside scenarios. The scope of utility regulation and AI-specific electricity demand must be independently documented; **do not assume AI data-centre demand directly causes Hydro One earnings growth**.

## AI usage and verification

For Module 03, LLM extraction is a hypothesis to test, not assumed competence:
- Each extracted amount must include filing title, reporting period, citation/page and unit.
- Build manual ground truth from primary financial filings.
- Score field-level accuracy, units errors, omissions and invented fields.
- Never let an LLM invent a line item or substitute values silently.
- Publish both model errors and successful cases.

## Suggested first LinkedIn research post structure

1. One specific headline finding based on real, independently verified regression outputs (insert only after running).
2. Plain English explanation of beta and what it does NOT mean.
3. One legible chart: rolling beta H/FTS vs XIC.
4. Source link and downloadable full methodology.
5. Invitation for corrections from energy-finance and investment-research professionals.

## A practical impact measure

Count qualified research use: downloads of reproducible notebook, constructive error reports, citations and actual feedback from investors and researchers. Page views and likes are reach, not proof of impact.
