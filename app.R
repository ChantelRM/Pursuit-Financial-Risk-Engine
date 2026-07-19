# ==============================================================================
# PURSUIT DASHBOARD — Shiny app with a querychat sidebar
#
# This is a DIFFERENT runtime from the Colab notebook — it's a live Shiny app,
# not a notebook cell. Easiest way to run it: posit.cloud (free), new RStudio
# project, paste this in as app.R, click "Run App". Local RStudio works too.
#
# SETUP (run once, in the R console):
#   install.packages("pak")
#   pak::pak(c("shiny", "bslib", "DBI", "duckdb", "dplyr", "readr",
#              "reactable", "ggplot2", "scales", "querychat", "shinychat"))
#
# API KEY: querychat defaults to OpenAI (ellmer::chat_openai()), which lines
# up with the credits you've already got. Set it as an environment variable
# before running — in Posit Cloud, use the same idea as Colab's Secrets: a
# per-project .Renviron file (Posit Cloud persists this, unlike Colab):
#   OPENAI_API_KEY=your-key-here
# Then Session > Restart R so it picks it up.
# ==============================================================================

library(shiny)
library(bslib)
library(shinychat)
library(querychat)
library(DBI)
library(duckdb)
library(dplyr)
library(reactable)
library(ggplot2)
library(scales)

# ------------------------------------------------------------------------------
# DATA — swap this path for wherever your notebook actually wrote
# unified_ledger.csv (Section 3's write_csv() output)
# ------------------------------------------------------------------------------
unified_ledger <- readr::read_csv("data/unified_ledger.csv", show_col_types = FALSE)

# Convert dollar-scale synthetic data to approximate Rand equivalents.
# Rate is approximate (~16.5 as of writing) — update periodically, it fluctuates.
USD_TO_ZAR <- 16.5
unified_ledger <- unified_ledger %>%
  mutate(
    Original_Debt = Original_Debt * USD_TO_ZAR,
    Amount_Paid = Amount_Paid * USD_TO_ZAR,
    Cost_To_Acquire = Cost_To_Acquire * USD_TO_ZAR,
    Remaining_Balance = Remaining_Balance * USD_TO_ZAR,
    Net_Profit = Net_Profit * USD_TO_ZAR
  )

# querychat runs generated SQL against a real database (DuckDB), not the LLM
# itself — only the schema/column descriptions go to the LLM, never the raw
# rows. Worth keeping this line for your README's privacy note.
conn <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(conn, "ledger", unified_ledger, overwrite = TRUE)

# ------------------------------------------------------------------------------
# QUERYCHAT SETUP
# ------------------------------------------------------------------------------
qc <- querychat::QueryChat$new(
  conn,
  table_name = "ledger",
  greeting = paste(
    "Ask me about the portfolio — for example:",
    "\"Show only Critical Alert accounts with balance over 5000\"",
    "\"Sort by Remaining_Balance descending\"",
    "\"What's the total outstanding balance for the Severe risk tier?\"",
    sep = "\n"
  ),
  data_description = "
    `ledger` is the merged debtor risk table (Master Ledger + External Risk
    Registry, already joined). Columns:
    - Debtor_ID, Debtor_Name
    - Original_Debt, Amount_Paid, Remaining_Balance, Net_Profit (dollar amounts)
    - Is_Blacklisted, Has_External_Debts (booleans)
    - Critical_Alert (boolean) — TRUE means an active balance AND
      (blacklisted OR has external debts)
    - Risk_Tier — one of Clear, Watch, Critical, Severe
    - Days_Past_Due (integer)
  "
)

# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------
ui <- page_sidebar(
  title = tags$span("Pursuit — Debtor Risk Dashboard", class = "dashboard-title"),  theme = bslib::bs_theme(
    version = 5,
    base_font = font_google("Poppins"),
    primary = "#2563EB", secondary = "#6D28D9", success = "#10B981",
    warning = "#FBBF24", danger = "#EF4444"
  ),
  tags$head(tags$style(HTML("
  body { background-color: #ffffff !important; }
  .dashboard-title {
    text-transform: uppercase;
    font-weight: 900;
    color: #000000;
    letter-spacing: 0.5px;
  }
  .card-header {
    text-transform : uppercase;
    color: #000000;
    font-weight: 600;
  }
  .card {
    border: none !important;
    box-shadow: none !important;
  }
  .bslib-value-box {
  padding: 0.6rem 1rem !important;
  min-height: auto !important;
  min-width: 150px;
  box-shadow: 0 5px 15px rgba(60,60,60, 0.35) !important;
}
.bslib-value-box .value-box-title {
  font-size: 0.9rem !important;
  white-space: normal;
}
.bslib-value-box .value-box-value {
  font-size: 1.4rem !important;
}
  .vb-red { border-color: #EF4444 !important; }
  .vb-red #total_outstanding { color: #EF4444 !important; font-weight: 600; }
  .vb-green { border-color: #10B981 !important; }
  .vb-green #total_profit { color: #10B981 !important; font-weight: 600; }
  div.shiny-chat-input { 
    border: none !important; 
    fill: #6D28D9 !important;
  }
  shiny-chat-container {
  font-size: 0.85rem;
}
  div.shiny-chat-input textarea {
    border: 1px solid #6D28D9 !important;
    border-radius: 15px !important;
    border-shadow: 0 2px 6px rgba(109, 40, 217, 0.7);
  }
  .shiny-chat-btn-send svg.bi-arrow-up-circle-fill {
    fill: #6D28D9 !important;
    color: #6D28D9 !important;
  }
  .shiny-chat-user-message{
    # background-color: #9333EA !important;
    background-color: rgba(109, 40, 217, 0.8) !important;
    color: white !important;
    border-radius: 15px !important;
    font-style: italic !important;
  }
  .accounts-chart-row .bslib-grid{
    align-items: start;
  }
  @media (max-width: 900px) {
  .accounts-chart-row .bslib-grid {
    grid-template-columns: 1fr !important;
  }
}
"))),
  sidebar = qc$sidebar(width = 300),
  
  layout_columns(
    fill = FALSE,
    value_box(title = "Total Accounts", value = textOutput("total_accounts")),
    value_box(title = "Critical Alerts", value = textOutput("critical_alerts")),
    value_box(title = "Total Outstanding", value = textOutput("total_outstanding"), class = "vb-red"),
    value_box(title = "Total Net Profit", value = textOutput("total_profit"), class = "vb-green")
  ),
  
  div(class = "accounts-chart-row",
      layout_columns(
        col_widths = c(7, 5),
        card(
          card_header("Accounts"),
          reactableOutput("accounts_table")
        ),
        card(
          card_header("Remaining Balance Distribution"),
          plotOutput("balance_dist", height= "300px")
        )
      )
  )
)

# SERVER
# ------------------------------------------------------------------------------
server <- function(input, output, session) {
  qc_vals <- qc$server()

  # This is the reactive, LLM-filtered version of the ledger — it updates
  # automatically whenever the chat sidebar changes the active filter/sort
  filtered_data <- reactive({
    df <- qc_vals$df()
    req(df)
    df
  })

  output$total_accounts <- renderText({
    format(nrow(filtered_data()), big.mark = ",")
  })

  output$critical_alerts <- renderText({
    format(sum(filtered_data()$Critical_Alert, na.rm = TRUE), big.mark = ",")
  })

  output$total_outstanding <- renderText({
    scales::dollar(sum(filtered_data()$Remaining_Balance, na.rm = TRUE), prefix = "R", big.mark = ",")
  })
  
  output$total_profit <- renderText({
    scales::dollar(sum(filtered_data()$Net_Profit, na.rm = TRUE), prefix = "R", big.mark = ",")
  })

  output$accounts_table <- renderReactable({
    reactable(
      filtered_data(),
      searchable = TRUE,
      sortable = TRUE,
      defaultPageSize = 10,
      theme = reactableTheme(
        style = list(fontSize= "0.70rem"),
        searchInputStyle = list(
          color = "#6D28D9",
          borderColor = "#6D28D9",
          borderWidth = "1px",
          borderStyle = "solid",
          borderRadius = "15px",
          boxShadow = "0 2px 6px rgba(109, 40, 217, 0.7)"
        )
      ),
      columns = list(
        Remaining_Balance = colDef(format = colFormat(prefix = "R ", separators = TRUE, digits = 2)),
        Net_Profit        = colDef(format = colFormat(prefix = "R ", separators = TRUE, digits = 2))
      )
    )
  })
  output$balance_dist <- renderPlot({
    ggplot(filtered_data(), aes(x = Remaining_Balance, fill = Critical_Alert)) +
      geom_histogram(bins = 30, alpha = 0.85, position = "identity") +
      scale_fill_manual(values = c("FALSE" = "#10B981", "TRUE" = "#EF4444"),
                        labels = c("Standard", "Critical Alert")) +
      scale_x_continuous(labels = scales::dollar_format(prefix = "R", big.mark = ",")) +
      labs(x = "Remaining Balance", y = "Accounts", fill = "Status") +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui, server)
