test_that("validate_schema passes for a correctly-shaped Master Ledger", {
  good_data <- tibble::tibble(
    Debtor_ID = 1L, Debtor_Name = "Test Debtor", Billing_Month = as.Date("2025-01-01"),
    Original_Debt = 1000, Amount_Paid = 500, Cost_To_Acquire = 50
  )
  expect_silent(validate_schema(good_data, MASTER_LEDGER_SCHEMA, "test"))
})

test_that("validate_schema errors on a missing column", {
  bad_data <- tibble::tibble(
    Debtor_ID = 1L, Debtor_Name = "Test Debtor"
    # missing Billing_Month, Original_Debt, Amount_Paid, Cost_To_Acquire
  )
  expect_error(
    validate_schema(bad_data, MASTER_LEDGER_SCHEMA, "test"),
    "Missing required columns"
  )
})

test_that("validate_schema errors on a wrong column type", {
  bad_type_data <- tibble::tibble(
    Debtor_ID = "not-a-number",  # should be integer
    Debtor_Name = "Test Debtor", Billing_Month = as.Date("2025-01-01"),
    Original_Debt = 1000, Amount_Paid = 500, Cost_To_Acquire = 50
  )
  expect_error(
    validate_schema(bad_type_data, MASTER_LEDGER_SCHEMA, "test"),
    "Schema mismatches"
  )
})

test_that("validate_schema treats numeric/integer as interchangeable", {
  # Original_Debt etc are declared "numeric" in the schema, but a plain
  # integer column should still pass -- mirrors real behavior seen with
  # simulated data, which sometimes produces integers where doubles were
  # expected.
  flexible_data <- tibble::tibble(
    Debtor_ID = 1L, Debtor_Name = "Test Debtor", Billing_Month = as.Date("2025-01-01"),
    Original_Debt = 1000L, Amount_Paid = 500L, Cost_To_Acquire = 50L
  )
  expect_silent(validate_schema(flexible_data, MASTER_LEDGER_SCHEMA, "test"))
})

test_that("validate_schema works on the External Risk Registry schema too", {
  good_registry <- tibble::tibble(
    Debtor_ID = 1L, Is_Blacklisted = TRUE, Has_External_Debts = FALSE
  )
  expect_silent(validate_schema(good_registry, RISK_REGISTRY_SCHEMA, "test"))
})