# ==============================================================================
# PURSUIT — FINANCIAL RISK ANALYTICS ENGINE (standalone script)
#
# Merged version of the Colab notebook: Sections 0-5 (ledger/risk/notifications
# /charts) + Section 6 (pursuit prediction model, debugged version) + Section 7
# (LLM chat layer). Run top to bottom with Rscript, or source() in RStudio.
#
# This reflects the ACTUAL debugged state from the notebook, not the earlier
# src/ drafts — in particular, Section 6 here trains on Balance_Amount +
# Debt_Ratio only (Risk_Flag and Days_Past_Due were tested and dropped after
# they caused ~97% row loss to missingness when sources were combined — see
# README for the full explanation), and uses the real 3-dataset CONFIG
# (bank_debt, collections, invoice_delay) rather than the original draft's
# akrambelha/synthetic_banking placeholder.
# ==============================================================================

# ------------------------------------------------------------------------------
# SECTION 0: SETUP
# ------------------------------------------------------------------------------
required_packages <- c("dplyr", "ggplot2", "tibble", "purrr", "glue",
                        "scales", "lubridate", "readr", "tidyr", "stringr",
                        "httr", "jsonlite")

new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(new_packages) > 0) install.packages(new_packages, repos = "https://cloud.r-project.org")
invisible(lapply(required_packages, library, character.only = TRUE))

set.seed(42)
dir.create("outputs", showWarnings = FALSE)
dir.create("outputs/charts", showWarnings = FALSE)
dir.create("models", showWarnings = FALSE)
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)


# ------------------------------------------------------------------------------
# SECTION 1: SCHEMA CONTRACTS
# ------------------------------------------------------------------------------
MASTER_LEDGER_SCHEMA <- list(
  Debtor_ID = "integer", Debtor_Name = "character", Billing_Month = "Date",
  Original_Debt = "numeric", Amount_Paid = "numeric", Cost_To_Acquire = "numeric"
)

RISK_REGISTRY_SCHEMA <- list(
  Debtor_ID = "integer", Is_Blacklisted = "logical", Has_External_Debts = "logical"
)

validate_schema <- function(df, schema, df_name = "dataset") {
  missing_cols <- setdiff(names(schema), names(df))
  if (length(missing_cols) > 0) {
    stop(glue("[{df_name}] Missing required columns: {paste(missing_cols, collapse = ', ')}"))
  }
  problems <- c()
  for (col in names(schema)) {
    expected <- schema[[col]]
    actual_class <- class(df[[col]])[1]
    ok <- (actual_class == expected) ||
      (expected == "numeric" && actual_class %in% c("numeric", "integer")) ||
      (expected == "integer" && actual_class %in% c("numeric", "integer"))
    if (!ok) problems <- c(problems, glue("  - {col}: expected {expected}, got {actual_class}"))
  }
  if (length(problems) > 0) stop(glue("[{df_name}] Schema mismatches:\n{paste(problems, collapse = '\n')}"))
  message(glue("[{df_name}] Schema OK ({nrow(df)} rows, {ncol(df)} cols)"))
  invisible(TRUE)
}

load_and_validate_csv <- function(path, schema, df_name = "dataset", date_cols = character(0)) {
  df <- readr::read_csv(path, show_col_types = FALSE)
  for (dc in date_cols) if (dc %in% names(df)) df[[dc]] <- as.Date(df[[dc]])
  validate_schema(df, schema, df_name)
  df
}


# ------------------------------------------------------------------------------
# SECTION 2: DATA — simulated by default, flip USE_REAL_DATA once ready
# ------------------------------------------------------------------------------
USE_REAL_DATA <- FALSE

simulate_master_ledger <- function(n = 250) {
  original_debt <- round(runif(n, 500, 12000), 2)
  payment_ratio <- rbeta(n, 2, 3)
  tibble(
    Debtor_ID = 1:n,
    Debtor_Name = paste0("Debtor_", str_pad(1:n, 4, pad = "0")),
    Billing_Month = sample(seq(as.Date("2025-01-01"), as.Date("2025-12-01"), by = "month"), n, replace = TRUE),
    Original_Debt = original_debt,
    Amount_Paid = round(pmin(original_debt, original_debt * payment_ratio), 2),
    Cost_To_Acquire = round(runif(n, 40, 450), 2)
  )
}

simulate_risk_registry <- function(n = 250) {
  tibble(
    Debtor_ID = 1:n,
    Is_Blacklisted = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.14, 0.86)),
    Has_External_Debts = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.22, 0.78))
  )
}

if (USE_REAL_DATA) {
  master_ledger <- load_and_validate_csv("data/raw/master_ledger.csv", MASTER_LEDGER_SCHEMA,
                                          "Master Ledger", date_cols = "Billing_Month")
  external_risk_registry <- load_and_validate_csv("data/raw/risk_registry.csv", RISK_REGISTRY_SCHEMA,
                                                    "External Risk Registry")
} else {
  master_ledger <- simulate_master_ledger(250)
  external_risk_registry <- simulate_risk_registry(250)
  validate_schema(master_ledger, MASTER_LEDGER_SCHEMA, "Master Ledger")
  validate_schema(external_risk_registry, RISK_REGISTRY_SCHEMA, "External Risk Registry")
}


# ------------------------------------------------------------------------------
# SECTION 3: MERGE & RISK COMPUTATIONS
# ------------------------------------------------------------------------------
unified_ledger <- master_ledger %>% left_join(external_risk_registry, by = "Debtor_ID")
stopifnot(nrow(unified_ledger) == nrow(master_ledger))

unified_ledger <- unified_ledger %>%
  mutate(
    Remaining_Balance = round(Original_Debt - Amount_Paid, 2),
    Net_Profit = round(Amount_Paid - Cost_To_Acquire, 2),
    Days_Past_Due = as.integer(Sys.Date() - Billing_Month),
    Critical_Alert = Remaining_Balance > 0 & (Is_Blacklisted | Has_External_Debts),
    Risk_Tier = case_when(
      Critical_Alert & Remaining_Balance > 5000 ~ "Severe",
      Critical_Alert ~ "Critical",
      Remaining_Balance > 0 ~ "Watch",
      TRUE ~ "Clear"
    )
  )

message(glue("Flagged {sum(unified_ledger$Critical_Alert)} of {nrow(unified_ledger)} accounts as Critical Alert."))
write_csv(unified_ledger, "data/processed/unified_ledger.csv")


# ------------------------------------------------------------------------------
# SECTION 4: NOTIFICATION DRAFTS (email + SMS)
# ------------------------------------------------------------------------------
generate_email_draft <- function(row) {
  glue(
"Subject: URGENT: Outstanding Balance Notice - Account #{row$Debtor_ID}

Dear {row$Debtor_Name},

This notice is to formally inform you that our records show an outstanding
balance on your account that requires immediate attention.

  Account Reference:     {row$Debtor_ID}
  Outstanding Balance:   ${format(row$Remaining_Balance, big.mark=',', nsmall=2)}
  Days Past Due:         {row$Days_Past_Due} days
  Risk Classification:   {row$Risk_Tier}

Please settle this balance or contact us to arrange a payment plan within
7 days of this notice to avoid further collection action.

Regards,
Accounts Recovery Team"
  )
}

generate_sms_draft <- function(row) {
  msg <- glue(
    "ALERT: Acct #{row$Debtor_ID}, balance ${format(row$Remaining_Balance, nsmall=2)} ",
    "is {row$Days_Past_Due}d overdue. Pay within 7 days to avoid legal/credit ",
    "action. Reply HELP for options."
  )
  if (nchar(msg) > 160) {
    msg <- glue(
      "ALERT: Acct #{row$Debtor_ID} owes ${format(row$Remaining_Balance, nsmall=0)}, ",
      "{row$Days_Past_Due}d overdue. Pay in 7 days to avoid escalation."
    )
  }
  as.character(msg)
}

critical_accounts <- unified_ledger %>% filter(Critical_Alert)

notification_queue <- critical_accounts %>%
  select(Debtor_ID, Debtor_Name, Remaining_Balance, Days_Past_Due, Risk_Tier) %>%
  mutate(
    Email_Draft = pmap_chr(critical_accounts, function(...) generate_email_draft(tibble(...))),
    SMS_Draft = pmap_chr(critical_accounts, function(...) generate_sms_draft(tibble(...))),
    SMS_Char_Count = nchar(SMS_Draft)
  )

write_csv(notification_queue, "outputs/notification_queue.csv")


# ------------------------------------------------------------------------------
# SECTION 5: VISUALIZATIONS
# ------------------------------------------------------------------------------
theme_risk <- theme_minimal(base_size = 13) + theme(plot.title = element_text(face = "bold"))

plot_balance_distribution <- ggplot(unified_ledger, aes(x = Remaining_Balance, fill = Critical_Alert)) +
  geom_histogram(bins = 30, alpha = 0.85, position = "identity") +
  scale_fill_manual(values = c("FALSE" = "#4C9F70", "TRUE" = "#D64545"), labels = c("Standard", "Critical Alert")) +
  scale_x_continuous(labels = scales::dollar_format()) +
  labs(title = "Distribution of Remaining Balances", x = "Remaining Balance", y = "Accounts", fill = "Status") +
  theme_risk

plot_risk_matrix <- ggplot(unified_ledger, aes(x = Days_Past_Due, y = Remaining_Balance, color = Risk_Tier)) +
  geom_point(alpha = 0.75, size = 2.4) +
  scale_color_manual(values = c("Clear" = "#4C9F70", "Watch" = "#E8B339", "Critical" = "#E06C3B", "Severe" = "#B5251F")) +
  scale_y_continuous(labels = scales::dollar_format()) +
  labs(title = "Risk Matrix: Balance vs. Days Past Due", x = "Days Past Due", y = "Remaining Balance", color = "Risk Tier") +
  theme_risk

monthly_pnl <- unified_ledger %>% group_by(Billing_Month) %>%
  summarise(Total_Net_Profit = sum(Net_Profit), .groups = "drop") %>%
  mutate(Result = ifelse(Total_Net_Profit >= 0, "Profit", "Loss"))

plot_monthly_pnl <- ggplot(monthly_pnl, aes(x = Billing_Month, y = Total_Net_Profit, fill = Result)) +
  geom_col() + geom_hline(yintercept = 0, color = "grey30") +
  scale_fill_manual(values = c("Profit" = "#4C9F70", "Loss" = "#B5251F")) +
  scale_y_continuous(labels = scales::dollar_format()) +
  labs(title = "Monthly Net Profit vs. Loss", x = "Billing Month", y = "Net Profit") +
  theme_risk

ggsave("outputs/charts/balance_distribution.png", plot_balance_distribution, width = 8, height = 5, dpi = 150)
ggsave("outputs/charts/risk_matrix.png", plot_risk_matrix, width = 8, height = 5, dpi = 150)
ggsave("outputs/charts/monthly_pnl.png", plot_monthly_pnl, width = 8, height = 5, dpi = 150)


# ------------------------------------------------------------------------------
# SECTION 6: PURSUIT PREDICTION MODEL (debugged version)
# ------------------------------------------------------------------------------
# Before trusting this section: upload your 3 real datasets to data/raw/, run
# inspect_dataset() on each, and confirm CONFIG below matches the real columns.

inspect_dataset <- function(path, n_max = 5000) {
  df <- readr::read_csv(path, n_max = n_max, show_col_types = FALSE)
  cat("\n=====", path, "=====\n")
  cat("Columns:", paste(names(df), collapse = ", "), "\n")
  cat("Rows sampled:", nrow(df), "\n\n")
  print(dplyr::glimpse(df))
  invisible(df)
}

CONFIG <- list(
  bank_debt = list(
    path = "data/raw/bank_data.csv",
    id_col = "id", expected_recovery_col = "expected_recovery_amount",
    actual_recovery_col = "actual_recovery_amount", strategy_col = "recovery_strategy",
    age_col = "age", has_outcome = TRUE
  ),
  collections = list(
    path = "data/raw/banking_collections_dataset.csv",
    id_col = "Customer_ID", balance_col = "Outstanding_Amount", original_col = "Loan_Amount",
    risk_col = "Risk_Level", days_past_due_col = "Days_Past_Due",
    outcome_col = "Payment_Status", outcome_paid_values = c("Paid"), has_outcome = TRUE
  ),
  invoice_delay = list(
    path = "data/raw/Dataset.csv",
    id_col = "Cust_Num", amount_col = "Amount", delay_flag_col = "DelayFlag"
  )
)

standardize_bank_debt <- function(cfg) {
  df <- readr::read_csv(cfg$path, show_col_types = FALSE)
  tibble(Source = "bank_debt", Record_ID = as.character(df[[cfg$id_col]]),
         Outcome_Repaid = as.integer(df[[cfg$actual_recovery_col]] > 0),
         Balance_Amount = df[[cfg$expected_recovery_col]], Debt_Ratio = 1,
         Days_Past_Due = NA_real_, Risk_Flag = NA_integer_)
}

standardize_collections <- function(cfg) {
  df <- readr::read_csv(cfg$path, show_col_types = FALSE)
  outcome <- if (!is.null(cfg$outcome_col) && cfg$outcome_col %in% names(df)) {
    as.integer(df[[cfg$outcome_col]] %in% cfg$outcome_paid_values)
  } else NA_integer_
  tibble(Source = "collections", Record_ID = as.character(df[[cfg$id_col]]),
         Outcome_Repaid = outcome, Balance_Amount = df[[cfg$balance_col]],
         Debt_Ratio = df[[cfg$balance_col]] / pmax(df[[cfg$original_col]], 1),
         Days_Past_Due = df[[cfg$days_past_due_col]],
         Risk_Flag = as.integer(tolower(df[[cfg$risk_col]]) %in% c("high", "severe", "critical")))
}

# Days_Overdue_Delay isn't used as a feature here: it's very likely what
# DelayFlag (the label) was derived from — including it would leak the label
# back into training.
standardize_invoice_delay <- function(cfg) {
  df <- readr::read_csv(cfg$path, show_col_types = FALSE)
  tibble(
    Source = "invoice_delay",
    Record_ID = as.character(df[[cfg$id_col]]),
    Outcome_Repaid = as.integer(df[[cfg$delay_flag_col]] == 0),
    Balance_Amount = df[[cfg$amount_col]],
    Debt_Ratio = 1,
    Days_Past_Due = NA_real_,
    Risk_Flag = NA_integer_
  )
}

safe_standardize <- function(fn, cfg, label) {
  tryCatch(fn(cfg), error = function(e) {
    warning(glue("Could not standardize '{label}': {conditionMessage(e)}. Check CONFIG${label} against inspect_dataset() output."))
    NULL
  })
}

validate_modeling_data <- function(df) {
  issues <- c()
  if (nrow(df) == 0) issues <- c(issues, "No rows loaded — check CONFIG paths.")
  dupes <- df %>% group_by(Source, Record_ID) %>% filter(n() > 1)
  if (nrow(dupes) > 0) issues <- c(issues, glue("{nrow(dupes)} duplicate Record_ID(s) found within a source."))
  negative_balance <- df %>% filter(Balance_Amount < 0)
  if (nrow(negative_balance) > 0) issues <- c(issues, glue("{nrow(negative_balance)} row(s) with a negative Balance_Amount."))
  if (length(issues) > 0) warning(paste(issues, collapse = "\n"))
  else message("Validation passed: rows present, no duplicate IDs, no negative balances.")
  invisible(issues)
}

split_dataset <- function(df, train_frac = 0.70, val_frac = 0.15, seed = 42) {
  set.seed(seed)
  n <- nrow(df); idx <- sample(seq_len(n))
  train_end <- floor(train_frac * n); val_end <- floor((train_frac + val_frac) * n)
  list(train = df[idx[1:train_end], ], val = df[idx[(train_end + 1):val_end], ], test = df[idx[(val_end + 1):n], ])
}

evaluate_model <- function(model, data, threshold = 0.5, label = "set") {
  data <- data %>% filter(!is.na(Balance_Amount))
  pred_prob <- predict(model, newdata = data, type = "response")
  pred_class <- as.integer(pred_prob > threshold)
  actual <- data$Outcome_Repaid
  valid <- !is.na(pred_class) & !is.na(actual)
  pred_class <- pred_class[valid]; actual <- actual[valid]; pred_prob <- pred_prob[valid]

  accuracy <- mean(pred_class == actual)
  pos <- pred_prob[actual == 1]; neg <- pred_prob[actual == 0]
  auc <- if (length(pos) > 0 && length(neg) > 0) {
    mean(outer(pos, neg, ">")) + 0.5 * mean(outer(pos, neg, "=="))
  } else NA_real_

  cat(glue("--- {label} ---\n"))
  cat(glue("Accuracy: {round(accuracy, 3)}   AUC: {round(auc, 3)}\n"))
  cat("Confusion matrix:\n"); print(table(Predicted = pred_class, Actual = actual)); cat("\n")
  invisible(list(accuracy = accuracy, auc = auc))
}

# Run the model build (wrapped so a fresh clone without the 3 CSVs uploaded
# yet doesn't crash the whole script — it'll just skip to Section 7):
payment_model <- tryCatch({
  modeling_data <- bind_rows(
    safe_standardize(standardize_bank_debt, CONFIG$bank_debt, "bank_debt"),
    safe_standardize(standardize_collections, CONFIG$collections, "collections"),
    safe_standardize(standardize_invoice_delay, CONFIG$invoice_delay, "invoice_delay")
  )
  message(glue("Combined modeling table: {nrow(modeling_data)} rows from {n_distinct(modeling_data$Source)} source(s)."))
  validate_modeling_data(modeling_data)

  # bank_debt excluded: its derived outcome label has no variance (see README)
  labeled_data <- modeling_data %>% filter(!is.na(Outcome_Repaid), Source %in% c("collections", "invoice_delay"))
  message(glue("{nrow(labeled_data)} labeled rows across {n_distinct(labeled_data$Source)} source(s)."))

  splits <- split_dataset(labeled_data)
  message(glue("Train: {nrow(splits$train)} | Validation: {nrow(splits$val)} | Test: {nrow(splits$test)}"))

  # Balance_Amount + Debt_Ratio only: Risk_Flag/Days_Past_Due don't exist
  # across all training sources and caused ~97% row loss to missingness
  # when included (see README "Model performance" for the full story).
  model <- glm(
    Outcome_Repaid ~ Balance_Amount + Debt_Ratio,
    data = splits$train, family = binomial(link = "logit"), na.action = na.exclude
  )
  print(summary(model))
  evaluate_model(model, splits$val, label = "Validation")
  evaluate_model(model, splits$test, label = "Test")

  saveRDS(model, "models/payment_model.rds")
  message("Model saved to models/payment_model.rds")
  model
}, error = function(e) {
  message(glue("Section 6 skipped — {conditionMessage(e)}. Upload the 3 CSVs to data/raw/ to run this section."))
  NULL
})

predict_new_accounts <- function(new_csv_path, model) {
  new_data <- readr::read_csv(new_csv_path, show_col_types = FALSE)
  validate_schema(new_data, MASTER_LEDGER_SCHEMA, "New accounts file")
  scored <- new_data %>%
    mutate(
      Remaining_Balance = Original_Debt - Amount_Paid,
      Balance_Amount = Remaining_Balance,
      Debt_Ratio = Remaining_Balance / pmax(Original_Debt, 1),
      Days_Past_Due = as.integer(Sys.Date() - Billing_Month)
    )
  scored$Predicted_Payment_Probability <- predict(model, newdata = scored, type = "response")
  scored %>% arrange(desc(Predicted_Payment_Probability))
}

score_unified_ledger <- function(unified_ledger, model) {
  scoring_input <- unified_ledger %>%
    mutate(
      Balance_Amount = Remaining_Balance,
      Debt_Ratio = Remaining_Balance / pmax(Original_Debt, 1)
    )
  scoring_input$Predicted_Payment_Probability <- predict(model, newdata = scoring_input, type = "response")

  scoring_input %>%
    mutate(
      Expected_Recovery_Value = round(Predicted_Payment_Probability * Remaining_Balance, 2),
      Worth_Pursuing = case_when(
        !Critical_Alert ~ "Not Flagged",
        Predicted_Payment_Probability >= 0.6 ~ "High Priority",
        Predicted_Payment_Probability >= 0.3 ~ "Medium Priority",
        TRUE ~ "Low Priority - consider write-off"
      )
    ) %>%
    select(Debtor_ID, Debtor_Name, Remaining_Balance, Critical_Alert, Risk_Tier,
           Predicted_Payment_Probability, Expected_Recovery_Value, Worth_Pursuing) %>%
    arrange(desc(Expected_Recovery_Value))
}

if (!is.null(payment_model)) {
  pursuit_rankings <- score_unified_ledger(unified_ledger, payment_model)
  write_csv(pursuit_rankings, "outputs/pursuit_rankings.csv")
}


# ------------------------------------------------------------------------------
# SECTION 7: LLM CHAT LAYER
# ------------------------------------------------------------------------------
# Requires an API key set as an environment variable first, e.g.:
#   Sys.setenv(ANTHROPIC_API_KEY = "your-key-here")
# or swap call_llm() below for the OpenAI version if that's what you're using.

call_llm <- function(prompt, model = "claude-sonnet-5", max_tokens = 1000) {
  api_key <- Sys.getenv("ANTHROPIC_API_KEY")
  if (api_key == "") stop("Set Sys.setenv(ANTHROPIC_API_KEY = ...) first.")

  resp <- httr::POST(
    url = "https://api.anthropic.com/v1/messages",
    httr::add_headers(
      "x-api-key" = api_key,
      "anthropic-version" = "2023-06-01",
      "content-type" = "application/json"
    ),
    body = jsonlite::toJSON(list(
      model = model,
      max_tokens = max_tokens,
      messages = list(list(role = "user", content = prompt))
    ), auto_unbox = TRUE)
  )

  if (httr::status_code(resp) != 200) {
    stop(glue("API error {httr::status_code(resp)}: {httr::content(resp, 'text')}"))
  }

  parsed <- httr::content(resp, "parsed")
  parsed$content[[1]]$text
}

build_data_context <- function(question, data = unified_ledger) {
  id_match <- str_extract(question, "(?i)debtor[_\\s]?0*([0-9]+)")
  target_id <- if (!is.na(id_match)) as.integer(str_extract(id_match, "[0-9]+")) else NA_integer_

  if (!is.na(target_id) && target_id %in% data$Debtor_ID) {
    row <- data %>% filter(Debtor_ID == target_id)
    return(glue(
"Specific account detail:
{paste(capture.output(print(as.data.frame(row))), collapse = '\n')}"
    ))
  }

  if (str_detect(tolower(question), "flagged|critical|worth pursuing")) {
    data <- data %>% filter(Critical_Alert)
  }

  glue(
"Portfolio summary ({nrow(data)} accounts in scope):
- Critical Alert accounts: {sum(data$Critical_Alert)}
- Total outstanding balance: ${format(round(sum(data$Remaining_Balance), 2), big.mark=',')}
- Total net profit: ${format(round(sum(data$Net_Profit), 2), big.mark=',')}
- Risk tier breakdown: {paste(names(table(data$Risk_Tier)), table(data$Risk_Tier), sep=': ', collapse=', ')}
- Blacklisted accounts: {sum(data$Is_Blacklisted)}
- Accounts with external debts: {sum(data$Has_External_Debts)}"
  )
}

ask_data_llm <- function(question, data = unified_ledger) {
  context <- build_data_context(question, data)
  prompt <- glue(
"You are a financial risk analyst assistant. Answer using ONLY the data below.
Be concise and specific with numbers.

{context}

Question: {question}"
  )
  call_llm(prompt)
}

# Example usage once ANTHROPIC_API_KEY (or OPENAI_API_KEY, if you swapped
# call_llm) is set:
# cat(ask_data_llm("Which risk tier has the most exposure?"))
# cat(ask_data_llm("Tell me about Debtor_0006"))

message("Pipeline complete. See README.md for the full section-by-section explanation.")
