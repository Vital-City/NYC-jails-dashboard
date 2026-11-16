# NYC jails dashboard

A Vital City page tracking New York City's jails: population, admissions, length of stay, deaths in custody, stabbings and slashings, and use of force. It rebuilds itself every Monday from public data and Vital City's own records.

## How it updates

| Job | When | What it does |
|---|---|---|
| Daily custody snapshot | Every day, about 5:30 p.m. | Saves the day's count of people in custody from NYC Open Data. A missed day can't be recovered, so this runs daily. |
| Weekly dashboard build | Mondays, about 9:45 a.m. | Pulls every source, runs the checks, rebuilds `site/index.html` and publishes it to GitHub Pages. |

Both can be run by hand from the **Actions** tab: pick the workflow, then **Run workflow**.

## Where the numbers come from

| Measure | Source | Updates |
|---|---|---|
| Deaths in custody | Vital City Google Sheet, "Jails dashboard: deaths by month" | By hand, when a death is confirmed |
| Use of force | Vital City Google Sheet, "Jails dashboard: use of force (MMR)", from the Mayor's Management Report | By hand, each September |
| Average daily population (ADP) | Through June 2019: Vital City compilation (`data/manual/adp_monthly_compiled.csv`). From July 2019: rebuilt from NYC Open Data [Inmate Discharges](https://data.cityofnewyork.us/d/94ri-3ium) and [Daily Inmates In Custody](https://data.cityofnewyork.us/d/7479-ugqb). Months after the latest discharge data use the average of the saved daily counts. | Automatic |
| Stabbings and slashings | NYC Open Data [Inmate Incidents: Slashing and Stabbing](https://data.cityofnewyork.us/d/gakf-suji) | Automatic, complete months only |
| Admissions | NYC Open Data [Inmate Admissions](https://data.cityofnewyork.us/d/6teu-xtgp) | Automatic, complete months only |
| Length of stay | 2005 to 2013: earlier Vital City chart (`data/manual/los_2005_2013.csv`). From 2014: mean of discharge date minus admission date, Inmate Discharges | Automatic |
| Held more than a year; most serious charge | Daily Inmates In Custody. Charge classes come from `data/manual/charge_classes.csv`, which maps Penal Law sections to felony classes; attempts are one class lower except the sections in `attempt_stays_class_AI.csv` | Automatic |
| In the news | Google News search for deaths in city jails, last 60 days | Automatic; listed for tracking, not verified |

Rates are per 1,000 ADP. Year-to-date rates compare the same months in every year; when incident data run past the latest month of ADP, the most recent ADP is used. Open Data excludes sealed cases, so the rebuilt ADP runs about 1% below official figures.

## Checks before publishing

The build stops without publishing if any of these fail. The live page keeps the previous version and GitHub emails whoever last edited the workflow files.

- The deaths sheet has its Year and Jan to Dec columns, consecutive years, no future year and whole numbers from 0 to 25.
- The use of force sheet has no blank or non-numeric cells and consecutive fiscal years.
- ADP stays between 3,000 and 15,000 and doesn't change more than 15% in a month (March to June 2020 excepted).
- The stabbing data has a complete month within the last three months, and the latest month is no more than three times any month in the prior year.
- The custody snapshot has between 3,000 and 15,000 people.
- Inmate Discharges has been updated in the last 75 days.

Warnings that don't stop the build (printed in the run log): fiscal-year ADP more than 1.5% from the MMR figure, more than 20% of top charges unclassified, or the news search failing (last week's list is kept).

## Updating the data by hand

- **A death:** open the deaths sheet and add 1 to that month's cell. Enter 0 for months with no deaths. Start a new row each January. Leave future months blank.
- **Use of force, each September:** add a row to the use of force sheet with the new fiscal year, "Incidents of use of force" and average daily population from the Department of Correction chapter of the Mayor's Management Report.
- **Charge classes:** if the run log warns about unclassified charges, add the Penal Law sections to `data/manual/charge_classes.csv`.

Don't rename the sheets' columns; the build reads them by name.

## First-time setup

1. Upload every file in this folder to the repository, keeping the folder structure.
2. In `config.json`, replace the two `PASTE_...` values with the published CSV links of the two Google Sheets (File > Share > Publish to web > Comma-separated values).
3. **Settings > Pages:** set **Source** to **GitHub Actions**.
4. **Settings > Actions > General > Workflow permissions:** select **Read and write permissions** and save.
5. **Actions** tab: run **Daily custody snapshot**, then **Weekly dashboard build**. The page appears at `https://vital-city-nyc.github.io/jails-dashboard/`.

## Files

```
R/common.R            shared helpers (data pulls, checks)
R/snapshot.R          daily job
R/build.R             weekly job
site_template.html    the page; the build fills in the data
site/                 the published page and its data (written by the build)
data/snapshot_counts.csv  one row per day: people in custody
data/snapshots/       last 60 days of full snapshots (admission dates only)
data/manual/          figures that don't come from a live source
config.json           sheet links and settings
tests/make_fixtures.R builds fake data for testing without the internet
```
