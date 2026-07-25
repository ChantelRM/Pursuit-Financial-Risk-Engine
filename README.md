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
- A third invoice/accounts-receivable dataset (`Dataset.csv`, Cust_Num/Amount/DelayFlag schema) — added later for a larger, better-powered label source

`bank-debt-data`'s derived outcome label (`actual_recovery_amount > 0`) has no variance in practice — every row reads as "repaid" — so it contributes no training signal and is excluded from `labeled_data`, though it's still loaded and standardized in case that changes with a different derivation later.

**Model training uses `collections` + the invoice dataset combined (~33,000 labeled rows).** The two sources share only `Balance_Amount`/`Debt_Ratio` as common features — their schemas otherwise diverge (loan/account fields on one side, payment-term/customer-age fields on the other), so the model is necessarily limited to those two shared predictors. A field resembling "days overdue" exists in both sources but isn't used: on the invoice dataset it's very likely what the outcome label was derived from (using it as a feature would leak the label back into training), and on the collections dataset alone it would reintroduce single-source missingness that breaks `glm()`'s row-dropping behavior when sources are combined.

`CONFIG` in Section 6 maps each dataset's real columns onto a shared schema. Kaggle gates full column previews behind login, so those mappings were originally best-effort guesses — `inspect_dataset()` at the top of that section exists specifically to check them against the real files before the standardize functions run.

## Model performance

Current result, trained on `Balance_Amount + Debt_Ratio` across ~32,800 training rows: **AUC ≈ 0.48–0.49** on both validation and test, with neither predictor statistically significant (p > 0.1). This is a well-powered negative result, not an under-tested one — with this much data, a real relationship between these two features and repayment would be expected to show up if it existed. It didn't.

`Risk_Flag` and `Days_Past_Due` were tested and dropped from the final model: `Risk_Flag` only exists on one of the two training sources, which caused `glm()` to silently drop ~97% of rows to missingness when included (a rerun with it removed confirmed the full dataset was actually being used). `Days_Past_Due` was excluded up front for the leakage reason above.

**Honest takeaway for the write-up:** outstanding balance and debt ratio alone aren't predictive of repayment in this combined dataset. Candidate features for future improvement — none currently shared across the training sources, so this would mean training source-specific models rather than one combined model: `Risk_Level`/`Loan_Type`/`EMI_Amount` (collections-only) or `Payment_Term`/`Age_Of_Customer_Months`/`No_of_orders_by_customer` (invoice dataset-only).

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

## Architecture & Design Decisions

This project went through real debugging, not just implementation — the reasoning behind each non-obvious call is documented in full in `LEARNING_JOURNAL.md`. Summary of the ones that mattered most:

- **Schema-first validation** (`validate_schema()`) — every dataset is checked against an explicit expected schema before use, so a bad column fails loudly at the point of ingestion rather than silently three cells later. This paid off repeatedly: most of this project's real bugs were caught this way rather than through trial and error.
- **Excluding `bank_debt` from model training** — its derived outcome label had zero variance (confirmed via `group_by(Source) %>% summarise(pct_repaid = ...)`), which would have let the model "win" on accuracy by matching a majority class rather than learning anything real. Kept in the pipeline for a different purpose (the recovery-strategy cost-benefit analysis) rather than discarded entirely.
- **Reporting a negative model result honestly** — the final pursuit-prediction model shows AUC ≈ 0.48–0.49 on ~33,000 well-powered rows. Rather than keep tuning until a better-looking number appeared, this was treated as a real, defensible finding: these two features don't predict repayment in this data. A worse-looking-but-true result was chosen over a better-looking-but-misleading one at an earlier stage (a ~1,000-row version that hit 76% accuracy purely by exploiting the excluded dataset's label imbalance).
- **Reframing rather than discarding a flawed feature** — an initial "find similar historical debtors, recommend their strategy" feature turned out to be unsupportable (the source dataset assigns strategy purely by balance band, so there's no counterfactual to learn from). Rather than drop the work, it was reframed into a valid question the data *does* support: a cost-benefit check at each strategy threshold, using the dataset's own documented $50-per-level cost structure.
- **Fixed exchange rate over a live currency API for model data** — deliberately not applied to training data, since two of three source datasets have no confirmed currency; applying real conversion math to unconfirmed-currency numbers would be false precision. Applied instead to the dashboard's own simulated data, where the conversion is meaningful, with the rate used logged to a file for reproducibility.
- **Two-tier LLM chat design** — an offline keyword-matched fallback (`ask_data()`) alongside the full LLM-backed layer (`ask_data_llm()`), so a billing/API issue blocks only the more flexible tier, not natural-language querying entirely.

A few debugging lessons worth naming plainly, since catching and understanding these is as much a part of the engineering as writing the code the first time:
- **Silent missingness from mismatched training sources** — combining datasets where a feature exists in only some of them caused `glm()` to silently drop ~97% of rows to missingness, producing a model that looked fine until the degrees-of-freedom count was checked directly.
- **JSON auto-simplification breaking a working API call** — `httr::content(resp, "parsed")` silently converted a JSON array-of-objects into a data frame, so `parsed$content[[1]]$text` grabbed a column instead of a list element and returned `NULL` with no error at all. Fixed by parsing explicitly with `jsonlite::fromJSON(..., simplifyVector = FALSE)`.
- **Assuming a fixed response shape** — the same function initially assumed the LLM's first response block was always the text block; Claude can return a `"thinking"` block first for substantive prompts, so the fix filters by block `type` rather than assuming position.
- **Reproducibility gaps in `set.seed()`** — reseeding once at the top of a notebook doesn't protect against a cell being rerun later in the same session after other random draws have already consumed part of the sequence; a defensive reseed immediately before each simulation call closes that gap.

## Future Work

- **Test `predict_new_accounts()` against a genuinely held-out dataset.** Its schema-validation behavior was confirmed correct, but it's never been run end-to-end against real unseen data — worth doing before treating the model as production-ready in any sense.
- **Source-specific models instead of one combined model.** `collections` and the invoice dataset share almost no features beyond balance — a model trained per-source using each dataset's full feature set (e.g. `Risk_Level`/`Loan_Type`/`EMI_Amount` for one, `Payment_Term`/`Age_Of_Customer_Months` for the other) would likely outperform the current shared-feature-only approach.
- **Revisit the set-aside relational dataset** (accounts/loans/customers/merchants/branches/cards) with an actual join across tables rather than a single flat file, now that the other two datasets have proven the pipeline can handle real, messy Kaggle data.
- **A proper regression discontinuity design** for the recovery-strategy analysis, rather than the simpler fixed-window threshold comparison currently used — would give more statistically rigorous estimates of the effect at each cutoff.
- **CI/automated retraining** — a GitHub Action to re-run the notebook on push, catching breakage automatically rather than relying on manual "restart and run all" passes.
- **Live send integration for notifications**, once the jurisdiction-specific compliance review noted above is actually done — the drafting pipeline is complete, but deliberately stops short of connecting to a real SMTP/SMS provider.
- **Per-debtor, feature-driven strategy recommendations**, once a dataset with genuine strategy/outcome variation at matched balance levels is available — the current cost-benefit analysis is portfolio-level and threshold-based, not yet a per-account recommendation.

## Dataset licensing

Code in this repository is MIT licensed (see `LICENSE`). The two Kaggle datasets used for training keep their own respective licenses — see `PROJECT_PLAN.md` for the outstanding task of documenting each one's specific terms.

## Task tracking

See `PROJECT_PLAN.md` for the current issue list.
