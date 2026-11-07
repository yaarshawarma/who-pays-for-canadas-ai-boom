# WHO PAYS FOR CANADA'S AI BOOM?
# Module 01: Canadian utility market risk vs XIC (historical, descriptive only)
# Version 0.1.3 (2026-11-07). Educational research only. Not investment advice.
#
# Run from the project root:   Rscript R/01_market_risk.R
# Re-download raw data:        REFRESH_DATA=1 Rscript R/01_market_risk.R
#
# Changes vs. legacy_starter/01_market_risk_original.R (see docs/methodology.md):
#  1. Bank of Canada Valet series ID: TB.CDN.90D.MID (V39065 returns HTTP 404 on Valet).
#  2. Raw-data snapshot + manifest in data/raw/<as_of>/; later runs reuse the snapshot.
#  3. Risk-free timing option: "prior" (strictly earlier BoC observation, default) or "same".
#  4. Day-count option: "act365" (money-market simple accrual over calendar days since
#     the previous close, default) or "cmp252" (legacy (1+y)^(1/252)-1).
#  5. Newey-West HAC standard errors alongside OLS; Durbin-Watson test.
#  6. Sharpe uses sd of EXCESS returns; geometric annualized return added.
#  7. Rolling beta at 126 and 252 days; chart carries sample/source/as-of disclosures.
#  8. Coverage report, as-of assertion, sensitivity grid, run_info.txt.
#  9. Documented vendor-data corrections from data/corrections.csv (v0.1.2).
# All outputs carry validation_status = "UNVALIDATED" until tests/ and manual checks pass.

if (!file.exists("R/01_market_risk.R")) stop("Run this script from the project root folder.")

suppressPackageStartupMessages({
  library(quantmod); library(xts); library(zoo); library(jsonlite)
  library(ggplot2); library(sandwich); library(lmtest)
})

# ---- Configuration ---------------------------------------------------------
cfg <- list(
  start_date    = as.Date("2020-01-01"),
  as_of         = as.Date("2026-11-05"),   # last completed session in the frozen sample
  days_per_year = 252,
  rf_series     = "TB.CDN.90D.MID",        # Valet ID; legacy reference V39065
  rf_timing     = "prior",                 # "prior" or "same"
  rf_daycount   = "act365",                # "act365" or "cmp252"
  windows       = c(126, 252),
  refresh       = identical(Sys.getenv("REFRESH_DATA"), "1"),
  apply_corrections = TRUE                 # data/corrections.csv (documented vendor-data fixes)
)
tickers <- c(Hydro_One = "H.TO", Fortis = "FTS.TO", Market_XIC = "XIC.TO")
stocks  <- c("Hydro_One", "Fortis")
STATUS  <- "UNVALIDATED"

raw_dir <- file.path("data", "raw", format(cfg$as_of))
for (d in c(raw_dir, "data/processed", "outputs")) dir.create(d, recursive = TRUE, showWarnings = FALSE)
manifest_path <- file.path(raw_dir, "manifest.csv")

record_manifest <- function(row) {
  m <- if (file.exists(manifest_path)) read.csv(manifest_path, stringsAsFactors = FALSE) else NULL
  if (!is.null(m)) m <- m[m$data_id != row$data_id, , drop = FALSE]
  write.csv(rbind(m, row), manifest_path, row.names = FALSE)
}

# ---- Raw data: prices (snapshot) -------------------------------------------
fetch_prices <- function(tk) {
  f <- file.path(raw_dir, paste0(tk, ".csv"))
  if (!file.exists(f) || cfg$refresh) {
    message("Downloading ", tk, " from Yahoo Finance (quantmod)")
    x <- getSymbols(tk, src = "yahoo", from = cfg$start_date, to = cfg$as_of + 1,
                    auto.assign = FALSE)
    df <- data.frame(date = as.Date(index(x)), coredata(x))
    names(df) <- c("date", "open", "high", "low", "close", "volume", "adjusted")
    write.csv(df, f, row.names = FALSE)
    record_manifest(data.frame(
      data_id = tk, source = "Yahoo Finance via quantmod::getSymbols", security = tk,
      period_start = format(min(df$date)), period_end = format(max(df$date)),
      retrieved_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      source_url = paste0("https://finance.yahoo.com/quote/", tk, "/history"),
      currency = "CAD", unit = "price per share/unit",
      adjustment_basis = "adjusted = Yahoo split+distribution adjusted close (unverified)",
      rows = nrow(df), file = f, md5 = unname(tools::md5sum(f)),
      status = "convenience source; verify", stringsAsFactors = FALSE))
  }
  df <- read.csv(f, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  df
}
px_raw <- lapply(tickers, fetch_prices)
names(px_raw) <- names(tickers)

# ---- Raw data: Bank of Canada 3-month T-bill (snapshot) ---------------------
rf_file <- file.path(raw_dir, paste0(cfg$rf_series, ".csv"))
if (!file.exists(rf_file) || cfg$refresh) {
  url <- sprintf("https://www.bankofcanada.ca/valet/observations/%s/json?start_date=%s&end_date=%s",
                 cfg$rf_series, cfg$start_date - 14, cfg$as_of)
  message("Downloading ", cfg$rf_series, " from Bank of Canada Valet")
  j <- fromJSON(url)
  obs <- j$observations
  if (is.null(obs) || !nrow(obs)) stop("Bank of Canada Valet returned no observations")
  rf_df <- data.frame(date = as.Date(obs$d),
                      yield_pct = suppressWarnings(as.numeric(obs[[cfg$rf_series]]$v)))
  write.csv(rf_df, rf_file, row.names = FALSE)
  record_manifest(data.frame(
    data_id = cfg$rf_series, source = "Bank of Canada Valet API", security = "GoC 3-month T-bill",
    period_start = format(min(rf_df$date)), period_end = format(max(rf_df$date)),
    retrieved_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), source_url = url,
    currency = "CAD", unit = "percent per annum (mid-market, business-day average)",
    adjustment_basis = "none", rows = nrow(rf_df), file = rf_file,
    md5 = unname(tools::md5sum(rf_file)), status = "primary official source",
    stringsAsFactors = FALSE))
}
rf_df <- read.csv(rf_file, stringsAsFactors = FALSE)
rf_df$date <- as.Date(rf_df$date)
rf_na <- sum(is.na(rf_df$yield_pct))
rf_df <- rf_df[!is.na(rf_df$yield_pct), ]
if (any(rf_df$yield_pct < -1 | rf_df$yield_pct > 20)) stop("T-bill yield outside plausible percent range")

# ---- Coverage report (no forward-filling of prices) -------------------------
all_dates <- sort(unique(do.call(c, lapply(px_raw, `[[`, "date"))))
coverage <- do.call(rbind, lapply(names(px_raw), function(nm) {
  d <- px_raw[[nm]]
  data.frame(series = nm, ticker = tickers[[nm]], rows = nrow(d),
             first_date = format(min(d$date)), last_date = format(max(d$date)),
             na_adjusted = sum(is.na(d$adjusted)), zero_volume_days = sum(d$volume == 0, na.rm = TRUE),
             dates_missing_vs_union = length(setdiff(all_dates, d$date)))
}))
coverage <- rbind(coverage, data.frame(
  series = "risk_free", ticker = cfg$rf_series, rows = nrow(rf_df),
  first_date = format(min(rf_df$date)), last_date = format(max(rf_df$date)),
  na_adjusted = rf_na, zero_volume_days = NA, dates_missing_vs_union = NA))
for (nm in names(px_raw)) {
  if (max(px_raw[[nm]]$date) != cfg$as_of)
    stop(sprintf("%s last date %s != as_of %s", nm, max(px_raw[[nm]]$date), cfg$as_of))
}

# Inner join on dates present in every series with a non-missing adjusted price.
adj_list <- lapply(names(px_raw), function(nm) {
  d <- px_raw[[nm]][!is.na(px_raw[[nm]]$adjusted), ]
  x <- xts(d$adjusted, order.by = d$date); colnames(x) <- nm; x
})
prices <- do.call(merge, c(adj_list, list(all = FALSE)))
dropped <- setdiff(all_dates, index(prices))
coverage$dates_dropped_by_inner_join <- length(dropped)

# ---- Returns and risk-free alignment ----------------------------------------
ret <- (prices / lag.xts(prices, k = 1) - 1)[-1]   # simple returns, t-1 -> t
gap_days <- as.numeric(diff(index(prices)))         # calendar days since previous close

align_rf <- function(dates, timing) {
  shift <- if (timing == "prior") 1 else 0          # prior: rf date strictly before t
  i <- findInterval(as.numeric(dates) - shift, as.numeric(rf_df$date))
  if (any(i == 0)) stop("No earlier risk-free observation for some return dates")
  data.frame(rf_obs_date = rf_df$date[i], rf_yield_pct = rf_df$yield_pct[i])
}
to_daily <- function(y_pct, gap, daycount) {
  if (daycount == "act365") y_pct / 100 * gap / 365
  else (1 + y_pct / 100)^(1 / cfg$days_per_year) - 1
}
rf_for <- function(timing, daycount) {
  a <- align_rf(index(ret), timing)
  to_daily(a$rf_yield_pct, gap_days, daycount)
}

rf_main <- align_rf(index(ret), cfg$rf_timing)
panel <- data.frame(
  date = as.Date(index(ret)),
  Hydro_One = as.numeric(ret$Hydro_One), Fortis = as.numeric(ret$Fortis),
  Market_XIC = as.numeric(ret$Market_XIC), gap_days = gap_days,
  rf_obs_date = rf_main$rf_obs_date, rf_yield_pct = rf_main$rf_yield_pct,
  rf_daily = to_daily(rf_main$rf_yield_pct, gap_days, cfg$rf_daycount)
)

# ---- Documented data corrections (data/corrections.csv) ---------------------
# Each correction replaces one vendor return with a value rebuilt from stated
# inputs. The uncorrected series is kept for sensitivity analysis.
panel$Market_XIC_uncorrected <- panel$Market_XIC
corr <- read.csv("data/corrections.csv", stringsAsFactors = FALSE)
corr$date <- as.Date(corr$date)
corr$corrected_return <- (corr$close + corr$cash_distribution) / corr$close_prev - 1
corr$original_return <- NA_real_
if (cfg$apply_corrections) {
  for (i in seq_len(nrow(corr))) {
    k <- which(panel$date == corr$date[i])
    if (length(k) != 1) stop("Correction ", corr$correction_id[i], " date not in panel")
    corr$original_return[i] <- panel[[corr$series[i]]][k]
    panel[[corr$series[i]]][k] <- corr$corrected_return[i]
  }
}
corr$applied <- cfg$apply_corrections
write.csv(corr[, c("correction_id", "series", "date", "original_return", "corrected_return",
                   "applied", "method", "status")],
          "outputs/corrections_applied.csv", row.names = FALSE)

if (anyNA(panel)) stop("Missing values in aligned panel")
write.csv(panel, "data/processed/aligned_daily_returns.csv", row.names = FALSE)

# ---- CAPM ------------------------------------------------------------------
capm <- function(y, x) {
  fit <- lm(y ~ x)
  ct  <- coef(summary(fit)); ci <- confint(fit, level = 0.95)
  hac <- coeftest(fit, vcov. = NeweyWest(fit, prewhite = FALSE, adjust = TRUE))
  b <- coef(fit)[["x"]]; df <- fit$df.residual; tq <- qt(0.975, df)
  se <- ct["x", 2]; se_h <- hac["x", 2]
  se_hc1 <- sqrt(vcovHC(fit, type = "HC1")["x", "x"])   # heteroskedasticity-only
  dw <- dwtest(fit)
  c(n = nobs(fit),
    alpha_daily_bps = coef(fit)[[1]] * 1e4,
    alpha_annualized_approx_pct = coef(fit)[[1]] * cfg$days_per_year * 100,
    alpha_p_ols = ct[1, 4], alpha_p_hac = hac[1, 4],
    beta = b,
    beta_se_ols = se, beta_low95_ols = ci["x", 1], beta_high95_ols = ci["x", 2],
    beta_se_hc1 = se_hc1,
    beta_se_hac = se_h, beta_low95_hac = b - tq * se_h, beta_high95_hac = b + tq * se_h,
    p_beta_eq0_ols = ct["x", 4],
    p_beta_eq1_ols = 2 * pt(-abs((b - 1) / se), df),
    p_beta_eq1_hac = 2 * pt(-abs((b - 1) / se_h), df),
    r_squared = summary(fit)$r.squared,
    durbin_watson = unname(dw$statistic), dw_p = dw$p.value)
}
run_capm <- function(df, rf) {
  do.call(rbind, lapply(stocks, function(s) {
    data.frame(company = s, t(capm(df[[s]] - rf, df$Market_XIC - rf)))
  }))
}

capm_results <- run_capm(panel, panel$rf_daily)
capm_results <- cbind(capm_results, sample_start = format(min(panel$date)),
                      sample_end = format(max(panel$date)), benchmark = "XIC.TO (proxy)",
                      rf = paste(cfg$rf_series, cfg$rf_timing, cfg$rf_daycount),
                      validation_status = STATUS)

# Sensitivity grid: risk-free conventions (full sample) and subsamples (main rf).
sens <- list()
for (tm in c("prior", "same")) for (dc in c("act365", "cmp252")) {
  sens[[length(sens) + 1]] <- cbind(spec = paste0("full | rf ", tm, " ", dc),
                                    run_capm(panel, rf_for(tm, dc)))
}
subsamples <- list(
  "ex_March_2020" = !(panel$date >= as.Date("2020-03-01") & panel$date <= as.Date("2020-03-31")),
  "2020_to_2022"  = panel$date <= as.Date("2022-12-31"),
  "2023_to_asof"  = panel$date >= as.Date("2023-01-01"))
for (nm in names(subsamples)) {
  k <- subsamples[[nm]]
  sens[[length(sens) + 1]] <- cbind(spec = paste0(nm, " | rf main"),
                                    run_capm(panel[k, ], panel$rf_daily[k]))
}
uncorr <- panel; uncorr$Market_XIC <- uncorr$Market_XIC_uncorrected
sens[[length(sens) + 1]] <- cbind(spec = "full | rf main | NO data corrections",
                                  run_capm(uncorr, panel$rf_daily))
capm_sensitivity <- do.call(rbind, sens)
capm_sensitivity$validation_status <- STATUS

# ---- Performance -----------------------------------------------------------
years <- as.numeric(max(index(prices)) - min(index(prices))) / 365.25
perf <- function(r, rf) {
  ex <- r - rf; w <- cumprod(1 + r); pk <- cummax(c(1, w))[-1]
  c(total_return = tail(w, 1) - 1,
    annualized_return_geometric = tail(w, 1)^(1 / years) - 1,
    annualized_volatility = sd(r) * sqrt(cfg$days_per_year),
    sharpe_annualized = mean(ex) / sd(ex) * sqrt(cfg$days_per_year),
    max_drawdown = min(w / pk - 1))
}
performance <- do.call(rbind, lapply(c(stocks, "Market_XIC", "Market_XIC_uncorrected"), function(s) {
  data.frame(series = s, t(perf(panel[[s]], panel$rf_daily)))
}))
performance <- cbind(performance, first_price_date = format(min(index(prices))),
                     sample_end = format(max(panel$date)), years = round(years, 3),
                     return_basis = "adjusted close (total-return proxy)",
                     validation_status = STATUS)

# ---- Rolling beta (trailing windows; uses data up to and including t) -------
rolling_beta <- function(r, m, rf, width) {
  n <- length(r); out <- rep(NA_real_, n)
  if (n < width) return(out)
  for (i in seq.int(width, n)) {
    ix <- (i - width + 1):i
    em <- m[ix] - rf[ix]
    out[i] <- if (var(em) > 0) cov(r[ix] - rf[ix], em) / var(em) else NA_real_
  }
  out
}
roll <- do.call(rbind, lapply(cfg$windows, function(w) do.call(rbind, lapply(stocks, function(s) {
  data.frame(date = panel$date, company = s, window = w,
             beta = rolling_beta(panel[[s]], panel$Market_XIC, panel$rf_daily, w))
}))))
write.csv(roll, "outputs/rolling_beta.csv", row.names = FALSE)

roll_plot <- subset(roll, !is.na(beta))
roll_plot$company <- ifelse(roll_plot$company == "Hydro_One", "Hydro One (H.TO)", "Fortis (FTS.TO)")
roll_plot$window_label <- paste0(roll_plot$window, "-trading-day window")
p <- ggplot(roll_plot, aes(date, beta, colour = company)) +
  geom_hline(yintercept = 1, colour = "grey60", linewidth = 0.4) +
  geom_line(linewidth = 0.55) +
  facet_wrap(~ window_label, ncol = 1) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               limits = c(min(panel$date), max(panel$date))) +
  labs(title = "DRAFT - UNVALIDATED: rolling market beta vs XIC",
       subtitle = sprintf("Daily excess simple returns, %s to %s. As of %s.",
                          format(min(panel$date)), format(max(panel$date)), format(cfg$as_of)),
       x = NULL, y = "Estimated beta", colour = NULL,
       caption = paste0(
         "Prices: Yahoo Finance adjusted close via quantmod (split/distribution-adjusted; not yet verified). ",
         "Risk-free: Bank of Canada ", cfg$rf_series, ", prior-day observation, act/365.\n",
         "XIC is a Canadian equity-market proxy, not the full market. Historical estimate only: ",
         "not a forecast or a causal estimate of AI exposure. Not investment advice.")) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", plot.caption = element_text(hjust = 0, size = 7.5))
ggsave("outputs/rolling_beta.png", p, width = 10, height = 7, dpi = 180, bg = "white")

# ---- AR(1) on log gross returns (exploratory) -------------------------------
ar1_checks <- do.call(rbind, lapply(stocks, function(s) {
  y <- log1p(panel[[s]])
  m <- lm(y[-1] ~ y[-length(y)])
  lb <- Box.test(residuals(m), lag = 10, type = "Ljung-Box", fitdf = 1)
  lb2 <- Box.test(residuals(m)^2, lag = 10, type = "Ljung-Box")
  data.frame(company = s, ar1_phi = unname(coef(m)[2]),
             ar1_phi_p_ols = coef(summary(m))[2, 4],
             ar1_phi_p_hac = coeftest(m, vcov. = NeweyWest(m, prewhite = FALSE, adjust = TRUE))[2, 4],
             ljung_box_resid_lag10_p = lb$p.value,
             ljung_box_sq_resid_lag10_p = lb2$p.value,
             validation_status = STATUS)
}))

# ---- Write outputs ----------------------------------------------------------
write.csv(coverage, "outputs/coverage_report.csv", row.names = FALSE)
write.csv(capm_results, "outputs/capm_results.csv", row.names = FALSE)
write.csv(capm_sensitivity, "outputs/capm_sensitivity.csv", row.names = FALSE)
write.csv(performance, "outputs/performance_results.csv", row.names = FALSE)
write.csv(ar1_checks, "outputs/ar1_checks.csv", row.names = FALSE)

writeLines(c(
  paste("run_at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste("config:", paste(names(cfg), sapply(cfg, function(v) paste(format(v), collapse = ",")),
                         sep = "=", collapse = "; ")),
  paste("aligned_return_days:", nrow(panel), "| first:", min(panel$date), "| last:", max(panel$date)),
  paste("dates_dropped_by_inner_join:", length(dropped)),
  "", capture.output(sessionInfo())), "outputs/run_info.txt")

cat(sprintf("\nSample: %s to %s, %d aligned return days (%d dropped by inner join).\n",
            min(panel$date), max(panel$date), nrow(panel), length(dropped)))
cat("Outputs written to outputs/ and data/processed/. Status:", STATUS,
    "- run tests/test_g2_reconciliation.R next.\n")
