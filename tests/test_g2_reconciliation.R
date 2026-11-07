# G2 reconciliation: automated checks that recompute key numbers independently
# from the raw snapshot, rather than re-using R/01_market_risk.R code.
# Run from project root AFTER R/01_market_risk.R:  Rscript tests/test_g2_reconciliation.R
# Writes outputs/g2_automated_checks.csv and (once) tests/manual_price_checks.csv.
# Passing these checks is necessary, not sufficient: the manual external price checks
# in tests/manual_price_checks.csv must also be completed by a human.

as_of   <- as.Date("2026-11-05")
raw_dir <- file.path("data", "raw", format(as_of))
tickers <- c(Hydro_One = "H.TO", Fortis = "FTS.TO", Market_XIC = "XIC.TO")
tol <- 1e-10

panel <- read.csv("data/processed/aligned_daily_returns.csv", stringsAsFactors = FALSE)
panel$date <- as.Date(panel$date); panel$rf_obs_date <- as.Date(panel$rf_obs_date)
capm  <- read.csv("outputs/capm_results.csv", stringsAsFactors = FALSE)
raw   <- lapply(tickers, function(t) {
  d <- read.csv(file.path(raw_dir, paste0(t, ".csv")), stringsAsFactors = FALSE)
  d$date <- as.Date(d$date); d
})
rf_raw <- read.csv(file.path(raw_dir, "TB.CDN.90D.MID.csv"), stringsAsFactors = FALSE)
rf_raw$date <- as.Date(rf_raw$date)

results <- data.frame(check = character(), pass = logical(), detail = character())
check <- function(name, ok, detail = "") {
  results[nrow(results) + 1, ] <<- list(name, isTRUE(ok), detail)
}

# 1. Panel integrity
check("dates strictly increasing", all(diff(panel$date) > 0))
check("no missing values", !anyNA(panel))
check("last date equals as_of", max(panel$date) == as_of, format(max(panel$date)))
check("first return date after 2020-01-01", min(panel$date) > as.Date("2020-01-01"),
      format(min(panel$date)))
check("panel dates present in every raw price file",
      all(sapply(raw, function(d) all(panel$date %in% d$date))))

# 2. Independent return recomputation on first, middle and last panel dates
pick <- panel$date[c(1, ceiling(nrow(panel) / 2), nrow(panel))]
for (nm in names(tickers)) for (dt in as.list(pick)) {
  d <- raw[[nm]]; i <- match(dt, d$date)
  prev_panel_date <- if (match(dt, panel$date) > 1) panel$date[match(dt, panel$date) - 1] else d$date[i - 1]
  j <- match(prev_panel_date, d$date)
  r <- d$adjusted[i] / d$adjusted[j] - 1
  got <- panel[[nm]][panel$date == dt]
  check(sprintf("return %s %s recomputed", nm, format(dt)), abs(r - got) < tol,
        sprintf("raw %.10f vs panel %.10f (P_t=%.6f, P_t-1=%.6f on %s)",
                r, got, d$adjusted[i], d$adjusted[j], format(d$date[j])))
}

# 2b. Documented corrections: panel holds the recomputed value; the uncorrected
#     column still equals the raw vendor return on that date.
corr <- read.csv("data/corrections.csv", stringsAsFactors = FALSE); corr$date <- as.Date(corr$date)
for (i in seq_len(nrow(corr))) {
  v <- corr$index_close[i] / corr$index_close_prev[i] - 1 + corr$cash_distribution[i] / corr$prev_close[i]
  k <- panel$date == corr$date[i]
  check(sprintf("correction %s applied (%s %s)", corr$correction_id[i], corr$series[i], format(corr$date[i])),
        abs(panel[[corr$series[i]]][k] - v) < tol, sprintf("%.6f", v))
  d <- raw[[corr$series[i]]]; j <- match(corr$date[i], d$date)
  check(sprintf("correction %s uncorrected column = raw vendor return", corr$correction_id[i]),
        abs(panel$Market_XIC_uncorrected[k] - (d$adjusted[j] / d$adjusted[j - 1] - 1)) < tol)
}
check("no other XIC dates altered", sum(panel$Market_XIC != panel$Market_XIC_uncorrected) == nrow(corr))

# 3. Risk-free: no look-ahead, units, conversion
check("rf observation strictly before return date (prior timing)", all(panel$rf_obs_date < panel$date))
check("rf yield equals raw BoC value on its observation date",
      all(abs(panel$rf_yield_pct - rf_raw$yield_pct[match(panel$rf_obs_date, rf_raw$date)]) < tol))
check("rf yield in percent units (0-20)", all(panel$rf_yield_pct >= 0 & panel$rf_yield_pct < 20),
      sprintf("range %.2f to %.2f", min(panel$rf_yield_pct), max(panel$rf_yield_pct)))
check("rf daily = yield/100 * gap/365", all(abs(panel$rf_daily - panel$rf_yield_pct / 100 * panel$gap_days / 365) < 1e-15))
check("gap_days matches calendar gap between panel dates",
      all(panel$gap_days[-1] == as.numeric(diff(panel$date))))

# 4. Beta and alpha by two independent routes
for (s in c("Hydro_One", "Fortis")) {
  y <- panel[[s]] - panel$rf_daily; x <- panel$Market_XIC - panel$rf_daily
  X <- cbind(1, x); b_ne <- solve(crossprod(X), crossprod(X, y))
  b_cv <- cov(y, x) / var(x)
  reported <- capm$beta[capm$company == s]
  check(sprintf("%s beta: normal equations = reported", s), abs(b_ne[2] - reported) < tol,
        sprintf("%.12f vs %.12f", b_ne[2], reported))
  check(sprintf("%s beta: cov/var = reported", s), abs(b_cv - reported) < tol,
        sprintf("%.12f", b_cv))
  check(sprintf("%s alpha (bps/day) = reported", s),
        abs(b_ne[1] * 1e4 - capm$alpha_daily_bps[capm$company == s]) < 1e-6)
  e <- y - X %*% b_ne; n <- length(y)
  se <- sqrt(sum(e^2) / (n - 2) / sum((x - mean(x))^2))
  check(sprintf("%s OLS beta SE recomputed", s), abs(se - capm$beta_se_ols[capm$company == s]) < 1e-12)
  ci <- b_ne[2] + c(-1, 1) * qt(0.975, n - 2) * se
  check(sprintf("%s OLS 95%% CI recomputed", s),
        all(abs(ci - unlist(capm[capm$company == s, c("beta_low95_ols", "beta_high95_ols")])) < 1e-12))
}

write.csv(results, "outputs/g2_automated_checks.csv", row.names = FALSE)

# 5. Manual external price-check template (filled in by a person, not by code)
manual_file <- "tests/manual_price_checks.csv"
if (!file.exists(manual_file)) {
  tmpl <- do.call(rbind, lapply(names(tickers), function(nm) do.call(rbind, lapply(as.list(pick), function(dt) {
    d <- raw[[nm]]; i <- match(dt, d$date)
    data.frame(ticker = tickers[[nm]], date = format(dt), yahoo_close = d$close[i],
               yahoo_adjusted = d$adjusted[i], computed_simple_return = panel[[nm]][panel$date == dt],
               external_source = "", external_close = "", dividends_or_distributions_checked = "",
               matches = "", checked_by = "", checked_on = "")
  }))))
  write.csv(tmpl, manual_file, row.names = FALSE)
}

print(results, right = FALSE, row.names = FALSE)
cat(sprintf("\n%d of %d automated checks passed.\n", sum(results$pass), nrow(results)))
if (!all(results$pass)) quit(status = 1)
