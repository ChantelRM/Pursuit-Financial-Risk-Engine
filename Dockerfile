FROM rocker/shiny-verse:latest
WORKDIR /app
RUN R -e "install.packages(c('bslib', 'shinychat', 'querychat', 'DBI', 'dplyr', 'reactable', 'ggplot2', 'scales'), repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages(c('duckdb'), repos = 'https://cloud.r-project.org/')"
COPY app.R .
COPY data/ data/
EXPOSE 3838
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]


