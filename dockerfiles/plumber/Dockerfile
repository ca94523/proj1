FROM rocker/r-base

RUN apt-get update -qq && apt-get install -y \
  git-core \
  libssl-dev \
  libcurl4-gnutls-dev

RUN R -e "install.packages(c('devtools','jsonlite','dplyr','rjson'))"
RUN install2.r plumber

EXPOSE 8000
ENTRYPOINT ["R", "-e", "pr <- plumber::plumb(commandArgs()[4]); pr$run(host='0.0.0.0', port=8000, swagger = TRUE)"]
CMD ["/plumber.R"]



