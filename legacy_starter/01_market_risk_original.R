# WHO PAYS FOR CANADA'S AI BOOM?
# Module 01: Canadian utility investment risk and market exposure
# Prepared as an independent research starter, 2026-11-06
# Educational research only. No investment recommendation.
# Data downloaded only when you run this script with internet access.

required <- c("quantmod", "xts", "jsonlite", "zoo", "ggplot2")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop("Install these R packages first: install.packages(c(",
       paste(sprintf('"%s"', missing), collapse = ", "), "))")
}

start_date <- as.Date("2020-01-01")
# Freeze the initial study at the most recent completed date before launch.
# Update after each publication to document a new as-of date.
as_of <- as.Date("2026-11-05")
trading_days_per_year <- 252
rolling_window <- 126
stock_symbols <- c(Hydro_One = "H.TO", Fortis = "FTS.TO", Market_XIC = "XIC.TO")

if (!dir.exists("outputs")) dir.create("outputs", recursive = TRUE)

get_adjusted <- function(name, ticker) {
  dat <- tryCatch(
    quantmod::getSymbols(ticker, src = "yahoo", from = start_date,
                         to = as_of + 1, auto.assign = FALSE),
    error = function(e) stop(sprintf("Unable to download %s (%s): %s",
                                     name, ticker, conditionMessage(e)))
  )
  adjusted <- quantmod::Ad(dat)
  colnames(adjusted) <- name
  adjusted
}

message("Downloading adjusted historical prices: Hydro One, Fortis and XIC")
price_series <- Map(get_adjusted, names(stock_symbols), unname(stock_symbols))
prices <- do.call(merge, c(price_series, list(all = FALSE)))
prices <- stats::na.omit(prices)
if (NROW(prices) <= rolling_window + 5) {
  stop("Not enough common adjusted-price observations for the analysis")
}
# Adjusted prices aim to account for corporate actions and cash distributions.
# Verify adjusted-price methodology with the data provider before publication.
simple <- stats::na.omit(prices / stats::lag(prices, k = 1) - 1)

# Canadian three-month secondary-market T-bill yield, daily percent per annum.
# Bank of Canada series: V39065; do not substitute an arbitrary zero risk-free rate.
base_url <- "https://www.bankofcanada.ca/valet/observations/V39065/json"
api_url <- sprintf("%s?start_date=%s&end_date=%s", base_url,
                   as.character(start_date), as.character(as_of))
message("Downloading daily Canadian T-bill yields from the Bank of Canada")
boc <- tryCatch(jsonlite::fromJSON(api_url, simplifyVector = FALSE),
                error = function(e) stop("Unable to get Bank of Canada data: ", conditionMessage(e)))
if (is.null(boc$observations) || !length(boc$observations)) {
  stop("The Bank of Canada API did not return observations")
}
rate_dates <- as.Date(vapply(boc$observations, function(x) x$d, character(1)))
yields_pct <- vapply(boc$observations, function(x) {
  if (is.null(x$V39065) || is.null(x$V39065$v)) return(NA_real_)
  suppressWarnings(as.numeric(x$V39065$v))
}, numeric(1))
keep <- !is.na(rate_dates) & !is.na(yields_pct)
if (sum(keep) < 20) stop("Insufficient usable three-month Treasury bill observations")

# Approximation: annualized T-bill yield converted to an effective daily rate.
# Quoted bill yields may use particular market day-count conventions: disclose this.
rf_daily <- (1 + yields_pct[keep] / 100)^(1 / trading_days_per_year) - 1
rf_xts <- xts::xts(rf_daily, order.by = rate_dates[keep])
colnames(rf_xts) <- "rf_daily"

# Use the latest AVAILABLE historical observation at each trading date.
# Never back-fill rates using future information.
joined <- merge(simple, rf_xts, all = TRUE)
joined[, "rf_daily"] <- zoo::na.locf(joined[, "rf_daily"], na.rm = FALSE)
joined <- joined[zoo::index(simple)]
panel <- stats::na.omit(joined)
if (NROW(panel) < rolling_window + 5) stop("Not enough dates with prices and past risk-free rates")

sample <- data.frame(
  date = as.Date(zoo::index(panel)),
  Hydro_One = as.numeric(panel[, "Hydro_One"]),
  Fortis = as.numeric(panel[, "Fortis"]),
  Market_XIC = as.numeric(panel[, "Market_XIC"]),
  rf_daily = as.numeric(panel[, "rf_daily"])
)

capm_model <- function(stock_return, benchmark_return, rf) {
  regdata <- data.frame(stock_excess = stock_return - rf,
                        market_excess = benchmark_return - rf)
  fit <- stats::lm(stock_excess ~ market_excess, data = regdata)
  ct <- summary(fit)$coefficients
  ci <- stats::confint(fit, level = 0.95)
  beta <- unname(stats::coef(fit)["market_excess"])
  se <- ct["market_excess", "Std. Error"]
  p_beta_equals_one <- 2 * stats::pt(-abs((beta - 1) / se), df = fit$df.residual)
  c(alpha_daily_bps = unname(stats::coef(fit)["(Intercept)"]) * 10000,
    beta = beta, beta_low_95 = ci["market_excess", 1],
    beta_high_95 = ci["market_excess", 2],
    beta_p_0 = ct["market_excess", "Pr(>|t|)"],
    beta_p_1 = p_beta_equals_one,
    r_squared = summary(fit)$r.squared)
}

performance_metrics <- function(r, rf) {
  wealth <- cumprod(1 + r)
  peak <- cummax(c(1, wealth))[-1]
  c(annualized_historical_volatility = stats::sd(r) * sqrt(trading_days_per_year),
    historical_sharpe = mean(r - rf) / stats::sd(r) * sqrt(trading_days_per_year),
    total_sample_return = tail(wealth, 1) - 1,
    max_historical_drawdown = min(wealth / peak - 1))
}

names_to_analyze <- c("Hydro_One", "Fortis")
capm_results <- do.call(rbind, lapply(names_to_analyze, function(nm) {
  c(company = nm,
    capm_model(sample[[nm]], sample$Market_XIC, sample$rf_daily))
}))
capm_results <- as.data.frame(capm_results, stringsAsFactors = FALSE)
for (v in setdiff(names(capm_results), "company")) capm_results[[v]] <- as.numeric(capm_results[[v]])

performance <- do.call(rbind, lapply(c(names_to_analyze, "Market_XIC"), function(nm) {
  c(company = nm, performance_metrics(sample[[nm]], sample$rf_daily))
}))
performance <- as.data.frame(performance, stringsAsFactors = FALSE)
for (v in setdiff(names(performance), "company")) performance[[v]] <- as.numeric(performance[[v]])

rolling_betas <- function(r, m, rf, width = rolling_window) {
  n <- length(r)
  out <- rep(NA_real_, n)
  if (n < width) return(out)
  for (i in seq.int(width, n)) {
    ix <- (i - width + 1):i
    er <- r[ix] - rf[ix]
    em <- m[ix] - rf[ix]
    out[i] <- if (stats::var(em) > 0) stats::cov(er, em) / stats::var(em) else NA_real_
  }
  out
}

plot_data <- rbind(
  data.frame(date = sample$date, company = "Hydro One",
             beta = rolling_betas(sample$Hydro_One, sample$Market_XIC, sample$rf_daily)),
  data.frame(date = sample$date, company = "Fortis",
             beta = rolling_betas(sample$Fortis, sample$Market_XIC, sample$rf_daily))
)

p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = date, y = beta, group = company, linetype = company)) +
  ggplot2::geom_hline(yintercept = 1, color = "grey60", linewidth = 0.5) +
  ggplot2::geom_line(linewidth = 0.65, na.rm = TRUE) +
  ggplot2::labs(title = "Rolling 126-trading-day market beta",
                subtitle = "Canadian utility stocks relative to XIC (excess daily returns)",
                x = "Date", y = "Estimated beta", linetype = "Company",
                caption = "Historical estimation, not a forecast or causal estimate of AI exposure") +
  ggplot2::theme_minimal(base_size = 12)

# Chapter 4 of ECON 4140: fit simple AR(1) to stock log returns.
# The test checks autocorrelation through lag 10; it cannot establish tradable predictability.
ar1_checks <- do.call(rbind, lapply(names_to_analyze, function(nm) {
  y <- log1p(sample[[nm]])
  model <- stats::lm(y[-1] ~ y[-length(y)])
  ljung <- stats::Box.test(stats::residuals(model), lag = 10, type = "Ljung-Box", fitdf = 1)
  data.frame(company = nm, ar1_phi = unname(stats::coef(model)[2]),
             ar1_phi_pvalue = summary(model)$coefficients[2, 4],
             ljung_box_lag10_pvalue = ljung$p.value)
}))

utils::write.csv(capm_results, "outputs/capm_results.csv", row.names = FALSE)
utils::write.csv(performance, "outputs/performance_results.csv", row.names = FALSE)
utils::write.csv(ar1_checks, "outputs/ar1_checks.csv", row.names = FALSE)
utils::write.csv(sample, "outputs/aligned_daily_returns.csv", row.names = FALSE)
ggplot2::ggsave("outputs/rolling_beta.png", p, width = 10, height = 5.7, dpi = 180)

cat("\nDATA PERIOD:", as.character(min(sample$date)), "to", as.character(max(sample$date)),
    "; aligned trading days:", nrow(sample), "\n")
cat("\nCAPM coefficients (excess returns):\n")
print(capm_results, row.names = FALSE)
cat("\nHistorical returns and risk:\n")
print(performance, row.names = FALSE)
cat("\nAR(1) exploratory diagnostics:\n")
print(ar1_checks, row.names = FALSE)
cat("\nFiles saved in ./outputs/. Interpret results using research_design.md.\n")
