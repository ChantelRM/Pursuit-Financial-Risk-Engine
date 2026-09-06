FROM rocker/shiny-verse:latest
RUN R -e "install.packages(c('bslib', 'shinychat', 'querychat', 'DBI', 'dplyr', 'reactable', 'ggplot2', 'scales', 'RSQLite'), repos = 'https://cloud.r-project.org/')"
COPY app.R .
COPY data/processed/ ./data/processed/
EXPOSE 3838
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]


