# External data checks — 2026-11-07

Snapshot checked: `data/raw/2026-11-05/` (Yahoo Finance via quantmod, retrieved 2026-11-06).
Checks performed with AI assistance (Claude) using a web browser; the user should spot-check at least one item.

## 1. Closing prices (tests/manual_price_checks.csv)

| Ticker | Source | Result |
|---|---|---|
| H.TO | Hydro One IR stock-information page, third-party quote widget, "Unadjusted" view | 3/3 closes match (24.91, 38.37, 57.60); daily % changes match computed returns |
| FTS.TO, XIC.TO | TMX Money price history | **Not checked.** Page did not load on 2026-11-07 even when signed in (requests returned HTTP 503). Fortis IR has no price lookup; Stooq is bot-gated. Retry later. |

## 2. Dividend / distribution adjustments (Yahoo adjusted ÷ close)

Method: on each date where the ratio `adjusted / close` changes, the implied cash amount is `close_{t-1} × (1 − ratio_{t-1} / ratio_t)`.

**Fortis (FTS.TO)** — 27 adjustment events, 2020-02-14 to 2026-08-19, no splits.
- Compared with the Fortis "Common Share Dividend" table (https://www.fortisinc.com/investors/share-information, viewed 2026-11-07): all 8 quarterly amounts for 2024–2025 match exactly ($0.59 ×3, $0.615 ×4, $0.64).
- Annual sums of implied dividends by ex-date year vs Fortis "dividend paid per common share": 2020 1.939 vs $1.94; 2021 2.050 vs $2.05; 2022 2.170 vs $2.17; 2023 2.285 vs $2.29; 2024 2.385 vs $2.39; 2025 2.485 vs $2.49 — consistent to rounding.
- Dates: several Yahoo adjustment dates are one trading day after the Fortis "ex-dividend" column and equal its record date (e.g. 2024-08-20, 2024-11-18, 2025-08-19, 2025-11-17). Since Canada's move to T+1 settlement (May 2024) the ex-date normally equals the record date, so this is likely a labelling convention. Effect is limited to moving one dividend between adjacent daily returns.
- **Result: PASS.**

**XIC (XIC.TO)** — 27 cash-distribution adjustments plus one Yahoo "split" of 1.013171 on 2021-12-30.
- Recent cash distributions match the iShares distribution history (https://www.blackrock.com/ca/investors/en/products/239837/, viewed 2026-11-07), e.g. 2025-12-30 $0.281 and 2026-03-26 $0.272.
- iShares reports 2021 total distributions for tax purposes of $1.19517 per unit, well above the ~$0.80 of regular quarterly cash distributions — i.e. a reinvested (non-cash) year-end distribution. Yahoo encodes this as a 1.013171 "split".
- Cross-check against the S&P/TSX Composite price index (^GSPTSE): over 1,718 days the XIC adjusted return differs from the index return by more than 0.75 pp on only two dates: 2020-03-19 (−0.77 pp, crash-period close timing) and **2021-12-30 (−1.20 pp)**. On 2021-12-30 the index fell 0.235% while the XIC adjusted return is −1.436%, and H and FTS were flat.
- **Result: ISSUE FOUND → CORRECTED (v0.1.2).** Yahoo's record also shows a regular $0.206 cash distribution on 2021-12-30. A clean XIC adjusted return should therefore be close to the index price move plus the cash yield: −0.235% + 0.206/34.559 (0.596%) ≈ **+0.361%**, versus −1.436% in the Yahoo data — a distortion of about −1.8 pp (the −1.2 pp above compares with the index price move only, without adding back the cash distribution).
- Correction C001 (`data/corrections.csv`) replaces that single return with the rebuilt value; the uncorrected series is kept as `Market_XIC_uncorrected`. Remaining approximation: XIC's own close-to-close tracking difference vs the index on that day (typically a few basis points) is ignored.
- Impact (unvalidated outputs): beta +0.0004/+0.0005 (Hydro One 0.4474 → 0.4478; Fortis 0.5654 → 0.5659) — immaterial. XIC sample total return 149.8% → 154.4%; annualized 14.3% → 14.6%; Sharpe 0.726 → 0.741; max drawdown unchanged.

## Status

- CAPM / beta inputs: acceptable for G2 subject to the user's spot-check; Fortis and XIC closing prices still unchecked.
- Performance table: XIC 2021-12-30 corrected (C001); uncorrected figures reported alongside.
