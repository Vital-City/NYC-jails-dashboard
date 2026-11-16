# Weekly job: rebuild site/data.json from every source.
# If any check fails, the script stops before writing, so the live page keeps
# the last good version and GitHub marks the run as failed (and emails you).

source("R/common.R")
MONTHS <- month.abb

# ---------------------------------------------------------------------------
# 1. Deaths (Google Sheet: Year, Jan..Dec, Notes)
# ---------------------------------------------------------------------------
ds <- read_sheet("deaths_sheet_csv")
need <- c("Year", MONTHS)
if (!all(need %in% names(ds))) fail("Deaths sheet is missing columns: ", paste(setdiff(need, names(ds)), collapse = ", "))
ds <- ds %>% filter(grepl("^\\d{4}$", trimws(Year)))
deaths <- list()
for (i in seq_len(nrow(ds))) {
  y <- trimws(ds$Year[i])
  v <- suppressWarnings(as.numeric(trimws(unlist(ds[i, MONTHS]))))
  raw <- trimws(unlist(ds[i, MONTHS])); raw[is.na(raw)] <- ""
  bad <- raw != "" & (is.na(v) | v < 0 | v > 25 | v != round(v))
  if (any(bad)) fail("Deaths sheet, ", y, ": ", paste(MONTHS[bad], collapse = ", "), " is not a whole number between 0 and 25")
  last <- if (any(raw != "")) max(which(raw != "")) else 0
  v[seq_len(last)][is.na(v[seq_len(last)])] <- 0          # blanks before the last entry count as 0
  if (last < 12) v[(last + 1):12] <- NA                    # blanks after it are months not reached yet
  deaths[[y]] <- v
}
yrs <- as.integer(names(deaths))
if (length(yrs) == 0) fail("Deaths sheet has no year rows")
if (length(yrs) && any(diff(sort(yrs)) != 1)) fail("Deaths sheet years are not consecutive")
if (length(yrs) && max(yrs) > year(TODAY)) fail("Deaths sheet has a row for a future year (", max(yrs), ")")

# ---------------------------------------------------------------------------
# 2. Use of force (Google Sheet: Fiscal year, Incidents of use of force, ADP (MMR), Source)
# ---------------------------------------------------------------------------
us <- read_sheet("use_of_force_sheet_csv")
names(us)[1:3] <- c("fy", "incidents", "adp")
us <- us %>% filter(grepl("^\\d{4}$", trimws(fy))) %>%
  mutate(fy = as.integer(fy), incidents = as.numeric(gsub(",", "", incidents)), adp = as.numeric(gsub(",", "", adp))) %>%
  arrange(fy)
if (any(is.na(us$incidents) | is.na(us$adp))) fail("Use of force sheet has a blank or non-numeric cell")
if (nrow(us) && any(diff(us$fy) != 1)) fail("Use of force sheet fiscal years are not consecutive")
uof <- lapply(seq_len(nrow(us)), function(i) list(us$fy[i], us$incidents[i], round(us$incidents[i] / us$adp[i] * 1000, 1)))

# ---------------------------------------------------------------------------
# 3. Average daily population (ADP)
# ---------------------------------------------------------------------------
compiled <- read_csv("data/manual/adp_monthly_compiled.csv", col_types = "cd")
splice   <- as.Date(paste0(CONFIG$splice_month, "-01"))

dis <- soda("94ri-3ium", c("$select" = "admitted_dt,discharged_dt"), paged = TRUE) %>%
  transmute(admitted = to_date(admitted_dt), discharged = to_date(discharged_dt)) %>%
  filter(!is.na(admitted), !is.na(discharged), discharged >= admitted)
cutoff <- max(dis$discharged)
if (cutoff < TODAY - 75) fail("Inmate Discharges has not been updated since ", cutoff)

# custody snapshot closest to the day after the discharge cutoff
snap_files <- list.files("data/snapshots", pattern = "\\.csv\\.gz$", full.names = TRUE)
snap_dates <- as.Date(sub("\\.csv\\.gz$", "", basename(snap_files)))
live <- soda("7479-ugqb", c("$select" = "admitted_dt,top_charge"))
if (length(snap_files)) {
  after <- snap_dates[snap_dates > cutoff]
  snap_date <- if (length(after)) min(after) else max(snap_dates)
  cur <- read_csv(snap_files[snap_dates == snap_date], col_types = "D")$admitted
} else {
  snap_date <- TODAY; cur <- to_date(live$admitted_dt)
}
snap_gap <- as.integer(snap_date - (cutoff + 1))

daily_population <- function(admitted, discharged, start, end) {
  n <- as.integer(end - start) + 1
  a <- pmax(as.integer(admitted - start), 0) + 1
  d <- ifelse(is.na(discharged), n + 1, as.integer(discharged - start) + 1)
  keep <- d > a & a <= n & d > 1
  ins <- tabulate(a[keep], nbins = n)
  outs <- tabulate(d[keep][d[keep] <= n], nbins = n)
  tibble(date = start + 0:(n - 1), pop = cumsum(ins - outs))
}
end_full <- floor_date(cutoff + 1, "month") - 1
pop <- daily_population(c(dis$admitted, cur), c(dis$discharged, rep(NA, length(cur))), splice, end_full)
rebuilt <- pop %>% mutate(month = month_key(date)) %>% group_by(month) %>%
  summarise(adp = mean(pop), .groups = "drop") %>%
  mutate(source = "opendata", provisional = snap_gap > 3 & month > month_key(end_full %m-% months(12)))

# Provisional rebuilt months use the compiled figure where one exists
rebuilt <- rebuilt %>% left_join(rename(compiled, compiled = adp), by = "month") %>%
  # a provisional month with no compiled figure is known to run low; leave it out until the
  # snapshot from the day after the next discharge release makes it exact
  filter(!(provisional & is.na(compiled))) %>%
  mutate(source = ifelse(provisional & !is.na(compiled), "compiled", source),
         adp = ifelse(provisional & !is.na(compiled), compiled, adp)) %>% select(-compiled)

counts_path <- "data/snapshot_counts.csv"
counts <- if (file.exists(counts_path)) read_csv(counts_path, col_types = "Di") else tibble(date = as.Date(character()), n = integer())
recent <- counts %>% filter(date > end_full) %>% mutate(month = month_key(date)) %>%
  group_by(month) %>% summarise(adp = mean(n), days = n(), .groups = "drop") %>%
  filter(days >= 7) %>% transmute(month, adp, source = "daily_count", provisional = TRUE)
# months between the rebuild and the daily counts (before the daily job started) fall back to compiled figures
gap_months <- compiled %>% filter(month > month_key(end_full), !month %in% recent$month) %>%
  transmute(month, adp, source = "compiled", provisional = TRUE)

adp <- bind_rows(compiled %>% filter(month < CONFIG$splice_month) %>% mutate(source = "compiled", provisional = FALSE),
                 rebuilt, gap_months, recent) %>%
  arrange(month) %>% distinct(month, .keep_all = TRUE)
# drop trailing months that skip ahead (keep the series continuous)
m_all <- as.Date(paste0(adp$month, "-01"))
breaks <- which(diff(m_all) > 31)
if (length(breaks)) { note("ADP series has a gap after ", adp$month[breaks[1]], "; later months dropped"); adp <- adp[seq_len(breaks[1]), ] }

chg <- adp$adp / lag(adp$adp) - 1
pandemic <- adp$month >= "2020-03" & adp$month <= "2020-06"
if (any(abs(chg) > 0.15 & !pandemic, na.rm = TRUE)) fail("ADP changes more than 15% in one month at ", paste(adp$month[which(abs(chg) > 0.15 & !pandemic)], collapse = ", "))
if (any(adp$adp < 3000 | adp$adp > 15000)) fail("ADP outside 3,000 to 15,000")

# Compare fiscal-year averages with the MMR figures in the use of force sheet
fyc <- adp %>% mutate(d = as.Date(paste0(month, "-01")), fy = year(d) + (month(d) >= 7)) %>%
  group_by(fy) %>% summarise(ours = mean(adp), n = n(), .groups = "drop") %>% filter(n == 12) %>%
  inner_join(us %>% select(fy, mmr = adp), by = "fy") %>% filter(fy >= 2020) %>% mutate(diff = ours / mmr - 1)
for (i in which(abs(fyc$diff) > 0.015)) note(sprintf("FY%d ADP is %+.1f%% from the MMR figure", fyc$fy[i], 100 * fyc$diff[i]))

adp_annual_pre <- read_csv("data/manual/adp_annual_2000_2012.csv", col_types = "id")

# ---------------------------------------------------------------------------
# 4. Monthly counts: stabbings/slashings and admissions (complete months only)
# ---------------------------------------------------------------------------
monthly_counts <- function(id, field, from) {
  mx <- to_date(soda(id, c("$select" = paste0("max(", field, ") as mx")))$mx)
  last_full <- if (day(mx) >= days_in_month(mx) - 2) floor_date(mx, "month") else floor_date(mx, "month") %m-% months(1)
  m <- soda(id, c("$select" = paste0("date_trunc_ym(", field, ") as m, count(*) as n"),
                  "$where" = paste0(field, " >= '", from, "-01-01T00:00:00'"), "$group" = "m", "$order" = "m")) %>%
    transmute(month = substr(m, 1, 7), n = as.integer(n))
  all <- tibble(month = month_key(seq(as.Date(paste0(from, "-01-01")), last_full, by = "month")))
  out <- all %>% left_join(m, by = "month") %>% mutate(n = coalesce(n, 0L))
  list(data = out, last = last_full)
}
st <- monthly_counts("gakf-suji", "reported_dt", 2016)
if (st$last < floor_date(TODAY, "month") %m-% months(3)) fail("Stabbing data last complete month is ", month_key(st$last))
sx <- st$data$n; r12 <- sapply(seq_along(sx), function(i) if (i > 12) max(sx[(i - 12):(i - 1)]) else Inf)
if (tail(sx, 1) > 3 * tail(r12, 1)) fail("Latest stabbing month (", tail(sx, 1), ") is more than three times any month in the past year")
stab <- split(st$data$n, substr(st$data$month, 1, 4))

ad <- monthly_counts("6teu-xtgp", "admitted_dt", 2014)
admissions <- lapply(seq_len(nrow(ad$data)), function(i) list(ad$data$month[i], ad$data$n[i]))

# ---------------------------------------------------------------------------
# 5. Length of stay (mean days, by year of discharge)
# ---------------------------------------------------------------------------
los_od <- dis %>% filter(discharged >= as.Date("2014-01-01")) %>%
  mutate(y = year(discharged), days = as.numeric(discharged - admitted)) %>%
  group_by(y) %>% summarise(v = round(mean(days), 1), .groups = "drop")
los_old <- read_csv("data/manual/los_2005_2013.csv", col_types = "id")
los <- c(lapply(seq_len(nrow(los_old)), function(i) list(los_old$year[i], los_old$avg_days[i], "chart")),
         lapply(seq_len(nrow(los_od)), function(i) list(los_od$y[i], los_od$v[i], "opendata")))

# ---------------------------------------------------------------------------
# 6. Who is held now: count, time held, most serious charge
# ---------------------------------------------------------------------------
n_now <- nrow(live)
if (n_now < 3000 || n_now > 15000) fail("Custody snapshot has ", n_now, " rows")
over1y <- sum(to_date(live$admitted_dt) < TODAY - 365, na.rm = TRUE)

cc <- read_csv("data/manual/charge_classes.csv", col_types = "ccc")
stay_ai <- read_csv("data/manual/attempt_stays_class_AI.csv", col_types = "c")$penal_law_section
down <- c(AI = "B", AII = "C", B = "C", C = "D", D = "E", E = "AM", AM = "BM", BM = "BM")
grp <- c(AI = "A felony", AII = "A felony", B = "B felony", C = "C felony", D = "D or E felony", E = "D or E felony", AM = "Misdemeanor", BM = "Misdemeanor")
klass <- function(code) {
  code <- trimws(code); att <- startsWith(code, "110-"); base <- ifelse(att, substring(code, 5), code)
  k <- cc$class[match(base, cc$penal_law_section)]
  k <- ifelse(att & !is.na(k), ifelse(k == "AI" & base %in% stay_ai, "AI", down[k]), k)
  ifelse(is.na(k), "Other or not recorded", grp[k])
}
order_g <- c("A felony", "B felony", "C felony", "D or E felony", "Misdemeanor", "Other or not recorded")
cg <- table(factor(klass(live$top_charge), levels = order_g))
charges <- lapply(order_g, function(g) list(g, as.integer(cg[[g]])))
if (cg[["Other or not recorded"]] / n_now > 0.2) note("More than 20% of top charges are unclassified; review data/manual/charge_classes.csv")

# ---------------------------------------------------------------------------
# 7. News (Google News RSS); failures keep last week's list
# ---------------------------------------------------------------------------
old_news <- if (file.exists("site/data.json")) fromJSON("site/data.json", simplifyVector = FALSE)$news else list()
news <- tryCatch({
  q <- paste0(CONFIG$news_query, " when:", CONFIG$news_days, "d")
  url <- paste0("https://news.google.com/rss/search?q=", URLencode(q, reserved = TRUE), "&hl=en-US&gl=US&ceid=US:en")
  x <- if (nzchar(FIXTURES)) xml2::read_xml(file.path(FIXTURES, "news.xml")) else xml2::read_xml(url)
  items <- xml2::xml_find_all(x, "//item")
  df <- tibble(title = xml2::xml_text(xml2::xml_find_first(items, "title")),
               link = xml2::xml_text(xml2::xml_find_first(items, "link")),
               src = xml2::xml_text(xml2::xml_find_first(items, "source")),
               date = as.Date(strptime(substr(xml2::xml_text(xml2::xml_find_first(items, "pubDate")), 6, 16), "%d %b %Y"))) %>%
    mutate(title = trimws(ifelse(!is.na(src) & endsWith(title, paste0(" - ", src)), substr(title, 1, nchar(title) - nchar(src) - 3), title))) %>%
    filter(grepl("die|dying|death|dead", title, ignore.case = TRUE), grepl("rikers|jail|custody|correction|doc\\b", title, ignore.case = TRUE)) %>%
    distinct(title, .keep_all = TRUE) %>% arrange(desc(date)) %>% head(CONFIG$news_max_items)
  if (nrow(df) == 0) stop("no matching items")
  lapply(seq_len(nrow(df)), function(i) list(format(df$date[i], "%d %b %Y"), df$src[i], df$title[i], df$link[i]))
}, error = function(e) { note("News feed not updated: ", conditionMessage(e)); old_news })

# ---------------------------------------------------------------------------
# 8. Write, or stop if anything failed
# ---------------------------------------------------------------------------
if (length(.notes)) cat("Notes:\n", paste0("  - ", .notes, collapse = "\n"), "\n")
if (length(.problems)) {
  cat("BUILD STOPPED. Nothing was published. Problems:\n", paste0("  - ", .problems, collapse = "\n"), "\n")
  quit(status = 1)
}

out <- list(
  built = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  deaths = lapply(deaths, function(v) lapply(v, function(z) if (is.na(z)) NULL else z)),
  adp_annual_pre = setNames(as.list(adp_annual_pre$adp), adp_annual_pre$year),
  adp = setNames(lapply(seq_len(nrow(adp)), function(i) list(round(adp$adp[i]), adp$source[i], adp$provisional[i])), adp$month),
  stab = lapply(stab, as.list),
  uof = uof, los = los, admissions = admissions,
  snapshot = list(format(TODAY), n_now), over1y = over1y, charges = charges, news = news,
  notes = as.list(.notes)
)
dir.create("site", showWarnings = FALSE)
writeLines(toJSON(out, auto_unbox = TRUE, null = "null", digits = NA), "site/data.json")
cat("Built site/data.json. Deaths through", names(deaths)[length(deaths)], "| stabbings through", month_key(st$last),
    "| ADP through", tail(adp$month, 1), "| in custody", n_now, "\n")

# Inline the data into the page so it loads in one request and embeds cleanly
tpl <- paste(readLines("site_template.html", warn = FALSE), collapse = "\n")
json <- gsub("</", "<\\/", paste(readLines("site/data.json", warn = FALSE), collapse = ""), fixed = TRUE)
page <- sub("__DATA__", json, tpl, fixed = TRUE)
writeLines(page, "site/index.html")
cat("Wrote site/index.html\n")
