# ==============================================================================
# PURSUIT DASHBOARD
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
# DATA
# ------------------------------------------------------------------------------
unified_ledger <- readr::read_csv("data/unified_ledger.csv", show_col_types = FALSE)

conn <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(conn, "ledger", unified_ledger, overwrite = TRUE)

qc <- querychat::QueryChat$new(
  conn,
  table_name = "ledger",
  client="anthropic/claude-sonnet-4-5",
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
    - Original_Debt, Amount_Paid, Remaining_Balance, Net_Profit (Rand amounts)
    - Is_Blacklisted, Has_External_Debts (booleans)
    - Critical_Alert (boolean) — TRUE means an active balance AND
      (blacklisted OR has external debts)
    - Risk_Tier — one of Clear, Watch, Critical, Severe
    - Days_Past_Due (integer)
  "
)

# ------------------------------------------------------------------------------
# SHARED HELPERS
# ------------------------------------------------------------------------------
styled_accounts_table <- function(data, page_size = 10, dark = FALSE) {
  
  if (dark) {
    table_color <- "#E2E8F0"
    table_bg <- "#1E293B"
    table_border <- "#334155"
    search_color <- "#E5E7EB"
    search_bg <- "#0B1424"
  } else {
    table_color <- "#1E293B"
    table_bg <- "#FFFFFF"
    table_border <- "#E2E8F0"
    search_color <- "#6D28D9"
    search_bg <- "#FFFFFF"
  }
  
  reactable(
    data,
    searchable = TRUE,
    sortable = TRUE,
    defaultPageSize = page_size,
    rowStyle = function(index) {
      tier <- data$Risk_Tier[index]
      if (tier == "Severe") {
        if (dark) {
          return(list(backgroundColor = "#7F1D1D"))
        } else {
          return(list(backgroundColor = "#FFC7CE"))
        }
      } else if (tier == "Critical") {
        if (dark) {
          return(list(backgroundColor = "#78350F"))
        } else {
          return(list(backgroundColor = "#FFEB9C"))
        }
      }
    },
    theme = reactableTheme(
      style = list(fontSize = "0.75rem"),
      color = table_color,
      backgroundColor = table_bg,
      borderColor = table_border,
      searchInputStyle = list(
        color = search_color,
        backgroundColor = search_bg,
        borderColor = "#8B5CF6",
        borderWidth = "1px",
        borderStyle = "solid",
        borderRadius = "15px",
        boxShadow = "0 0 8px rgba(139, 92, 246, 0.35)"
      )
    ),
    columns = list(
      Original_Debt = colDef(format = colFormat(prefix = "R ", separators = TRUE, digits = 2)),
      Amount_Paid = colDef(format = colFormat(prefix = "R ", separators = TRUE, digits = 2)),
      Cost_To_Acquire = colDef(format = colFormat(prefix = "R ", separators = TRUE, digits = 2)),
      Remaining_Balance = colDef(format = colFormat(prefix = "R ", separators = TRUE, digits = 2)),
      Net_Profit = colDef(format = colFormat(prefix = "R ", separators = TRUE, digits = 2)),
      Is_Blacklisted = colDef(cell = function(value) toupper(as.character(value))),
      Has_External_Debts = colDef(cell = function(value) toupper(as.character(value))),
      Critical_Alert = colDef(cell = function(value) toupper(as.character(value))),
      Risk_Tier = colDef(cell = function(value) toupper(value))
    )
  )
}
# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------
ui <- page_sidebar(
  
  title = div(
    class = "dashboard-header",
    div(
      class = "dashboard-brand",
      div(
        span("PURSUIT", class = "brand-name"),
        span("Debtor Risk Dashboard", class = "dashboard-title")
      )
    ),
    actionButton(
      inputId = "theme_toggle",
      label = tagList(
        icon("sun", class = "icon-light-only"),
        icon("moon", class = "icon-dark-only"),
        span("Light mode", class = "theme-button-text theme-text-dark-active"),
        span("Dark mode", class = "theme-button-text theme-text-light-active")
      ),
      class = "theme-toggle-btn"
    )
  ),
  
  theme = bslib::bs_theme(
    version = 5,
    base_font = font_google("Poppins"),
    primary = "#8B5CF6",
    secondary = "#2563EB",
    success = "#10B981",
    warning = "#F59E0B",
    danger = "#F43F5E"
  ),
  
  tags$head(
    
    tags$script(
      HTML("
        document.documentElement.classList.add('dark-mode-root');

        document.addEventListener('DOMContentLoaded', function() {
          document.body.classList.add('dark-mode');
        });

        Shiny.addCustomMessageHandler('set-theme', function(message) {
          const body = document.body;
          const root = document.documentElement;

          body.classList.remove('dark-mode', 'light-mode');
          root.classList.remove('dark-mode-root', 'light-mode-root');

          if (message.mode === 'dark') {
            body.classList.add('dark-mode');
            root.classList.add('dark-mode-root');
          } else {
            body.classList.add('light-mode');
            root.classList.add('light-mode-root');
          }
        });
      ")
    ),
    
    tags$style(
      HTML("

        /* ================================================================
           GENERAL LAYOUT
           ================================================================ */

        html, body {
          min-height: 100%;
          transition: background-color 0.25s ease, color 0.25s ease;
        }

        body { font-family: 'Poppins', sans-serif; }

        .dashboard-header {
          width: 100%;
          min-height: 64px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 1rem;
        }

        .dashboard-brand { display: flex; align-items: center; gap: 0.8rem; }
        .dashboard-brand > div { display: flex; align-items: center; gap: 1rem; }

        .brand-name { color: #A855F7; font-size: 1rem; font-weight: 900; letter-spacing: 0.5px; }
        .dashboard-title { font-size: 1.05rem; font-weight: 700; }

        .navbar, .bslib-page-sidebar > .navbar, .bslib-page-sidebar > header {
          transition: background-color 0.25s ease, border-color 0.25s ease;
        }

        .theme-toggle-btn {
          display: inline-flex !important;
          align-items: center;
          justify-content: center;
          gap: 0.45rem;
          min-width: 126px;
          padding: 0.55rem 0.9rem !important;
          border-radius: 10px !important;
          font-size: 0.78rem !important;
          font-weight: 600 !important;
          transition: background-color 0.2s ease, border-color 0.2s ease,
                      color 0.2s ease, transform 0.2s ease, box-shadow 0.2s ease;
        }
        .theme-toggle-btn:hover { transform: translateY(-1px); }

        .icon-dark-only, .icon-light-only,
        .theme-text-dark-active, .theme-text-light-active { display: none; }
        body.dark-mode .icon-dark-only,
        body.light-mode .icon-light-only { display: inline-block; }
        body.dark-mode .theme-text-dark-active,
        body.light-mode .theme-text-light-active { display: inline; }

        body.dark-mode .collapse-toggle,
        body.dark-mode .sidebar-toggle,
        body.dark-mode .collapse-toggle svg,
        body.dark-mode .sidebar-toggle svg {
          color: #22D3EE !important;
          fill: #22D3EE !important;
        }

        /* ================================================================
           CARDS
           ================================================================ */

        .card {
          overflow: hidden;
          border-radius: 13px !important;
          transition: background-color 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease;
        }

        .card-header {
          padding: 1rem 1.1rem;
          font-size: 0.88rem;
          font-weight: 700;
          text-transform: uppercase;
          border-bottom-width: 1px;
        }

        .metric-card { position: relative; }

        .metric-card .bslib-value-box {
          min-height: 90px !important;
          padding: 0.8rem 1.1rem !important;
          border-radius: 13px !important;
          overflow: hidden;
          transition: transform 0.2s ease, background-color 0.25s ease,
                      border-color 0.25s ease, box-shadow 0.25s ease;
        }
        .metric-card .bslib-value-box:hover { transform: translateY(-2px); }

        .bslib-value-box .value-box-title {
          font-size: 0.83rem !important;
          font-weight: 500 !important;
          white-space: normal;
        }
        .bslib-value-box .value-box-value {
          margin-top: 0.2rem;
          font-size: 1.5rem !important;
          font-weight: 700 !important;
        }

        .bslib-value-box .value-box-showcase {
          font-size: 1.6rem !important;
        }
        .bslib-value-box .value-box-showcase svg,
        .bslib-value-box .value-box-showcase i {
          width: 1.6rem !important;
          height: 1.6rem !important;
          font-size: 1.6rem !important;
        }
        .bslib-full-screen-enter {
          background-color: transparent !important;
          border: none !important;
          color: #22D3EE !important;
        }
        .bslib-full-screen-enter svg,
body.dark-mode .collapse-toggle svg,
body.dark-mode .sidebar-toggle svg {
  width: 1.3rem !important;
  height: 1.3rem !important;
  filter: drop-shadow(0 0 0.5px currentColor) drop-shadow(0 0 0.5px currentColor);
}

        .metric-accounts .value-box-showcase { color: #A855F7 !important; }
        .metric-alerts .value-box-showcase { color: #F43F5E !important; }
        .metric-outstanding .value-box-showcase { color: #F43F5E !important; }
        .metric-profit .value-box-showcase { color: #10B981 !important; }

        .metric-outstanding #total_outstanding { color: #F43F5E !important; }
        .metric-profit #total_profit { color: #10B981 !important; }

        /* ================================================================
           ACCOUNTS ROW
           ================================================================ */

        .accounts-dashboard-row .bslib-grid { align-items: stretch; }
        .accounts-dashboard-row .bslib-grid > * { height: 100%; }
        .accounts-dashboard-row .card { height: 100%; }

        .insights-alerts-stack {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          height: 100%;
        }
        .insights-alerts-stack > .card {
          flex: 1 1 0;
          min-height: 0;
          display: flex;
          flex-direction: column;
        }
        .insights-alerts-stack .card-body {
          flex: 1 1 auto;
          overflow-y: auto;
        }
        
        #accounts_table .rt-search {
  background-color: transparent !important;
}
#accounts_table .rt-search input {
  background-color: #0B1424 !important;
  color: #E5E7EB !important;
  border: 1px solid #8B5CF6 !important;
}

        /* ================================================================
           QUICK INSIGHTS
           ================================================================ */

        .insights-wrapper { display: flex; flex-direction: column; gap: 0.15rem; }

        .insight-item {
          display: grid;
          grid-template-columns: 42px 1fr;
          gap: 0.85rem;
          align-items: center;
          padding: 1rem 0.25rem;
          border-bottom: 1px solid;
        }
        .insight-item:last-child { border-bottom: none; }

        .insight-icon {
          width: 40px; height: 40px;
          display: flex; align-items: center; justify-content: center;
          border-radius: 50%;
          font-size: 1rem;
        }
        .insight-icon-purple {
          color: #A855F7; border: 1px solid rgba(168, 85, 247, 0.5);
          background-color: rgba(168, 85, 247, 0.1);
        }
        .insight-icon-blue {
          color: #3B82F6; border: 1px solid rgba(59, 130, 246, 0.5);
          background-color: rgba(59, 130, 246, 0.1);
        }
        .insight-icon-pink {
          color: #F43F5E; border: 1px solid rgba(244, 63, 94, 0.5);
          background-color: rgba(244, 63, 94, 0.1);
        }

        .insight-value { margin-bottom: 0.2rem; font-size: 0.88rem; font-weight: 600; }
        .insight-description { font-size: 0.72rem; line-height: 1.5; }

        /* ================================================================
           ALERT FEED
           ================================================================ */

        .alert-feed { display: flex; flex-direction: column; }

        .alert-feed-item {
          display: grid;
          grid-template-columns: 30px 1fr auto;
          gap: 0.65rem;
          align-items: center;
          padding: 0.9rem 0.1rem;
          border-bottom: 1px solid;
        }
        .alert-feed-item:last-child { border-bottom: none; }

        .alert-feed-icon { color: #F43F5E; font-size: 0.95rem; text-align: center; }
        .alert-debtor-name { margin-bottom: 0.15rem; font-size: 0.78rem; font-weight: 600; }
        .alert-description { font-size: 0.68rem; }
        .alert-balance { font-size: 0.68rem; font-weight: 500; white-space: nowrap; }

        /* ================================================================
           CHAT
           ================================================================ */

        div.shiny-chat-input { border: none !important; }
        shiny-chat-container { font-size: 0.83rem; }

        div.shiny-chat-input textarea {
          border: 1px solid #8B5CF6 !important;
          border-radius: 14px !important;
          box-shadow: 0 0 10px rgba(139, 92, 246, 0.2);
          transition: background-color 0.25s ease, color 0.25s ease;
        }

        .shiny-chat-btn-send svg.bi-arrow-up-circle-fill {
          fill: #8B5CF6 !important;
          color: #8B5CF6 !important;
        }

        .shiny-chat-user-message {
          color: #FFFFFF !important;
          background-color: rgba(109, 40, 217, 0.88) !important;
          border-radius: 15px !important;
        }
        .shiny-chat-suggestion-list {
  display: flex !important;
  flex-direction: column !important;
  gap: 0.5rem !important;
  list-style: none !important;
  padding-left: 0 !important;
  margin-top: 0.5rem !important;
  background-color: transparent !important;
}
.shiny-chat-suggestion-list::before {
  content: 'Suggested follow-up questions: ';
  display: block;
  font-style: normal;
  font-weight: 600;
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: #94A3B8;
  margin-bottom: 0.4rem;
  background-color: transparent ! important;
}
.shiny-chat-suggestion-list li button {
  all: unset !important;
  display: block !important;
  font-style: italic !important;
  color: #C4B5FD !important;
  cursor: pointer !important;
  padding: 0.15rem 0 !important;
}
.shiny-chat-suggestion-list li button:hover {
  color: #22D3EE !important;
  text-decoration: underline !important;
}

        /* ================================================================
           DARK MODE — DEFAULT
           ================================================================ */

        html.dark-mode-root, body.dark-mode {
          color: #E5E7EB !important;
          background-color: #050A16 !important;
        }

        body.dark-mode .bslib-page-sidebar {
          background: radial-gradient(circle at top right, rgba(109, 40, 217, 0.11), transparent 35%), #050A16 !important;
        }

        body.dark-mode .navbar,
        body.dark-mode .bslib-page-sidebar > .navbar,
        body.dark-mode .bslib-page-sidebar > header {
          color: #F8FAFC !important;
          background-color: #07101F !important;
          border-bottom: 1px solid #1E293B !important;
        }

        body.dark-mode .dashboard-title { color: #F8FAFC; }

        body.dark-mode .theme-toggle-btn {
          color: #F5F3FF !important;
          background-color: rgba(124, 58, 237, 0.22) !important;
          border: 1px solid #8B5CF6 !important;
          box-shadow: 0 0 14px rgba(139, 92, 246, 0.22);
        }
        body.dark-mode .theme-toggle-btn:hover {
          color: #FFFFFF !important;
          background-color: #6D28D9 !important;
          box-shadow: 0 0 20px rgba(139, 92, 246, 0.35);
        }

        body.dark-mode .sidebar {
          color: #CBD5E1 !important;
          background-color: #07101F !important;
          border-right: 1px solid #1E293B !important;
        }

        body.dark-mode .card {
          color: #E5E7EB !important;
          background-color: #091322 !important;
          border: 1px solid #1E293B !important;
          box-shadow: 0 8px 22px rgba(0, 0, 0, 0.23) !important;
        }

        body.dark-mode .card-header {
          color: #F8FAFC !important;
          background-color: #091322 !important;
          border-bottom-color: #1E293B !important;
        }

        body.dark-mode .metric-card .bslib-value-box {
          color: #E5E7EB !important;
          background: linear-gradient(145deg, rgba(14, 24, 42, 0.98), rgba(7, 16, 31, 0.98)) !important;
          border: 1px solid rgba(139, 92, 246, 0.3) !important;
          box-shadow: 0 7px 16px rgba(0, 0, 0, 0.28), 0 0 10px rgba(109, 40, 217, 0.08) !important;
        }

        body.dark-mode .metric-card .bslib-value-box:hover {
          border-color: #C084FC !important;
          box-shadow: 0 10px 26px rgba(0, 0, 0, 0.32), 0 0 36px 8px rgba(192, 132, 252, 0.45) !important;
        }

        body.dark-mode .bslib-value-box .value-box-title { color: #CBD5E1 !important; }
        body.dark-mode .bslib-value-box .value-box-value { color: #F8FAFC; }

        body.dark-mode .insight-item, body.dark-mode .alert-feed-item { border-bottom-color: #1E293B; }
        body.dark-mode .insight-description, body.dark-mode .alert-description,
        body.dark-mode .alert-balance { color: #94A3B8; }

        body.dark-mode div.shiny-chat-input textarea {
          color: #E5E7EB !important;
          background-color: #0B1424 !important;
        }
        body.dark-mode div.shiny-chat-input textarea::placeholder { color: #94A3B8 !important; }
        body.dark-mode shiny-chat-container { color: #CBD5E1; }

        body.dark-mode .rt-table, body.dark-mode .rt-thead, body.dark-mode .rt-tbody,
        body.dark-mode .rt-tr, body.dark-mode .rt-th, body.dark-mode .rt-td {
          color: #DCE3EE !important;
          background-color: #091322 !important;
          border-color: #1E293B !important;
        }
        body.dark-mode .rt-th { color: #F8FAFC !important; }
        body.dark-mode .rt-search { background-color: #091322 !important; }
        body.dark-mode .rt-pagination {
          color: #CBD5E1 !important;
          background-color: #091322 !important;
          border-top-color: #1E293B !important;
        }

        /* ================================================================
           LIGHT MODE
           ================================================================ */

        html.light-mode-root, body.light-mode {
          color: #172033 !important;
          background-color: #EEF1F7 !important;
        }

        body.light-mode .bslib-page-sidebar {
          background: radial-gradient(circle at top right, rgba(59, 130, 246, 0.07), transparent 30%), #EEF1F7 !important;
        }

        body.light-mode .navbar,
        body.light-mode .bslib-page-sidebar > .navbar,
        body.light-mode .bslib-page-sidebar > header {
          color: #172033 !important;
          background-color: #F4F6FA !important;
          border-bottom: 1px solid #DCE2EE !important;
        }

        body.light-mode .dashboard-title { color: #111827; }

        body.light-mode .theme-toggle-btn {
          color: #FFFFFF !important;
          background: linear-gradient(135deg, #6D28D9, #2563EB) !important;
          border: 1px solid #6D28D9 !important;
          box-shadow: 0 5px 12px rgba(109, 40, 217, 0.2);
        }
        body.light-mode .theme-toggle-btn:hover {
          box-shadow: 0 7px 17px rgba(109, 40, 217, 0.3);
        }

        body.light-mode .sidebar {
          color: #334155 !important;
          background-color: #F4F6FA !important;
          border-right: 1px solid #DCE2EE !important;
        }

        body.light-mode .card {
          color: #172033 !important;
          background-color: #F8F9FC !important;
          border: 1px solid #DCE2EE !important;
          box-shadow: 0 7px 18px rgba(44, 62, 100, 0.08) !important;
        }

        body.light-mode .card-header {
          color: #111827 !important;
          background-color: #F8F9FC !important;
          border-bottom-color: #E1E6EF !important;
        }

        body.light-mode .metric-card .bslib-value-box {
          color: #172033 !important;
          background: linear-gradient(145deg, #FAFBFE, #F3F5FA) !important;
          border: 1px solid #D9DFEB !important;
          box-shadow: 0 7px 16px rgba(44, 62, 100, 0.11), 0 0 8px rgba(109, 40, 217, 0.04) !important;
        }

        body.light-mode .metric-card .bslib-value-box:hover {
          border-color: #A855F7 !important;
          box-shadow: 0 10px 24px rgba(44, 62, 100, 0.16), 0 0 32px 7px rgba(168, 85, 247, 0.30) !important;
        }

        body.light-mode .bslib-value-box .value-box-title { color: #475569 !important; }
        body.light-mode .bslib-value-box .value-box-value { color: #172033; }

        body.light-mode .insight-item, body.light-mode .alert-feed-item { border-bottom-color: #E1E6EF; }
        body.light-mode .insight-description, body.light-mode .alert-description,
        body.light-mode .alert-balance { color: #64748B; }

        body.light-mode div.shiny-chat-input textarea {
          color: #172033 !important;
          background-color: #F8F9FC !important;
        }
        body.light-mode div.shiny-chat-input textarea::placeholder { color: #64748B !important; }
        body.light-mode shiny-chat-container { color: #334155; }

        body.light-mode .rt-table, body.light-mode .rt-thead, body.light-mode .rt-tbody,
        body.light-mode .rt-tr, body.light-mode .rt-th, body.light-mode .rt-td {
          color: #253047 !important;
          background-color: #F8F9FC !important;
          border-color: #E1E6EF !important;
        }
        body.light-mode .rt-th { color: #111827 !important; }
        body.light-mode .rt-search { background-color: #F8F9FC !important; }
        body.light-mode .rt-pagination {
          color: #475569 !important;
          background-color: #F8F9FC !important;
          border-top-color: #E1E6EF !important;
        }

        /* Search box fix -- targets the real #accounts_table ID directly
           rather than guessing reactable's internal class names */
       #accounts_table { background-color: transparent !important; }
body.dark-mode #accounts_table input {
  background-color: #0B1424 !important;
  color: #E5E7EB !important;
  border: 1px solid #8B5CF6 !important;
}
body.light-mode #accounts_table input {
  background-color: #FFFFFF !important;
  color: #172033 !important;
  border: 1px solid #8B5CF6 !important;
}
        
        .querychat pre,
.querychat code,
.querychat .card {
  background-color: #0B1424 !important;
  color: #E5E7EB !important;
  border: 1px solid #334155 !important;
}

        /* ================================================================
           MOBILE
           ================================================================ */

        @media (max-width: 900px) {
          .accounts-dashboard-row .bslib-grid { grid-template-columns: 1fr !important; }
          .dashboard-brand > div { display: block; }
          .brand-name { display: none; }
          .dashboard-title { font-size: 0.88rem; }
          .theme-toggle-btn { min-width: auto; }
          .theme-button-text { display: none; }
        }
      ")
    )
  ),
  
  sidebar = qc$sidebar(width = 300),
  
  # --------------------------------------------------------------------------
  # TOP KPI CARDS
  # Each div(...) wrapper needs TWO closing parens before its trailing
  # comma: one for value_box(...), one for the div(...) itself. Missing the
  # second one is what caused the "possible missing comma" parse errors --
  # every subsequent div(...) was getting swallowed as another argument to
  # the still-open previous div(...) instead of becoming its own sibling.
  # --------------------------------------------------------------------------
  layout_columns(
    fill = FALSE,
    col_widths = c(3, 3, 3, 3),
    
    div(class = "metric-card metric-accounts",
        value_box(title = "Total Accounts", value = textOutput("total_accounts"),
                  showcase = icon("users"), showcase_layout = bslib::showcase_left_center(width = "30%"))
    ),
    
    div(class = "metric-card metric-alerts",
        value_box(title = "Critical Alerts", value = textOutput("critical_alerts"),
                  showcase = icon("triangle-exclamation"), showcase_layout = bslib::showcase_left_center(width = "30%"))
    ),
    
    div(class = "metric-card metric-outstanding",
        value_box(title = "Total Outstanding", value = textOutput("total_outstanding"),
                  showcase = icon("wallet"), showcase_layout = bslib::showcase_left_center(width = "30%"))
    ),
    
    div(class = "metric-card metric-profit",
        value_box(title = "Total Net Profit", value = textOutput("total_profit"),
                  showcase = icon("chart-line"), showcase_layout = bslib::showcase_left_center(width = "30%"))
    )
  ),
  
  # --------------------------------------------------------------------------
  # ACCOUNTS TABLE, QUICK INSIGHTS, CRITICAL ALERT FEED
  # --------------------------------------------------------------------------
  div(
    class = "accounts-dashboard-row",
    layout_columns(
      col_widths = c(7, 5),
      
      card(
        full_screen = TRUE,
        card_header("Accounts"),
        reactableOutput("accounts_table")
      ),
      
      div(
        class = "insights-alerts-stack",
        card(
          card_header(tagList(icon("lightbulb"), " Quick Insights")),
          uiOutput("quick_insights")
        ),
        card(
          card_header(tagList(icon("bell"), " Critical Alert Feed")),
          uiOutput("critical_alert_feed")
        )
      )
    )
  )
)

# ------------------------------------------------------------------------------
# SERVER
# ------------------------------------------------------------------------------
server <- function(input, output, session) {
  qc_vals <- qc$server()
  
  filtered_data <- reactive({
    df <- qc_vals$df()
    req(df)
    df
  })
  
  dark_mode <- reactiveVal(TRUE)
  is_dark <- reactive({ dark_mode() })
  
  observeEvent(input$theme_toggle, {
    new_mode <- !dark_mode()
    dark_mode(new_mode)
    session$sendCustomMessage("set-theme", list(mode = if (new_mode) {"dark"} else {"light"}))
  })
  
  # ---- Value boxes ----
  output$total_accounts <- renderText(format(nrow(filtered_data()), big.mark = ","))
  output$critical_alerts <- renderText(format(sum(filtered_data()$Critical_Alert, na.rm = TRUE), big.mark = ","))
  output$total_outstanding <- renderText(
    scales::dollar(sum(filtered_data()$Remaining_Balance, na.rm = TRUE), prefix = "R", big.mark = ",")
  )
  output$total_profit <- renderText(
    scales::dollar(sum(filtered_data()$Net_Profit, na.rm = TRUE), prefix = "R", big.mark = ",")
  )
  
  # ---- Accounts table ----
  output$accounts_table <- renderReactable({
    styled_accounts_table(filtered_data(), page_size = 10, dark = is_dark())
  })
  
  # --------------------------------------------------------------------------
  # QUICK INSIGHTS
  # --------------------------------------------------------------------------
  output$quick_insights <- renderUI({
    data <- filtered_data()
    
    critical_count <- sum(data$Critical_Alert, na.rm = TRUE)
    severe_count <- sum(data$Risk_Tier == "Severe", na.rm = TRUE)
    total_outstanding <- sum(data$Remaining_Balance, na.rm = TRUE)
    
    highest_risk_tier <- data %>%
      filter(!is.na(Risk_Tier)) %>%
      count(Risk_Tier, sort = TRUE) %>%
      slice_head(n = 1)
    
    highest_risk_text <- if (nrow(highest_risk_tier) > 0) {
      paste0(highest_risk_tier$Risk_Tier, " contains the most accounts")
    } else {
      "No risk-tier information available"
    }
    
    div(
      class = "insights-wrapper",
      div(
        class = "insight-item",
        div(class = "insight-icon insight-icon-purple", icon("shield-halved")),
        div(
          div(class = "insight-value", paste(format(critical_count, big.mark = ","), "critical alert accounts")),
          div(class = "insight-description", "Accounts currently matching the active critical-alert rules.")
        )
      ),
      div(
        class = "insight-item",
        div(class = "insight-icon insight-icon-blue", icon("wallet")),
        div(
          div(class = "insight-value", scales::dollar(total_outstanding, prefix = "R", big.mark = ",")),
          div(class = "insight-description", "Total outstanding balance for the currently filtered portfolio.")
        )
      ),
      div(
        class = "insight-item",
        div(class = "insight-icon insight-icon-pink", icon("bullseye")),
        div(
          div(class = "insight-value", paste(format(severe_count, big.mark = ","), "severe-risk accounts")),
          div(class = "insight-description", highest_risk_text)
        )
      )
    )
  })
  
  # --------------------------------------------------------------------------
  # CRITICAL ALERT FEED
  # --------------------------------------------------------------------------
  output$critical_alert_feed <- renderUI({
    alert_data <- filtered_data() %>%
      filter(Critical_Alert %in% TRUE) %>%
      arrange(desc(Days_Past_Due), desc(Remaining_Balance)) %>%
      slice_head(n = 4)
    
    if (nrow(alert_data) == 0) {
      return(
        div(
          style = "padding: 1.5rem 0.5rem; text-align: center; opacity: 0.75;",
          icon("circle-check"), tags$br(), tags$br(),
          "No critical alerts in the current results."
        )
      )
    }
    
    alert_rows <- lapply(seq_len(nrow(alert_data)), function(index) {
      debtor_name <- alert_data$Debtor_Name[index]
      days_past_due <- alert_data$Days_Past_Due[index]
      balance <- alert_data$Remaining_Balance[index]
      
      description <- if (!is.na(days_past_due) && days_past_due > 0) {
        paste("Payment overdue by", days_past_due, "days")
      } else {
        "Critical account requires review"
      }
      
      div(
        class = "alert-feed-item",
        div(class = "alert-feed-icon", icon("triangle-exclamation")),
        div(
          div(class = "alert-debtor-name", debtor_name),
          div(class = "alert-description", description)
        ),
        div(class = "alert-balance", scales::dollar(balance, prefix = "R", big.mark = ","))
      )
    })
    
    do.call(div, c(list(class = "alert-feed"), alert_rows))
  })
}

shinyApp(ui, server)
