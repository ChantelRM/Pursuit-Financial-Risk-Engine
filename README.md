# Financial Risk Analytics Engine

An automated financial risk analytics and collections communication pipeline
built in R for Google Colab. Ingests debtor and risk data, computes exposure
and risk tiers, drafts collection notifications, visualizes portfolio health,
predicts which flagged accounts are actually worth pursuing, and lets you
ask the data questions in plain English via the Claude API.

## Quick start

1. Open `financial_risk_analytics.ipynb` in Google Colab
2. **Runtime > Change runtime type > R**
3. Run cells top to bottom (Section 0 → Section 8)
4. Everything runs on simulated data by default — no setup required to see
   the whole pipeline work end to end

## Project structure

```
financial-risk-analytics-engine/
├── README.md                       <- you are here
├── PROJECT_PLAN.md                 <- 3-week issue breakdown for the hackathon board
├── financial_risk_analytics.ipynb  <- MAIN NOTEBOOK — run this
├── src/
│   ├── financial_risk_engine.R     <- standalone version of Sections 0-5
│   └── pursuit_prediction_model.R  <- standalone version of Section 6 (the ML layer)
├── data/
│   ├── raw/                        <- put your downloaded Kaggle CSVs here
│   └── processed/                  <- unified_ledger.csv gets written here
├── models/
│   └── payment_model.rds           <- trained model, generated on first run
└── outputs/
    ├── charts/                     <- the 3 PNG visualizations
    ├── notification_queue.csv      <- drafted email/SMS content
    └── pursuit_rankings.csv        <- ranked "worth pursuing" list
```

The `.R` files in `src/` are the same logic as the notebook, split into two
plain scripts — useful if a teammate wants to work outside Colab, or if you
want to `source()` them from another script instead of running a notebook.
The notebook is self-contained and doesn't depend on `src/` at all.

## What each notebook section does

| Section | What it does |
|---|---|
| 0 | Installs/loads packages |
| 1 | Schema contracts + validation (fails loudly on a bad column, not silently downstream) |
| 2 | Simulated data by default; flip `USE_REAL_DATA <- TRUE` once your Master Ledger / Risk Registry CSVs are in `data/raw/` |
| 3 | Merge, `Remaining_Balance`, `Net_Profit`, `Critical_Alert` flag, `Risk_Tier` |
| 4 | Email + SMS notification drafts for flagged accounts (drafts only — no send integration wired up; see note below) |
| 5 | 3 ggplot2 visualizations |
| 6 | **Pursuit prediction model** — trains a logistic regression on your 3 Kaggle datasets to predict repayment probability, evaluates it, scores your accounts, ranks who's worth pursuing |
| 7 | LLM chat layer — ask the data questions via the Claude API |
| 8 | Wrap-up / output file list |

## Your 3 Kaggle datasets

- `kingabzpro/bank-debt-data` — has a real recovered/not-recovered outcome; your cleanest label source
- `kotich/banking-collections-dataset-synthetic-data` — richer risk features (loan type, risk level, outstanding amount)
- `akrambelha/synthetic-banking-dataset-csv-sql-sqlite` — large (1.26M+ rows), likely relational; treated as optional enrichment, not required for the model to work

**Before trusting Section 6's output:** download the 3 CSVs into `data/raw/`,
then run the `inspect_dataset()` calls (commented out at the top of that
section) on each one and compare the printed columns against `CONFIG`.
Kaggle gates full column listings behind login, so `CONFIG` is a best-effort
starting map, not a confirmed schema — it's written to fail with a clear
error pointing at the specific mismatched column rather than silently
producing a wrong model.

## Model stats — where to find them

Once you run the "Train the model" and "Evaluate" cells, you'll get, inline
in the notebook output:
- `summary(payment_model)` — coefficients, significance, standard errors
- Accuracy and AUC on both the validation and test sets
- A confusion matrix for each

These are real outputs of your actual run, not something you need to
generate separately — just run the cells.

## Testing the model against new data

Two supported paths, both already in the notebook:

1. **Reload the trained model without retraining:**
   ```r
   payment_model <- readRDS("models/payment_model.rds")
   ```
2. **Score a new CSV shaped like your ledger:**
   ```r
   new_predictions <- predict_new_accounts("data/raw/some_new_batch.csv", payment_model)
   ```
   If the new data comes from a genuinely different source (different
   columns), write a `standardize_*()` function for it the same way the
   three in Section 6 were written — that's the pattern for adding a 4th
   data source later without touching the model itself.

## LLM chat setup

1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
   (Settings > API Keys) — this is separate from a claude.ai login
2. In a notebook cell: `Sys.setenv(ANTHROPIC_API_KEY = "your-key-here")`
   — don't hardcode it in a cell you commit to git
3. Run: `cat(ask_data_llm("your question here"))`

It sends a compact statistical summary of the portfolio (not raw per-debtor
rows) plus your question to Claude, so it stays fast and doesn't ship
individual debtor data unnecessarily.

## Notification pipeline — one thing to know before it's "real"

Section 4 drafts email/SMS content as R strings/data frames. It intentionally
stops there — there's no live send integration. Before wiring this to an
actual SMTP or SMS provider, check your jurisdiction's rules on automated
debt-collection communications (frequency limits, required disclosures,
opt-out language). Worth a line in your write-up either way.

## Next steps

See `PROJECT_PLAN.md` for the full 3-week breakdown — copy each `### Issue`
heading straight into your hackathon board.
