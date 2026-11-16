# Shared helpers for the jails dashboard pipeline.
# All data pulls go through these functions so tests can swap in local fixtures
# by setting the environment variable JAILS_FIXTURES to a folder of CSV/XML files.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
  library(jsonlite)
})

CONFIG   <- fromJSON("config.json")
FIXTURES <- Sys.getenv("JAILS_FIXTURES", "")
TODAY    <- as.Date(Sys.getenv("JAILS_TODAY", as.character(Sys.Date())))

ODP <- "https://data.cityofnewyork.us/resource/"

# Socrata query returning a data frame of character columns.
soda <- function(id, params, page = 50000, paged = FALSE) {
  if (nzchar(FIXTURES)) {
    key <- gsub("[^A-Za-z0-9]+", "_", paste(id, paste(names(params), params, collapse = "_")))
    f <- file.path(FIXTURES, paste0(substr(key, 1, 120), ".csv"))
    if (!file.exists(f)) stop("Missing fixture: ", f)
    return(read_csv(f, col_types = cols(.default = col_character()), progress = FALSE))
  }
  get_page <- function(offset) {
    q <- c(params, if (paged) c("$order" = ":id", "$limit" = format(page, scientific = FALSE), "$offset" = format(offset, scientific = FALSE)) else c("$limit" = "100000"))
    url <- paste0(ODP, id, ".csv?",
                  paste(names(q), vapply(as.character(q), URLencode, "", reserved = TRUE), sep = "=", collapse = "&"))
    for (attempt in 1:3) {
      out <- tryCatch(read_csv(url, col_types = cols(.default = col_character()), progress = FALSE),
                      error = function(e) e)
      if (!inherits(out, "error")) return(out)
      Sys.sleep(10 * attempt)
    }
    stop("Could not read ", id, " from NYC Open Data: ", conditionMessage(out))
  }
  if (!paged) return(get_page(0))
  out <- list(); offset <- 0
  repeat {
    chunk <- get_page(offset)
    if (nrow(chunk) == 0) break
    out[[length(out) + 1]] <- chunk
    if (nrow(chunk) < page) break
    offset <- offset + page
  }
  bind_rows(out)
}

# Published Google Sheet (CSV link).
read_sheet <- function(key) {
  url <- CONFIG[[key]]
  if (nzchar(FIXTURES)) return(read_csv(file.path(FIXTURES, paste0(key, ".csv")),
                                        col_types = cols(.default = col_character()), progress = FALSE))
  if (grepl("^PASTE_", url)) stop("config.json: ", key, " has not been filled in yet")
  read_csv(url, col_types = cols(.default = col_character()), progress = FALSE)
}

to_date <- function(x) as.Date(substr(x, 1, 10))
month_key <- function(d) format(d, "%Y-%m")

# Collected problems. Anything added with fail() stops the build before publishing.
.problems <- character()
.notes    <- character()
fail <- function(...) .problems <<- c(.problems, paste0(...))
note <- function(...) .notes <<- c(.notes, paste0(...))
