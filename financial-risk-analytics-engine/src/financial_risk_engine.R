   # ==============================================================================
# AUTOMATED FINANCIAL RISK ANALYTICS ENGINE & COMMUNICATION PIPELINE
# Built for Google Colab (R runtime)
# ==============================================================================
#
# HOW TO RUN IN GOOGLE COLAB:
#   1. Runtime > Change runtime type > select "R"
#   2. Paste this script into a cell (or upload it and source() it)
#   3. Run top to bottom. Package installs only happen once per session.
#
# This script is organized into clearly numbered sections so you can run it
# section-by-section while developing, or source() the whole thing in one go.
# ==============================================================================


# ------------------------------------------------------------------------------
# SECTION 1: SETUP & DEPENDENCIES
# ------------------------------------------------------------------------------

required_packages <- c("dplyr", "ggplot2", "tibble", "purrr", "glue",
                        "scales", "lubridate", "readr", "tidyr", "stringr")

new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(new_packages) > 0) {
  install.packages(new_packages, repos = "https://cloud.r-project.org")
}
invisible(lapply(required_packages, library, character.only = TRUE))

set.seed(42)  # reproducibility for simulated data


# ------------------------------------------------------------------------------
# SECTION 2: DATA ARCHITECTURE & SCHEMA CONTRACTS
# ------------------------------------------------------------------------------
# Defining the expected schema explicitly means that when you later swap in a
# real Kaggle dataset, validate_schema() will immediately tell you if a column
# is missing, misnamed, or of the wrong type -- instead of failing silently
# three steps downstream.

MASTER_LEDGER_SCHEMA <- list(
  Debtor_ID        = "integer",
  Debtor_Name      = "character",
  Billing_Month    = "Date",
  Original_Debt    = "numeric",
  Amount_Paid      = "numeric",
  Cost_To_Acquire  = "numeric"
)

RISK_REGISTRY_SCHEMA <- list(
  Debtor_ID           = "integer",
  Is_Blacklisted      = "logical",
  Has_External_Debts  = "logical"
)

#' Validate a data frame against an expected schema
#' @param df data frame to check
#' @param schema named list of column_name -> expected R class
#' @param df_name label used in error messages
validate_schema <- function(df, schema, df_name = "dataset") {
  missing_cols <- setdiff(names(schema), names(df))
  if (length(missing_cols) > 0) {
    stop(glue("[{df_name}] Missing required columns: {paste(missing_cols, collapse = ', ')}"))
  }

  problems <- c()
  for (col in names(schema)) {
    expected <- schema[[col]]
    actual_class <- class(df[[col]])[1]
    # allow integer/numeric interchangeably, and Date checked separately
    ok <- (actual_class == expected) ||
      (expected == "numeric" && actual_class %in% c("numeric", "integer")) ||
      (expected == "integer" && actual_class %in% c("numeric", "integer"))
    if (!ok) {
      problems <- c(problems, glue("  - {col}: expected {expected}, got {actual_class}"))
    }
  }
  if (length(problems) > 0) {
    stop(glue("[{df_name}] Schema type mismatches:\n{paste(problems, collapse = '\n')}"))
  }
  message(glue("[{df_name}] Schema OK ({nrow(df)} rows, {ncol(df)} cols)"))
  invisible(TRUE)
}

#' Load and validate a real Kaggle CSV against a schema, with light coercion
#' Use this once you swap simulated data for a real Kaggle dataset.
load_and_validate_csv <- function(path, schema, df_name = "dataset", date_cols = character(0)) {
  df <- readr::read_csv(path, show_col_types = FALSE)
  for (dc in date_cols) {
    if (dc %in% names(df)) df[[dc]] <- as.Date(df[[dc]])
  }
  validate_schema(df, schema, df_name)
  df
}


# ------------------------------------------------------------------------------
# SECTION 3: DATA SIMULATION (swap out for real Kaggle CSVs later)
# ------------------------------------------------------------------------------
# Replace this whole section with:
#   master_ledger <- load_and_validate_csv("master_ledger.csv", MASTER_LEDGER_SCHEMA,
#                                           "Master Ledger", date_cols = "Billing_Month")
#   external_risk_registry <- load_and_validate_csv("risk_registry.csv", RISK_REGISTRY_SCHEMA,
#                                                     "External Risk Registry")

simulate_master_ledger <- function(n = 250) {
  original_debt <- round(runif(n, 500, 12000), 2)
  # payment ratio skewed so a realistic chunk of accounts are under-paid
  payment_ratio <- rbeta(n, 2, 3)

  tibble(
    Debtor_ID       = 1:n,
    Debtor_Name     = paste0("Debtor_", str_pad(1:n, 4, pad = "0")),
    Billing_Month   = sample(
      seq(as.Date("2025-01-01"), as.Date("2025-12-01"), by = "month"),
      n, replace = TRUE
    ),
    Original_Debt   = original_debt,
    Amount_Paid     = round(pmin(original_debt, original_debt * payment_ratio), 2),
    Cost_To_Acquire = round(runif(n, 40, 450), 2)
  )
}

simulate_risk_registry <- function(n = 250) {
  tibble(
    Debtor_ID          = 1:n,
    Is_Blacklisted     = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.14, 0.86)),
    Has_External_Debts = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.22, 0.78))
  )
}

master_ledger          <- simulate_master_ledger(250)
external_risk_registry <- simulate_risk_registry(250)

validate_schema(master_ledger, MASTER_LEDGER_SCHEMA, "Master Ledger")
validate_schema(external_risk_registry, RISK_REGISTRY_SCHEMA, "External Risk Registry")


# ------------------------------------------------------------------------------
# SECTION 4: MERGE INTO UNIFIED VIEW
# ------------------------------------------------------------------------------

unified_ledger <- master_ledger %>%
  left_join(external_risk_registry, by = "Debtor_ID")

stopifnot(nrow(unified_ledger) == nrow(master_ledger))  # sanity check: no row explosion


# ------------------------------------------------------------------------------
# SECTION 5: FINANCIAL & RISK COMPUTATIONS
# ------------------------------------------------------------------------------

unified_ledger <- unified_ledger %>%
  mutate(
    Remaining_Balance = round(Original_Debt - Amount_Paid, 2),
    Net_Profit         = round(Amount_Paid - Cost_To_Acquire, 2),
    Days_Past_Due      = as.integer(Sys.Date() - Billing_Month),

    # Composite risk rule:
    #   active balance AND (blacklisted OR has external debts)
    Critical_Alert = Remaining_Balance > 0 & (Is_Blacklisted | Has_External_Debts),

    Risk_Tier = case_when(
      Critical_Alert & Remaining_Balance > 5000 ~ "Severe",
      Critical_Alert                            ~ "Critical",
      Remaining_Balance > 0                     ~ "Watch",
      TRUE                                       ~ "Clear"
    )
  )

message(glue(
  "Flagged {sum(unified_ledger$Critical_Alert)} of {nrow(unified_ledger)} accounts as Critical Alert."
))


# ------------------------------------------------------------------------------
# SECTION 6: OUTBOUND NOTIFICATION PIPELINE (drafting only — no send step)
# ------------------------------------------------------------------------------
# IMPORTANT: This section DRAFTS message content as R strings/data frames.
# It intentionally does NOT include an actual email/SMS sending integration.
# To go live, connect the drafts below to a transactional provider under your
# own account (e.g. blastula + your SMTP creds for email, or a provider like
# Twilio's REST API for SMS) once you've reviewed the message content and your
# jurisdiction's debt-collection communication rules.

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

This account has been escalated because it remains unpaid and additional
risk factors are present on file. To avoid further collection action,
possible credit rating impact, or referral to a third-party recovery
agency, please settle this balance or contact us to arrange a payment
plan within 7 days of this notice.

Please remit payment or contact our accounts team immediately to resolve
this matter.

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
    # Fallback to a shorter template if names/amounts push it over the SMS limit
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
    Email_Draft = pmap_chr(critical_accounts, function(...) {
      row <- tibble(...)
      generate_email_draft(row)
    }),
    SMS_Draft = pmap_chr(critical_accounts, function(...) {
      row <- tibble(...)
      generate_sms_draft(row)
    }),
    SMS_Char_Count = nchar(SMS_Draft)
  )

# Preview the first flagged account's drafts
if (nrow(notification_queue) > 0) {
  cat("----- SAMPLE EMAIL DRAFT -----\n")
  cat(notification_queue$Email_Draft[1], "\n\n")
  cat("----- SAMPLE SMS DRAFT (", notification_queue$SMS_Char_Count[1], "chars) -----\n")
  cat(notification_queue$SMS_Draft[1], "\n")
}

# Export the full queue for review / handoff to a sending system
write_csv(notification_queue, "notification_queue.csv")


# ------------------------------------------------------------------------------
# SECTION 7: VISUALIZATIONS
# ------------------------------------------------------------------------------

theme_risk <- theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

# 7a. Remaining balance distribution, split by Critical Alert status
plot_balance_distribution <- ggplot(unified_ledger, aes(x = Remaining_Balance, fill = Critical_Alert)) +
  geom_histogram(bins = 30, alpha = 0.85, position = "identity") +
  scale_fill_manual(values = c("FALSE" = "#4C9F70", "TRUE" = "#D64545"),
                     labels = c("Standard", "Critical Alert")) +
  scale_x_continuous(labels = scales::dollar_format()) +
  labs(
    title = "Distribution of Remaining Balances",
    subtitle = "Critical Alert accounts highlighted in red",
    x = "Remaining Balance", y = "Number of Accounts", fill = "Status"
  ) +
  theme_risk

# 7b. Risk matrix: Remaining Balance vs Days Past Due, colored by Risk_Tier
plot_risk_matrix <- ggplot(unified_ledger, aes(x = Days_Past_Due, y = Remaining_Balance, color = Risk_Tier)) +
  geom_point(alpha = 0.75, size = 2.4) +
  scale_color_manual(values = c(
    "Clear" = "#4C9F70", "Watch" = "#E8B339",
    "Critical" = "#E06C3B", "Severe" = "#B5251F"
  )) +
  scale_y_continuous(labels = scales::dollar_format()) +
  labs(
    title = "Risk Matrix: Balance vs. Days Past Due",
    x = "Days Past Due", y = "Remaining Balance", color = "Risk Tier"
  ) +
  theme_risk

# 7c. Monthly profit vs loss (net profit aggregated by billing month)
monthly_pnl <- unified_ledger %>%
  group_by(Billing_Month) %>%
  summarise(Total_Net_Profit = sum(Net_Profit), .groups = "drop") %>%
  mutate(Result = ifelse(Total_Net_Profit >= 0, "Profit", "Loss"))

plot_monthly_pnl <- ggplot(monthly_pnl, aes(x = Billing_Month, y = Total_Net_Profit, fill = Result)) +
  geom_col() +
  geom_hline(yintercept = 0, color = "grey30") +
  scale_fill_manual(values = c("Profit" = "#4C9F70", "Loss" = "#B5251F")) +
  scale_y_continuous(labels = scales::dollar_format()) +
  labs(
    title = "Monthly Net Profit vs. Loss",
    subtitle = "Amount Paid minus Cost to Acquire, aggregated by billing month",
    x = "Billing Month", y = "Net Profit"
  ) +
  theme_risk

# Display all three (in Colab these render inline automatically)
print(plot_balance_distribution)
print(plot_risk_matrix)
print(plot_monthly_pnl)

# Save to disk for the report / hand-off deck
ggsave("plot_balance_distribution.png", plot_balance_distribution, width = 8, height = 5, dpi = 150)
ggsave("plot_risk_matrix.png", plot_risk_matrix, width = 8, height = 5, dpi = 150)
ggsave("plot_monthly_pnl.png", plot_monthly_pnl, width = 8, height = 5, dpi = 150)


# ------------------------------------------------------------------------------
# SECTION 8: NATURAL-LANGUAGE QUERY LAYER
# ------------------------------------------------------------------------------
# Two options are provided:
#
# OPTION A — 'chattr' (real LLM-backed RAG over this data frame)
#   Requires an LLM backend (e.g. OpenAI, or Anthropic via a compatible
#   provider) and an API key set as an environment variable. Uncomment and
#   configure once you have credentials available in your Colab session.
#
# install.packages("chattr")
# library(chattr)
# Sys.setenv(OPENAI_API_KEY = "your-key-here")   # or use chattr's other providers
# chattr::chattr_app(
#   provider = "openai",
#   model    = "gpt-4o-mini"
# )
# # Then, inside the chat UI, point it at `unified_ledger` as context, e.g.:
# # "Using the unified_ledger data frame, summarize total exposure by Risk_Tier"
#
# OPTION B — lightweight offline fallback (no API key needed)
#   A simple keyword-routed summarizer so you have *something* interactive
#   working even before chattr/API access is set up. Not real NLU — just
#   pattern matches on common analyst questions.

ask_data <- function(question, data = unified_ledger) {
  q <- tolower(question)

  if (str_detect(q, "critical|flagged|alert")) {
    n <- sum(data$Critical_Alert)
    total_exposure <- sum(data$Remaining_Balance[data$Critical_Alert])
    return(glue(
      "{n} accounts are flagged Critical Alert, totaling ${format(round(total_exposure,2), big.mark=',')} in outstanding balance."
    ))
  }

  if (str_detect(q, "profit|loss")) {
    total <- sum(data$Net_Profit)
    verdict <- ifelse(total >= 0, "net profit", "net loss")
    return(glue("Overall the portfolio shows a {verdict} of ${format(abs(round(total,2)), big.mark=',')}."))
  }

  if (str_detect(q, "blacklist")) {
    n <- sum(data$Is_Blacklisted)
    return(glue("{n} of {nrow(data)} debtors are marked as blacklisted."))
  }

  if (str_detect(q, "top|largest|biggest")) {
    top <- data %>% arrange(desc(Remaining_Balance)) %>% slice_head(n = 5) %>%
      select(Debtor_ID, Debtor_Name, Remaining_Balance)
    return(paste0("Top 5 balances:\n", paste(capture.output(print(top)), collapse = "\n")))
  }

  "I can currently answer questions about: critical/flagged accounts, profit/loss, blacklist counts, and top balances. For open-ended natural language queries, connect the chattr block above to an LLM provider."
}

# Example usage:
cat(ask_data("How many accounts are critical?"), "\n")
cat(ask_data("What's our profit or loss?"), "\n")


# ------------------------------------------------------------------------------
# SECTION 9: EXPORT SUMMARY ARTIFACTS
# ------------------------------------------------------------------------------

write_csv(unified_ledger, "unified_ledger.csv")

portfolio_summary <- unified_ledger %>%
  summarise(
    Total_Accounts       = n(),
    Total_Critical_Alerts = sum(Critical_Alert),
    Total_Outstanding    = sum(Remaining_Balance),
    Total_Net_Profit     = sum(Net_Profit)
  )
print(portfolio_summary)
write_csv(portfolio_summary, "portfolio_summary.csv")

message("Pipeline complete. Files written: unified_ledger.csv, notification_queue.csv, portfolio_summary.csv, 3 PNG charts.")
