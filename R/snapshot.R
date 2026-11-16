# Daily job: save today's Daily Inmates In Custody snapshot.
# Writes data/snapshots/YYYY-MM-DD.csv.gz (admission dates only, no IDs) and
# appends the day's head count to data/snapshot_counts.csv. Full snapshots older
# than snapshot_keep_days are deleted; the counts file is kept forever.

source("R/common.R")

snap <- soda("7479-ugqb", c("$select" = "admitted_dt"))
n <- nrow(snap)
if (n < 3000 || n > 15000) stop("Custody snapshot has ", n, " rows; outside the plausible range, not saved")

dir.create("data/snapshots", recursive = TRUE, showWarnings = FALSE)
write_csv(tibble(admitted = sort(to_date(snap$admitted_dt))),
          file.path("data/snapshots", paste0(TODAY, ".csv.gz")))

path <- "data/snapshot_counts.csv"
counts <- if (file.exists(path)) read_csv(path, col_types = "Di") else tibble(date = as.Date(character()), n = integer())
counts <- counts %>% filter(date != TODAY) %>% bind_rows(tibble(date = TODAY, n = n)) %>% arrange(date)
write_csv(counts, path)

files <- list.files("data/snapshots", pattern = "\\.csv\\.gz$", full.names = TRUE)
old <- files[as.Date(sub("\\.csv\\.gz$", "", basename(files))) < TODAY - CONFIG$snapshot_keep_days]
if (length(old)) file.remove(old)

cat("Saved snapshot for", format(TODAY), "with", n, "people in custody\n")
