# Data notes

The first R script retrieves historical data at runtime. No market prices or statistical estimates are bundled. Yahoo Finance access and adjusted-price conventions may change.

For a publicly archived study, save source date, retrieval timestamp, original data file and provenance metadata, and independently verify security prices with issuer/exchange records. Review source licensing before redistributing raw vendor data.

Government series used: Bank of Canada Valet `TB.CDN.90D.MID` (legacy reference V39065), daily 3-month T-bill mid-market yields, percent per annum. See `docs/methodology.md` for timing and day-count conventions.

`raw/<as_of>/` holds the frozen snapshot used for each study version plus `manifest.csv`. Raw vendor price files are excluded from git (`.gitignore`) until redistribution terms are confirmed. `processed/` holds derived, aligned datasets.
