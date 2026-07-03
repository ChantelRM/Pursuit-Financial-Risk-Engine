# Financial Risk Analytics Engine — Project Plan (2–3 Weeks)

Each `###` heading is meant to be copy-pasted as one GitHub Issue. Checkboxes
become the issue's task list. Suggested labels are in brackets.

---

## Week 1 — Foundation & Data Layer

### Issue 1: Repo & environment setup `[setup]`
- [ ] Create GitHub repo, add `.gitignore` for R (`*.Rhistory`, `*.RData`)
- [ ] Confirm Colab R runtime works end-to-end (Runtime > Change runtime type > R)
- [ ] Add `financial_risk_engine.R` and confirm it runs top-to-bottom with simulated data
- [ ] Write a short `README.md`: what the project does, how to run it in Colab

### Issue 2: Source and inspect real Kaggle datasets `[data]`
- [ ] Find a Kaggle dataset for debt/collections or credit risk (search terms: "debt collection", "loan default", "credit risk dataset")
- [ ] Map its columns onto `MASTER_LEDGER_SCHEMA` and `RISK_REGISTRY_SCHEMA` — note any gaps
- [ ] Decide how to fill schema gaps (e.g. no `Cost_To_Acquire` in the raw data → derive or simulate it)
- [ ] Document the mapping decisions in `LEARNING_JOURNAL.md` or `DATA_SOURCES.md`

### Issue 3: Schema validation & loader `[data]`
- [ ] Implement `load_and_validate_csv()` against the real dataset (already stubbed in the script)
- [ ] Handle type coercion issues (dates, TRUE/FALSE stored as 0/1 or "Y"/"N", etc.)
- [ ] Add at least 3 unit-style checks (row count > 0, no duplicate `Debtor_ID`, no negative `Original_Debt`)

### Issue 4: Merge & validate unified view `[data]`
- [ ] Merge Master Ledger + Risk Registry on `Debtor_ID`
- [ ] Confirm row count doesn't change after merge (catches join fan-out bugs)
- [ ] Decide and document how to handle debtors present in one dataset but not the other

---

## Week 2 — Computations, Notifications, Visuals

### Issue 5: Financial computations `[core]`
- [ ] Implement `Remaining_Balance`, `Net_Profit`
- [ ] Decide the zero-balance interest edge case (see note below) and implement it
- [ ] Add `Days_Past_Due` using a real "today" reference or a fixed evaluation date if working with historical Kaggle data

### Issue 6: Composite risk rule `[core]`
- [ ] Implement `Critical_Alert` (active balance AND blacklisted/external debt)
- [ ] Add a `Risk_Tier` breakdown (Clear / Watch / Critical / Severe) for more useful reporting than a binary flag
- [ ] Validate against a few hand-picked rows to confirm the logic matches intent

### Issue 7: Notification drafting pipeline `[communication]`
- [ ] Implement email draft template (professional, urgent, includes balance/days past due/call to action)
- [ ] Implement SMS draft template, enforce the 160-character limit programmatically
- [ ] Export `notification_queue.csv` for manual review before any real send integration
- [ ] Write a short section in the README on the legal/compliance considerations of automated collections messaging in your jurisdiction (this matters before ever wiring this to a real send step)

### Issue 8: Visualizations `[analytics]`
- [ ] Balance distribution histogram (Critical vs. non-Critical)
- [ ] Risk matrix scatter (balance vs. days past due, colored by tier)
- [ ] Monthly profit/loss bar chart
- [ ] Save all charts as PNG for the final report/demo deck

---

## Week 3 — Interactivity, Polish, Delivery

### Issue 9: Natural-language query layer `[stretch]`
- [ ] Get `chattr` (or a direct API call) working with a real LLM backend, OR
- [ ] Extend the offline `ask_data()` fallback with 3–5 more question patterns your grader/reviewer is likely to try
- [ ] Document which option you used and why (API key friction is a legitimate reason to use the fallback for a class project)

### Issue 10: Testing & edge cases `[quality]`
- [ ] Zero-balance accounts: confirm they're never flagged Critical Alert
- [ ] Fully-paid accounts with external debt flags: confirm no false positive
- [ ] Duplicate `Debtor_ID` across datasets: confirm merge behavior is intentional, not accidental
- [ ] Extremely large/small dollar values: confirm formatting doesn't break SMS length or currency display

### Issue 11: Documentation & handoff `[delivery]`
- [ ] Finalize `README.md` with setup, run instructions, and a screenshot of one chart
- [ ] Finalize `LEARNING_JOURNAL.md` with design decisions (schema choices, risk rule rationale, zero-balance resolution, chattr vs. fallback decision)
- [ ] Record a 2–3 min walkthrough or write a short "system overview" doc if this is being presented

### Issue 12: Final review pass `[delivery]`
- [ ] Run the full script fresh in a clean Colab session start to finish, confirm no errors
- [ ] Sanity-check all output files (`unified_ledger.csv`, `notification_queue.csv`, `portfolio_summary.csv`)
- [ ] Peer review (if applicable) or self-review against the original spec, section by section

---

## Note on the zero-balance interest edge case

You mentioned this is still open. The two common approaches:

1. **No balance, no interest** — if `Remaining_Balance <= 0`, interest/penalty calculations simply don't apply, and the account can never be `Critical_Alert` regardless of blacklist/external-debt status. This is what the current script does implicitly, since `Critical_Alert` requires `Remaining_Balance > 0`.
2. **Grace-period interest** — some ledgers still accrue a small interest charge on a technically-closed account during a grace window (e.g. a late final payment). If your Kaggle dataset or assignment brief implies this, you'd add an `Interest_Accrued` column and a separate flag rather than folding it into `Critical_Alert`, so the two concerns (repayment status vs. risk status) stay clearly separated.

Worth deciding this early since it affects both the risk rule and the notification templates.
