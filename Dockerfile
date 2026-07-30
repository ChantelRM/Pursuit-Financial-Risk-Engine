# ==============================================================================
# DOCKERFILE SCAFFOLD FOR PURSUIT DASHBOARD
# This is a guide, not a solution -- fill in each section yourself.
# Delete these comments as you go, or keep them if you want the reasoning
# documented for whoever reads this file later (including future you).
# ==============================================================================

# ------------------------------------------------------------------------------
# STEP 1: BASE IMAGE
# ------------------------------------------------------------------------------
# Every Dockerfile starts with FROM <image>.
# Research: "rocker/shiny" on Docker Hub -- it's a pre-built image that
# already has R + Shiny Server installed, so you're not installing R from
# scratch. Check what R version it ships with, and whether that matters for
# any package you're using.
#
# FROM <your base image here>


# ------------------------------------------------------------------------------
# STEP 2: SYSTEM-LEVEL DEPENDENCIES (if needed)
# ------------------------------------------------------------------------------
# Some R packages need system libraries to compile (this is the same reason
# `apt-get install r-cran-httr` needed extra libcurl/openssl packages back
# when you were setting up the sandbox earlier in this project -- R packages
# with C/C++ dependencies need those dependencies present at the OS level).
# Check whether duckdb, DBI, httr, or curl need anything like libcurl4,
# libssl-dev, or similar, and whether the base image already includes them.
#
# RUN apt-get update && apt-get install -y <anything you find you need>


# ------------------------------------------------------------------------------
# STEP 3: INSTALL R PACKAGES
# ------------------------------------------------------------------------------
# Your app.R has a specific list of libraries it loads at the top --
# shiny, bslib, shinychat, querychat, DBI, duckdb, dplyr, reactable,
# ggplot2, scales, plus readr (used inside a function even without an
# explicit library() call).
#
# Research: install.packages() vs a package manager like pak -- pak can
# install several packages in parallel, which matters for build time.
# Also worth checking: does rocker/shiny already include any of these?
# No point reinstalling something that's already there.
#
# RUN R -e "install.packages(c(<your package list here>))"


# ------------------------------------------------------------------------------
# STEP 4: COPY YOUR APP FILES IN
# ------------------------------------------------------------------------------
# The container needs its own copy of app.R and your data -- it can't see
# your local filesystem. Think about:
#   - What directory structure does app.R expect? (it reads
#     "data/unified_ledger.csv" as a relative path -- where does that
#     path need to exist INSIDE the container for that to still work?)
#   - Do you copy the whole project folder, or just what's needed?
#
# COPY <source on your machine> <destination inside the container>


# ------------------------------------------------------------------------------
# STEP 5: EXPOSE THE PORT
# ------------------------------------------------------------------------------
# Shiny apps serve on a specific default port -- look this up (hint: it's
# a 4-digit number, commonly associated with Shiny Server specifically,
# not just "any R process"). EXPOSE documents which port the container
# listens on -- it doesn't publish it to your host machine by itself,
# that happens later when you actually run the container.
#
# EXPOSE <port>


# ------------------------------------------------------------------------------
# STEP 6: STARTUP COMMAND
# ------------------------------------------------------------------------------
# What command actually launches your Shiny app when the container starts?
# Research the difference between CMD and ENTRYPOINT while you're at it --
# worth understanding which one fits here and why, not just picking one.
#
# CMD ["<your startup command here>"]


# ==============================================================================
# ONCE WRITTEN, TEST WITH:
#   docker build -t pursuit-dashboard .
#   docker run -p <host port>:<container port> pursuit-dashboard
# Then check localhost at whatever host port you chose, in a browser.
#
# If the build fails, read the error from the top -- it'll usually name
# the exact line and package that failed, same as R's own error messages
# have all night.
# ==============================================================================