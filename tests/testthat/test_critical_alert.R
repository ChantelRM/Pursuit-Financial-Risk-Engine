test_that("zero balance is never Critical_Alert, even when blacklisted and has external debts", {
  # This is the manufactured test row from Issue 10, made permanent here
  # instead of being something you have to remember to re-run by hand.
  result <- compute_critical_alert(
    remaining_balance = 0, is_blacklisted = TRUE, has_external_debts = TRUE
  )
  expect_false(result)
})

test_that("a positive balance with no risk factors is not Critical_Alert", {
  result <- compute_critical_alert(
    remaining_balance = 5000, is_blacklisted = FALSE, has_external_debts = FALSE
  )
  expect_false(result)
})

test_that("a positive balance with a blacklist flag IS Critical_Alert", {
  result <- compute_critical_alert(
    remaining_balance = 5000, is_blacklisted = TRUE, has_external_debts = FALSE
  )
  expect_true(result)
})

test_that("a positive balance with external debts (no blacklist) IS Critical_Alert", {
  result <- compute_critical_alert(
    remaining_balance = 5000, is_blacklisted = FALSE, has_external_debts = TRUE
  )
  expect_true(result)
})

test_that("a negative balance (e.g. overpayment) is never Critical_Alert", {
  result <- compute_critical_alert(
    remaining_balance = -100, is_blacklisted = TRUE, has_external_debts = TRUE
  )
  expect_false(result)
})

test_that("compute_critical_alert is vectorized correctly for a whole column at once", {
  # Confirms the function works the way it's actually called in the real
  # pipeline -- inside mutate(), against full columns, not just one value
  # at a time.
  result <- compute_critical_alert(
    remaining_balance = c(0, 100, 100, -50),
    is_blacklisted = c(TRUE, FALSE, TRUE, TRUE),
    has_external_debts = c(TRUE, FALSE, FALSE, TRUE)
  )
  expect_equal(result, c(FALSE, FALSE, TRUE, FALSE))
})