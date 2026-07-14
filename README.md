# Financial Risk Analytics Engine (Pursuit)

An R-based financial risk analytics pipeline, built for Google Colab. It merges debtor and external risk data, computes exposure and risk tiers, drafts collection notifications, visualizes portfolio health, and trains a model to rank which flagged accounts are actually worth pursuing. A chat layer sits on top, answering plain-English questions about the portfolio via an LLM API.

## Quick start

1. Open `financial_risk_analytics.ipynb` in Google Colab
2. Runtime > Change runtime type > R
3. Run cells top to bottom (Section 0 → Section 8)

Sections 0–5, 7, and 8 run on simulated data with no setup. Section 6 (the prediction model) needs two real datasets uploaded to `data/raw/` — details below.

## Project structure

```
financial-risk-analytics-engine/
├── README.md
├── PROJECT_PLAN.md                 <- issue tracker / task breakdown
├── financial_risk_analytics.ipynb  <- main notebook
├── src/
│   ├── financial_risk_engine.R     <- standalone version of Sections 0-5
│   └── pursuit_prediction_model.R  <- standalone version of Section 6
├── data/
│   ├── raw/                        <- Kaggle CSVs live here
│   └── processed/                  <- unified_ledger.csv, generated
├── models/
│   └── payment_model.rds           <- trained model, generated
└── outputs/
    ├── charts/
    ├── notification_queue.csv
    └── pursuit_rankings.csv
```

`src/` holds the same logic as the notebook split into two plain scripts, for working outside Colab. The notebook doesn't depend on `src/` — either can be used on its own.

## What each notebook section does

| Section | Purpose |
|---|---|
| 0 | Package setup |
| 1 | Schema contracts + validation for the Master Ledger / Risk Registry |
| 2 | Data source — simulated by default, toggled to real CSVs via `USE_REAL_DATA` |
| 3 | Merge, `Remaining_Balance`, `Net_Profit`, `Critical_Alert`, `Risk_Tier` |
| 4 | Email + SMS notification drafts for flagged accounts (draft only, no send integration) |
| 5 | Three ggplot2 visualizations |
| 6 | Pursuit prediction model — repayment probability, evaluation, account ranking |
| 7 | LLM chat layer over the portfolio data |
| 8 | Output file summary |

## Datasets used for the prediction model

- `kingabzpro/bank-debt-data` — real recovered/not-recovered outcome data
- `kotich/banking-collections-dataset-synthetic-data` — richer per-account risk features

A third dataset (`akrambelha/synthetic-banking-dataset-csv-sql-sqlite`) was evaluated and set aside — its relational, multi-table structure didn't fit the flat modeling schema the other two share, and it wasn't needed once `bank-debt-data` and `banking-collections` covered both a real label and rich features between them.

**Model training currently uses `banking-collections` only.** `bank-debt-data`'s derived outcome label (`actual_recovery_amount > 0`) turned out to have no variance in practice — effectively every row read as "repaid" — so it contributes no training signal and is excluded from the `labeled_data` filter, though it's still loaded and standardized in case that changes with a different derivation later.

Current model performance: AUC ≈ 0.53 on both validation and test, using `Balance_Amount`, `Debt_Ratio`, and `Risk_Flag`. That's modest — only slightly better than chance — which reflects a genuinely weak relationship between these particular features and repayment in this dataset, not a bug in the pipeline. `Days_Past_Due` was dropped from the model after inspection showed it was missing for all rows in the real file.

`CONFIG` in Section 6 maps each dataset's real columns onto a shared schema. Kaggle gates full column previews behind login, so those mappings were originally best-effort guesses — `inspect_dataset()` at the top of that section exists specifically to check them against the real files before the standardize functions run.

## Model stats

`summary(payment_model)`, plus accuracy/AUC/confusion matrices on the validation and test sets, print inline once the "Train the model" and "Evaluate" cells run — no separate report generation needed.

## Testing the model against new data

```r
payment_model <- readRDS("models/payment_model.rds")            # reload without retraining
new_predictions <- predict_new_accounts("data/raw/some_new_batch.csv", payment_model)
```

A dataset shaped like the Master Ledger scores directly through `predict_new_accounts()`. A dataset from a new source with different columns needs its own `standardize_*()` function, following the pattern of the two already in Section 6.

## LLM chat layer

Section 7 sends a compact statistical summary of the portfolio (not raw per-debtor rows) alongside the question to an LLM API, and can also detect a specific `Debtor_ID` mentioned in the question and return single-account detail instead. The API call itself is provider-agnostic — `call_llm()` is the only function that changes depending on which provider's key is in use.

## Notification pipeline

Section 4 drafts email/SMS content as R strings/data frames. There's no live send integration — connecting this to an actual SMTP or SMS provider is a separate step, and worth checking relevant regulations on automated debt-collection communications before that happens.

## Dataset licensing

Code in this repository is MIT licensed (see `LICENSE`). The two Kaggle datasets used for training keep their own respective licenses — see `PROJECT_PLAN.md` for the outstanding task of documenting each one's specific terms.

## Task tracking

See `PROJECT_PLAN.md` for the current issue list.
