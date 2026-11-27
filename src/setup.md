---
layout: page.njk
title: RStudio setup
permalink: setup.html
---
# RStudio setup

1. Install R and RStudio Desktop. The workshop projects were tested with R 4.4.0 on Windows. Install the packages listed in `WORKSHOP_START.txt` inside the participant ZIP while you have internet access.
2. Download and extract the workshop ZIP to a writable local folder. Open the `.Rproj` file inside it. Keep the extracted ZIP as your reference copy and make a second working copy for full-stage runs.
3. From RStudio’s Files pane, open a lesson in `r_studio_run/`. Select the setup block and press **Ctrl+Enter**. Then run the remaining blocks in order. Click **Source** to run the whole file. Maps from the original lesson workflow are saved under `logs/`.
4. Use the Console for a full analysis script. Start with the first stage listed on the workshop page.

```r
source("START_HERE.R")
check_project("02")
# Proceed when preflight says PASS.
run_project("02")
```

Read the log path printed in the Console and use the workshop page to find the outputs. A preflight pass confirms package and file presence and R syntax. Compare the results with the expected outputs before using them.

## Troubleshooting

- **Missing settings or files.** Reopen the `.Rproj` from the fully extracted ZIP. Check that `getwd()` points to that folder and that the data folders appear beneath it.
- **Missing R package.** Install the packages named in preflight and restart RStudio. If `jsonlite` is missing, install it first and rerun the check.
- **Drive requests access.** Sign in with the Google account you registered for the workshop and request access from the organizer.
- **A recipe fails midway.** Read the full file under `logs/`. Rerun from a fresh working copy if the failed stage had already started replacing outputs.

[RStudio Desktop](https://posit.co/download/rstudio-desktop/) · [Running code in RStudio](https://docs.posit.co/ide/user/ide/guide/code/execution.html)
