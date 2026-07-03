# ==============================================================================
# PURSUIT PREDICTION MODEL
# "Which flagged accounts are actually worth pursuing?"
#
# Extends financial_risk_engine.R. Run that script first so `unified_ledger`
# exists in your environment, then run this one.
# ==============================================================================
#
# WORKFLOW
#   STEP 0  Upload your 3 Kaggle CSVs to Colab (left sidebar > Files > upload,
#           or mount Google Drive) and set the paths in CONFIG below.
#   STEP 1  Run inspect_dataset() on each file FIRST. Compare the printed
#           column names against CONFIG and fix any mismatches before
#           proceeding — this is the step that actually matters.
#   STEP 2  Standardize each dataset onto a common feature schema.
#   STEP 3  Combine into one modeling table, split train/validation/test.
#   STEP 4  Train a baseline logistic regression predicting "did this account
#           get repaid."
#   STEP 5  Evaluate on the held-out validation and test sets.
#   STEP 6  Score your live `unified_ledger` accounts with a payment
#           probability and rank which ones are actually worth pursuing.
#
# HONEST CAVEAT ON CONFIG
#   Kaggle gates full column listings behind login for two of your three
#   datasets, so the column names in CONFIG below are my best-effort guess
#   from public dataset descriptions, not a confirmed schema dump. Run
#   Step 1 (inspect_dataset) and fix CONFIG before trusting anything past
#   that point. This is a template built to fail loudly and clearly if a
#   column name is wrong, not one that silently guesses around it.
# ==============================================================================

required_packages <- c("dplyr", "readr", "glue", "purrr", "tibble", "stringr")
new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(new_packages) > 0) install.packages(new_packages, repos = "https://cloud.r-project.org")
invisible(lapply(required_packages, library, character.only = TRUE))

set.seed(42)


# ------------------------------------------------------------------------------
# STEP 0/1: INSPECTION HELPER — run this on each file before touching CONFIG
# ------------------------------------------------------------------------------

inspect_dataset <- function(path, n_max = 5000) {
  df <- readr::read_csv(path, n_max = n_max, show_col_types = FALSE)
  cat("\n=====", path, "=====\n")
  cat("Columns:", paste(names(df), collapse = ", "), "\n")
  cat("Rows sampled:", nrow(df), "\n\n")
  print(dplyr::glimpse(df))
  invisible(df)
}

# Example (uncomment once files are uploaded):
# inspect_dataset("/content/bank_debt_data.csv")
# inspect_dataset("/content/banking_collections.csv")
# inspect_dataset("/content/synthetic_banking.csv")


# ------------------------------------------------------------------------------
# CONFIG — column-name mapping per dataset. VERIFY against Step 1 output.
# ------------------------------------------------------------------------------

CONFIG <- list(

  # kingabzpro/bank-debt-data
  # This is the classic "which debts are worth the effort to collect" dataset
  # (expected vs. actual recovery amount, recovery strategy tier used).
  # It's the cleanest source of a real repayment OUTCOME label you have.
  bank_debt = list(
    path                     = "/content/bank_debt_data.csv",
    id_col                   = "id",
    expected_recovery_col    = "expected_recovery_amount",
    actual_recovery_col      = "actual_recovery_amount",   # outcome derived from this
    strategy_col             = "recovery_strategy",
    age_col                  = "age",
    has_outcome              = TRUE
  ),

  # kotich/banking-collections-dataset-synthetic-data
  collections = list(
    path              = "/content/banking_collections.csv",
    id_col            = "Customer_ID",
    balance_col       = "Outstanding_Amount",
    original_col      = "Loan_Amount",
    risk_col          = "Risk_Level",       # categorical: Low/Medium/High (verify actual levels)
    days_past_due_col = "Days_Past_Due",
    outcome_col       = "Payment_Status",   # VERIFY this column exists and its values
    outcome_paid_values = c("Paid"),        # values in outcome_col that count as "repaid"
    has_outcome       = TRUE
  ),

  # akrambelha/synthetic-banking-dataset-csv-sql-sqlite
  # 1.26M+ records, likely relational (multiple tables). Treat as the weakest
  # signal source — good for extra feature enrichment, not a required input.
  # If it turns out to be multi-table, either flatten with a join before
  # pointing this at it, or skip this dataset for the model and use it only
  # for exploratory analysis / your LEARNING_JOURNAL.md writeup.
  synthetic_banking = list(
    path              = "/content/synthetic_banking.csv",
    id_col            = "Customer_ID",
    balance_col       = "Outstanding_Balance",
    original_col      = "Loan_Amount",
    days_past_due_col = "Days_Past_Due",
    outcome_col       = "Loan_Status",         # VERIFY
    outcome_paid_values = c("Closed"),         # VERIFY — assumes "Closed" == repaid
    has_outcome       = TRUE
  )
)


# ------------------------------------------------------------------------------
# STEP 2: STANDARDIZATION — map each dataset onto one common feature schema
# ------------------------------------------------------------------------------
# Common schema (deliberately minimal — only fields every collections/loan
# dataset realistically has, and that also exist in unified_ledger, so a
# model trained here can actually be applied there):
#   Source, Record_ID, Outcome_Repaid (0/1/NA), Balance_Amount, Debt_Ratio,
#   Days_Past_Due, Risk_Flag (0/1)

standardize_bank_debt <- function(cfg) {
  df <- readr::read_csv(cfg$path, show_col_types = FALSE)
  tibble(
    Source          = "bank_debt",
    Record_ID       = as.character(df[[cfg$id_col]]),
    Outcome_Repaid  = as.integer(df[[cfg$actual_recovery_col]] > 0),
    Balance_Amount  = df[[cfg$expected_recovery_col]],
    Debt_Ratio      = 1,  # no separate "original debt" field in this dataset
    Days_Past_Due   = NA_real_,
    Risk_Flag       = NA_integer_  # no explicit risk flag in this dataset
  )
}

standardize_collections <- function(cfg) {
  df <- readr::read_csv(cfg$path, show_col_types = FALSE)
  outcome <- if (!is.null(cfg$outcome_col) && cfg$outcome_col %in% names(df)) {
    as.integer(df[[cfg$outcome_col]] %in% cfg$outcome_paid_values)
  } else {
    NA_integer_
  }
  tibble(
    Source          = "collections",
    Record_ID       = as.character(df[[cfg$id_col]]),
    Outcome_Repaid  = outcome,
    Balance_Amount  = df[[cfg$balance_col]],
    Debt_Ratio      = df[[cfg$balance_col]] / pmax(df[[cfg$original_col]], 1),
    Days_Past_Due   = df[[cfg$days_past_due_col]],
    Risk_Flag       = as.integer(tolower(df[[cfg$risk_col]]) %in% c("high", "severe", "critical"))
  )
}

standardize_synthetic_banking <- function(cfg) {
  df <- readr::read_csv(cfg$path, show_col_types = FALSE)
  outcome <- if (!is.null(cfg$outcome_col) && cfg$outcome_col %in% names(df)) {
    as.integer(df[[cfg$outcome_col]] %in% cfg$outcome_paid_values)
  } else {
    NA_integer_
  }
  tibble(
    Source          = "synthetic_banking",
    Record_ID       = as.character(df[[cfg$id_col]]),
    Outcome_Repaid  = outcome,
    Balance_Amount  = df[[cfg$balance_col]],
    Debt_Ratio      = df[[cfg$balance_col]] / pmax(df[[cfg$original_col]], 1),
    Days_Past_Due   = df[[cfg$days_past_due_col]],
    Risk_Flag       = NA_integer_
  )
}

# Wrap each in tryCatch so one bad file doesn't kill the whole pipeline —
# prints a clear message pointing back at CONFIG instead of a cryptic error.
safe_standardize <- function(fn, cfg, label) {
  tryCatch(
    fn(cfg),
    error = function(e) {
      warning(glue("Could not standardize '{label}': {conditionMessage(e)}. ",
                    "Check CONFIG${label} column names against inspect_dataset() output."))
      NULL
    }
  )
}

modeling_data <- bind_rows(
  safe_standardize(standardize_bank_debt, CONFIG$bank_debt, "bank_debt"),
  safe_standardize(standardize_collections, CONFIG$collections, "collections"),
  safe_standardize(standardize_synthetic_banking, CONFIG$synthetic_banking, "synthetic_banking")
)

message(glue("Combined modeling table: {nrow(modeling_data)} rows from {n_distinct(modeling_data$Source)} source(s)."))


# ------------------------------------------------------------------------------
# STEP 3: TRAIN / VALIDATION / TEST SPLIT
# ------------------------------------------------------------------------------
# Only rows with a known outcome can be used for training. Base-R split (no
# extra dependency needed) — 70% train / 15% validation / 15% test.

labeled_data <- modeling_data %>% filter(!is.na(Outcome_Repaid))
message(glue("{nrow(labeled_data)} of {nrow(modeling_data)} rows have a usable outcome label."))

split_dataset <- function(df, train_frac = 0.70, val_frac = 0.15, seed = 42) {
  set.seed(seed)
  n <- nrow(df)
  idx <- sample(seq_len(n))
  train_end <- floor(train_frac * n)
  val_end   <- floor((train_frac + val_frac) * n)
  list(
    train = df[idx[1:train_end], ],
    val   = df[idx[(train_end + 1):val_end], ],
    test  = df[idx[(val_end + 1):n], ]
  )
}

splits <- split_dataset(labeled_data)
message(glue("Train: {nrow(splits$train)} | Validation: {nrow(splits$val)} | Test: {nrow(splits$test)}"))

# --- If you'd rather use caret for a stratified split (keeps the Paid/Unpaid
# ratio consistent across splits — worth it once you're past the prototype):
# install.packages("caret")
# library(caret)
# train_idx <- createDataPartition(labeled_data$Outcome_Repaid, p = 0.70, list = FALSE)
# train <- labeled_data[train_idx, ]
# remainder <- labeled_data[-train_idx, ]
# val_idx <- createDataPartition(remainder$Outcome_Repaid, p = 0.50, list = FALSE)
# val <- remainder[val_idx, ]; test <- remainder[-val_idx, ]


# ------------------------------------------------------------------------------
# STEP 4: BASELINE MODEL — logistic regression
# ------------------------------------------------------------------------------
# Logistic regression on purpose: no extra package dependency, coefficients
# are directly explainable to a non-technical reviewer ("higher balance
# lowers repayment odds by X%"), and it's a defensible baseline before
# reaching for anything heavier in a 2-3 week project.

payment_model <- glm(
  Outcome_Repaid ~ Balance_Amount + Debt_Ratio + Days_Past_Due + Risk_Flag,
  data = splits$train,
  family = binomial(link = "logit"),
  na.action = na.exclude
)

print(summary(payment_model))


# ------------------------------------------------------------------------------
# STEP 5: EVALUATION
# ------------------------------------------------------------------------------

evaluate_model <- function(model, data, threshold = 0.5, label = "set") {
  data <- data %>% filter(!is.na(Balance_Amount))
  pred_prob <- predict(model, newdata = data, type = "response")
  pred_class <- as.integer(pred_prob > threshold)
  actual <- data$Outcome_Repaid

  valid <- !is.na(pred_class) & !is.na(actual)
  pred_class <- pred_class[valid]; actual <- actual[valid]; pred_prob <- pred_prob[valid]

  accuracy <- mean(pred_class == actual)

  # Manual AUC (rank-based Mann-Whitney formulation — no extra package needed)
  pos <- pred_prob[actual == 1]
  neg <- pred_prob[actual == 0]
  auc <- if (length(pos) > 0 && length(neg) > 0) {
    mean(outer(pos, neg, ">")) + 0.5 * mean(outer(pos, neg, "=="))
  } else {
    NA_real_
  }

  cat(glue("--- {label} ---\n"))
  cat(glue("Accuracy: {round(accuracy, 3)}   AUC: {round(auc, 3)}\n"))
  cat("Confusion matrix:\n")
  print(table(Predicted = pred_class, Actual = actual))
  cat("\n")
  invisible(list(accuracy = accuracy, auc = auc))
}

evaluate_model(payment_model, splits$val, label = "Validation")
evaluate_model(payment_model, splits$test, label = "Test")


# ------------------------------------------------------------------------------
# STEP 6: SCORE LIVE ACCOUNTS + RANK "WORTH PURSUING"
# ------------------------------------------------------------------------------
# Requires `unified_ledger` from financial_risk_engine.R to be in your
# environment. Maps its columns onto the same standardized feature schema
# used for training, so the model's coefficients transfer cleanly.

score_unified_ledger <- function(unified_ledger, model) {
  scoring_input <- unified_ledger %>%
    mutate(
      Balance_Amount = Remaining_Balance,
      Debt_Ratio      = Remaining_Balance / pmax(Original_Debt, 1),
      Days_Past_Due   = Days_Past_Due,
      Risk_Flag       = as.integer(Is_Blacklisted | Has_External_Debts)
    )

  scoring_input$Predicted_Payment_Probability <- predict(
    model, newdata = scoring_input, type = "response"
  )

  scoring_input %>%
    mutate(
      Expected_Recovery_Value = round(Predicted_Payment_Probability * Remaining_Balance, 2),
      Worth_Pursuing = case_when(
        !Critical_Alert                         ~ "Not Flagged",
        Predicted_Payment_Probability >= 0.6    ~ "High Priority",
        Predicted_Payment_Probability >= 0.3    ~ "Medium Priority",
        TRUE                                     ~ "Low Priority — consider write-off"
      )
    ) %>%
    select(Debtor_ID, Debtor_Name, Remaining_Balance, Critical_Alert, Risk_Tier,
           Predicted_Payment_Probability, Expected_Recovery_Value, Worth_Pursuing) %>%
    arrange(desc(Expected_Recovery_Value))
}

# Run once financial_risk_engine.R has produced `unified_ledger`:
# pursuit_rankings <- score_unified_ledger(unified_ledger, payment_model)
# print(head(pursuit_rankings, 15))
# write_csv(pursuit_rankings, "pursuit_rankings.csv")

message("Pursuit prediction model built. Run score_unified_ledger(unified_ledger, payment_model) once you have both objects loaded.")
