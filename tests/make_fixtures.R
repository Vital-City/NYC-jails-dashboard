# Builds synthetic fixtures so the pipeline can be tested without network access.
# Usage (from the repo root): Rscript tests/make_fixtures.R /tmp/fixtures
# then: JAILS_FIXTURES=/tmp/fixtures JAILS_TODAY=2026-11-16 Rscript R/build.R
suppressPackageStartupMessages({library(dplyr); library(readr)})
args <- commandArgs(TRUE); fx <- args[1]; dir.create(fx, showWarnings = FALSE)
key <- function(id, params) paste0(substr(gsub("[^A-Za-z0-9]+", "_", paste(id, paste(names(params), params, collapse = "_"))), 1, 120), ".csv")
set.seed(1)
cutoff <- as.Date("2026-10-31")
adm <- as.Date("2012-01-01") + sort(sample(0:as.integer(cutoff - as.Date("2012-01-01")), 1900 * 12 * 15, TRUE))
dis <- adm + ceiling(rexp(length(adm), 1/105))
done <- dis <= cutoff
write_csv(tibble(admitted_dt = paste0(adm[done], "T10:00:00.000"), discharged_dt = paste0(dis[done], "T12:00:00.000")),
          file.path(fx, key("94ri-3ium", c("$select" = "admitted_dt,discharged_dt"))))
inside <- adm[!done]
codes <- c("125.25","110-125.25","120.05","160.15","140.20","265.03","140.25","160.10","120.10","220.16","155.25","VOP",NA,"999.99")
charge <- sample(codes, length(inside), TRUE)
write_csv(tibble(admitted_dt = paste0(inside, "T10:00:00.000")), file.path(fx, key("7479-ugqb", c("$select" = "admitted_dt"))))
write_csv(tibble(admitted_dt = paste0(inside, "T10:00:00.000"), top_charge = charge), file.path(fx, key("7479-ugqb", c("$select" = "admitted_dt,top_charge"))))
mk <- function(id, field, from, vals, mx) {
  write_csv(tibble(mx = mx), file.path(fx, key(id, c("$select" = paste0("max(", field, ") as mx")))))
  months <- format(seq(as.Date(paste0(from, "-01-01")), by = "month", length.out = length(vals)), "%Y-%m-01T00:00:00.000")
  write_csv(tibble(m = months, n = vals), file.path(fx, key(id, c("$select" = paste0("date_trunc_ym(", field, ") as m, count(*) as n"),
                                                                 "$where" = paste0(field, " >= '", from, "-01-01T00:00:00'"), "$group" = "m", "$order" = "m"))))
}
stab <- c(1,9,1,12,8,10,15,15,22,15,14,12,11,16,17,12,6,14,13,5,12,7,9,10,13,4,7,8,5,5,2,11,6,10,9,16,10,4,7,7,13,12,14,7,14,7,15,10,10,5,13,7,8,14,11,7,9,16,12,9,14,19,27,40,42,41,28,39,51,38,35,46,50,32,66,43,24,39,43,40,30,46,33,32,41,23,32,22,26,21,25,47,47,42,25,31,29,27,30,24,18,27,16,20,32,22,31,28,21,16,16,27,26,35,24,22,28,21,18,28,21,19,25,27,29,44,26,29,22,28)
mk("gakf-suji", "reported_dt", 2016, stab, "2026-10-30T14:00:00.000")
mk("6teu-xtgp", "admitted_dt", 2014, rep(2000, 154), "2026-10-31T23:00:00.000")
write_csv(read_csv("tests/fixtures_src/deaths.csv", col_types = cols(.default = "c")), file.path(fx, "deaths_sheet_csv.csv"), na = "")
write_csv(read_csv("tests/fixtures_src/uof.csv", col_types = cols(.default = "c")), file.path(fx, "use_of_force_sheet_csv.csv"), na = "")
file.copy("tests/fixtures_src/news.xml", file.path(fx, "news.xml"), overwrite = TRUE)
cat("fixtures written to", fx, "\n")
