library(glue)

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
  invisible(TRUE)
}

load_and_validate_csv <- function(path, schema, df_name = "dataset", date_cols = character(0)) {
  df <- readr::read_csv(path, show_col_types = FALSE)
  for (dc in date_cols) if (dc %in% names(df)) df[[dc]] <- as.Date(df[[dc]])
  validate_schema(df, schema, df_name)
  df
}

compute_critical_alert <- function(remaining_balance, is_blacklisted, has_external_debts) {
  remaining_balance > 0 & (is_blacklisted | has_external_debts)
}

LOG_FILE <- "logs/pipeline_run.log"

log_message <- function(level, msg, console = FALSE) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  calls <- sys.calls()
  depth <- length(calls)
  if (depth >= 3) {
    caller_call <- calls[[depth - 2]]
    fn_name <- as.character(caller_call[[1]])[1]
  } else {
    fn_name <- "global"
  }
  if (fn_name %in% c("eval", "eval.parent")) fn_name <- "global"

  log_line <- sprintf("%s [%s] %s: %s", timestamp, level, fn_name, msg)

  if (dir.exists(dirname(LOG_FILE))) {
    cat(log_line, "\n", file = LOG_FILE, append = TRUE)
  }
  if (console) cat(log_line, "\n")
}

log_info <- function(msg, console = FALSE) {
  log_message("INFO", msg, console = console)
}

log_warn <- function(msg, console = TRUE) {
  log_message("WARN", msg, console = console)
}

log_error <- function(msg, console = TRUE) {
  log_message("ERROR", msg, console = console)
}