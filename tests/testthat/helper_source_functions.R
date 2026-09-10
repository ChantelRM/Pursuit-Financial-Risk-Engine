# testthat auto-runs any file starting with "helper-" before the actual
# tests, and keeps it loaded for all of them. This sources the REAL
# functions from R/functions.R -- not a copy -- so a test failure means
# the actual pipeline logic is broken, not a stale duplicate of it.
#
# testthat::test_dir() temporarily changes the working directory to the
# test folder itself while tests run, so this path goes up two levels
# (tests/testthat -> tests -> project root) rather than assuming the
# project root is already the working directory.
source(file.path("..", "..", "R", "functions.R"))