# Learning Journal — Pursuit (Financial Risk Analytics Engine)

Decisions made along the way, and the reasoning behind them. Written as a record for anyone reviewing this project (including future me) — not a step-by-step build log, just the calls that needed actual judgment.

---

## Data architecture

**Master Ledger / External Risk Registry split.** Kept these as two separate schemas joined on `Debtor_ID` rather than one flat table, mirroring how this data would realistically arrive in production — billing data and external risk/blacklist data typically come from different systems. `validate_schema()` checks both independently before the join, so a malformed file fails with a clear "missing column X" message rather than a cryptic downstream error three cells later.

**Zero-balance interest edge case.** Decided early that an account with `Remaining_Balance <= 0` can never be flagged `Critical_Alert`, regardless of blacklist/external-debt status — you can't meaningfully "chase" a debt that's already been paid off, even if the debtor has other red flags. Verified this holds even when both risk flags are `TRUE`:
```r
zero_balance_test$Critical_Alert  # FALSE, confirmed
```
The alternative (accruing a small grace-period interest charge even on a technically-closed account) was considered and rejected — it would conflate two different concerns (repayment status vs. ongoing risk) that are cleaner kept separate.

## Model training — what got excluded, and why

**`bank_debt` excluded from training.** Its derived outcome label (`actual_recovery_amount > 0`) turned out to have zero variance in the real data — effectively every row read as "repaid." Confirmed with:
```r
labeled_data %>% group_by(Source) %>% summarise(n = n(), pct_repaid = mean(Outcome_Repaid))
# bank_debt: pct_repaid = 1.000
```
A label with no variance contributes nothing to training and can silently make a combined model look better than it is (by letting it "win" on accuracy just by matching the majority source). Excluded from `labeled_data`, but left in the pipeline (still loaded and standardized) in case a different label derivation is worth revisiting later.

**`Risk_Flag` and `Days_Past_Due` dropped from the final model.** Both only existed on a subset of the training sources. Including them caused `glm()` to silently drop any row missing either field — in one run, this meant ~97% of a ~33,000-row training set was discarded to missingness without an obvious error, just a much smaller "degrees of freedom" number in the model summary than expected. Caught by explicitly checking:
```r
sapply(splits$train[, c("Balance_Amount","Debt_Ratio","Days_Past_Due","Risk_Flag")], function(x) sum(is.na(x)))
```
Final model trains on `Balance_Amount + Debt_Ratio` only — the two features every training source actually has.

**`Days_Overdue_Delay` never used as a feature for the invoice dataset**, even though it's the most obviously predictive-looking field there. It's very likely what `DelayFlag` (the outcome label) was derived from — including it as a predictor would let the model trivially "predict" the label by re-deriving it, producing a misleadingly perfect result rather than a real one. This is a general principle worth remembering: a feature that looks suspiciously perfect is worth checking for label leakage before trusting it.

**Result: AUC ≈ 0.48–0.49 on both validation and test, ~32,800 training rows, neither predictor statistically significant.** This is treated as a genuine, well-powered negative finding — not a bug to keep chasing. The first version of this model (trained on ~1,000 rows before the invoice dataset was added) showed a similar AUC but with far less statistical power to back it up; the larger run confirms rather than merely suggests that balance and debt ratio alone don't predict repayment in this combined dataset. Candidate features for a future, better model exist in both remaining datasets (`Risk_Level`/`Loan_Type`/`EMI_Amount` on `collections`; `Payment_Term`/`Age_Of_Customer_Months` on the invoice dataset) but aren't shared across sources, meaning a real improvement would mean training source-specific models rather than one combined one.

## Currency handling

**Fixed exchange rate over a live API for model training data.** A currency-conversion API (`open.er-api.com`) was found and tested, but deliberately not applied to the model-training datasets — two of the three sources have no confirmed currency at all (fictional zip/region codes, no stated locale), so applying a real conversion rate to unconfirmed-currency numbers would be false precision, not added accuracy. It's also mathematically moot: rescaling `Balance_Amount` by a constant doesn't change a logistic regression's AUC or p-values, only the coefficient's magnitude.

**Live rate used for the dashboard's simulated data, with the actual rate written to a log file.** Here the conversion is meaningful (the simulated Master Ledger data is genuinely dollar-scale, invented for this project), so `get_usd_to_zar_rate()` fetches a live rate with a hardcoded fallback if the API's unreachable, and records what rate was used to `outputs/exchange_rate_used.csv` for reproducibility. A live rate was deliberately *not* used to silently vary the model results shown in a write-up — reproducibility mattered more than up-to-the-minute accuracy for that piece.

**`SEVERE_THRESHOLD` rescaled alongside the currency conversion.** The `Risk_Tier` cutoff (`Remaining_Balance > 5000`) was calibrated for dollar-scale debts; multiplying the underlying data by ~16.5 without also rescaling this threshold would have collapsed nearly every account into "Severe" and made "Critical" disappear. Caught before it became a silent, hard-to-notice reporting bug.

## Chat / LLM layer

**Two-tier design: an offline keyword-based fallback, and a real LLM-backed layer, kept as separate functions.** `ask_data()` pattern-matches on common analyst questions (critical accounts, profit/loss, blacklist counts, top balances) without needing any API key or network access — useful as a baseline that works regardless of billing/API availability. `ask_data_llm()` sends a compact statistical summary (not raw per-debtor rows) to an LLM for genuinely open-ended questions. Keeping these separate meant API billing issues didn't block all NL-query functionality — only the more flexible tier.

**Debtor-specific lookup added via a regex, not a database join.** `build_data_context()` checks the question text for a `Debtor_ID`-like pattern before falling back to a portfolio-level summary. This is pattern matching, not real language understanding — it'll miss oddly-phrased references to a specific account. A known, documented limitation rather than a silent one.

## Dashboard (Shiny / querychat)

**Styling iterated through many small, targeted CSS/R fixes rather than one big rewrite.** Several rounds of "this didn't apply" turned out to be simple root causes once diagnosed properly: a missing `.` before a class name (targeting a nonexistent HTML element instead of the intended CSS class), a CSS specificity/ordering conflict (two rules of equal specificity, later one silently winning), and asymmetric column widths that looked fine at one screen size but broke at another. The general lesson: when a CSS change does *nothing at all*, the selector usually isn't matching anything — worth confirming via browser "Inspect Element" rather than guessing a second time.

**`layout_columns()` widths reverted from a fixed asymmetric ratio back to auto-sizing** after the fixed ratio broke at narrower screen widths (text wrapping to one character per line). Chose robustness over a specific visual proportion.
