test_that("no exact duplicate rows exist in a clean modeling table", {
  clean_data <- tibble::tibble(
    Source = c("collections", "collections", "invoice_delay"),
    Record_ID = c("1", "2", "3"),
    Balance_Amount = c(100, 200, 300)
  )
  exact_dupes <- clean_data[duplicated(clean_data) | duplicated(clean_data, fromLast = TRUE), ]
  expect_equal(nrow(exact_dupes), 0)
})

test_that("exact duplicate rows are correctly detected when present", {
  dirty_data <- tibble::tibble(
    Source = c("collections", "collections", "collections"),
    Record_ID = c("1", "1", "2"),
    Balance_Amount = c(100, 100, 200)  # first two rows are genuinely identical
  )
  exact_dupes <- dirty_data[duplicated(dirty_data) | duplicated(dirty_data, fromLast = TRUE), ]
  expect_equal(nrow(exact_dupes), 2)  # both copies of the duplicate pair
})

test_that("a repeated Record_ID with different data is NOT flagged as a duplicate", {
  # This is the actual lesson from tonight's investigation: a repeated
  # Record_ID (the same Cust_Num appearing in thousands of separate
  # invoice rows) is normal, expected data for an invoice-level dataset --
  # only genuinely identical rows should ever be flagged.
  invoice_style_data <- tibble::tibble(
    Source = c("invoice_delay", "invoice_delay"),
    Record_ID = c("5039221090", "5039221090"),  # same customer...
    Balance_Amount = c(150.25, 89.10)             # ...two different invoices
  )
  exact_dupes <- invoice_style_data[duplicated(invoice_style_data) | duplicated(invoice_style_data, fromLast = TRUE), ]
  expect_equal(nrow(exact_dupes), 0)
})