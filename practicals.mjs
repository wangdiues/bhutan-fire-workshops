export const projects = {
  wui: "thimphu_WUI",
  burn: "thimphu_paro_burn_severity",
};

export const practicals = [
  {
    course: "wui", folder: "01-sensitivity", title: "Map where buildings meet wildland",
    stages: ["02"], guide: 6, packages: ["jsonlite", "openxlsx", "terra"],
    method: "The wildland–urban interface (WUI) is where settlements and wild vegetation meet. A raster is a map made of small square cells. Here each cell is 50 m by 50 m. Intermix cells contain enough buildings and vegetation. Interface cells have enough buildings, less vegetation within their neighbourhood, and a large wildland patch nearby.",
    why: "Drawing a buffer around every house would miss how buildings and vegetation cluster across a landscape. A rule based on these patterns gives a consistent map across Thimphu, and changing one rule setting shows how much the map depends on that choice.",
    steps: [
      "Place building footprints on a common grid. Count buildings within a moving circle around each cell and divide by the circle’s area.",
      "Measure the vegetation share around the same cell. Identify sufficiently large groups of connected vegetated cells and calculate each cell’s distance to a patch.",
      "Apply the reviewed density, vegetation, patch-size and distance rules. Change one setting at a time in the sensitivity comparison and record how many buildings stay in WUI."
    ],
    formula: "Density = number of buildings in the neighbourhood ÷ neighbourhood area (km²). One 50 m cell = 0.0025 km².",
    result: "The reviewed structural baseline covers 191.795 km², equivalent to 76,718 cells of 0.0025 km² each. The sensitivity workbook records how the area and the share of buildings change as one rule setting changes. A larger mapped area can reflect a broader rule as well as a change in the landscape.",
    use: "Use the map to shortlist settlement edges for a field visit and compare how sensitive the shortlist is to the chosen WUI definition. Confirm vegetation and access on the ground before deciding on investments.",
    question: "Which rule change has the largest effect on the mapped share of buildings? What would you inspect in the field before accepting that change?",
    figures: [["fig_02_wui_baseline_map.png", "Reviewed structural WUI map for Thimphu. Read the class legend before comparing the distribution of interface and intermix."]],
    files: [
      ["summary_file", "data/derived/results_layers.json", "Reviewed baseline area and building counts."],
      ["sensitivity_file", "outputs/01-sensitivity/process_data/04_sensitivity_one_at_a_time.xlsx", "How the results respond when one WUI setting changes."],
      ["map_file", "data/derived/wui_class_baseline_50m.tif", "Actual 50 m WUI class map for Thimphu."],
    ],
    rebuildInputs: "50 m grid and boundaries, building footprints, vegetation shares, and forest type. The project settings supply the reviewed rule parameters.",
    import: `baseline <- jsonlite::read_json(summary_file, simplifyVector = TRUE)
sensitivity <- openxlsx::read.xlsx(sensitivity_file)
wui_map <- terra::rast(map_file)`,
    inspect: `print(head(sensitivity))
print(wui_map)`,
    calculate: `results <- data.frame(
  measure = c("Buildings in Thimphu", "Mapped WUI area (km2)", "Buildings in WUI (%)"),
  value = c(baseline$buildings_thimphu, baseline$baseline_wui_km2,
    100 * baseline$baseline_building_share)
)
print(results, row.names = FALSE)`,
    plot: 'terra::plot(wui_map, main = "Reviewed structural WUI classes")',
    expected: ["Sensitivity rows and the dimensions, cell size and extent of the reviewed map.", "191.795 km² of WUI and about 98.7% of the Open Buildings footprints under this baseline rule.", "A map with the reviewed WUI classes and a legend."],
  },
  {
    course: "wui", folder: "02-calibration", title: "Test WUI rules against historical fire",
    stages: ["03"], guide: 6, packages: ["jsonlite"],
    method: "Historical fire association compares each WUI rule with recorded fire evidence near buildings. Sensitivity is the share of buildings near recorded fire that the rule marks as WUI. Specificity is the share of buildings away from recorded fire that it marks as outside WUI.",
    why: "A broad rule can capture many buildings near fire by classifying almost every building as WUI. Checking both measures shows whether a rule distinguishes the two groups. It also reveals the difference between fitting a rule and testing it in another area.",
    steps: ["Measure proximity to the reviewed fire evidence. Mark buildings as near or away under the analysis distance.",
      "For each candidate rule, calculate sensitivity and specificity and combine them into Youden J.",
      "Compare the chosen rule with the structural baseline. Repeat selection while holding out one gewog, a local administrative area, and score the rule on the held-out area."],
    formula: "Youden J = sensitivity + specificity − 1. A value near 0 means the rule shows little ability to distinguish the two groups.",
    result: "The selected rule gives J = 0.230 on data used for selection and J = 0.108 in the held-out comparison. The reviewed structural baseline gives J = 0.053 in the in-sample comparison. These values describe association with the recorded evidence. Unrecorded fires and uneven reporting can affect them.",
    use: "Use historical fire proximity to prioritise verification and outreach around exposed settlements. Keep uncertainty visible when transferring a rule to another gewog.",
    question: "What does the fall from 0.230 to 0.108 tell you about using this rule in a new area?",
    figures: [["fig_03_skill_vs_area.png", "Reviewed comparison of rule performance and mapped WUI area. The mapped area changes as rules change."]],
    files: [
      ["summary_file", "data/derived/results_calibration.json", "Selected parameters, structural comparison, held-out score and bootstrap interval."],
      ["rule_file", "data/derived/calibration_all_rules.csv", "One row per candidate combination, with scores for several evidence sets and fire distances."],
    ],
    rebuildInputs: "Stage 02 grid layers, mapped buildings, administrative areas and the reviewed historical fire evidence layers.",
    import: `review <- jsonlite::read_json(summary_file, simplifyVector = TRUE)
rules <- read.csv(rule_file, check.names = FALSE)`,
    inspect: `print(review$selected)
print(head(rules[, c("D", "V", "P", "R", "A", "veg", "wui_km2")]))`,
    calculate: `results <- data.frame(
  comparison = c("Baseline", "Selected", "Held out"),
  youden_J = c(review$J_baseline, review$J_selected, review$cv_J)
)
print(results, row.names = FALSE)
cat("Rules reviewed:", nrow(rules), "\\n")`,
    plot: 'barplot(results$youden_J, names.arg = results$comparison, col = "#176451", ylim = c(0, 0.3),\n  ylab = "Youden J", main = "Historical fire association")',
    expected: ["Rule settings for density, vegetation, patch size, moving radius and distance, plus example result rows.", "The reviewed scores about 0.053, 0.230 and 0.108, based on a table of 2,160 candidate rules.", "The held-out bar is lower than the selected-rule bar. This illustrates why the held-out score matters."],
  },
  {
    course: "wui", folder: "03-growth", title: "Track settlement-related change",
    stages: ["04"], guide: 6, packages: ["terra"],
    method: "Dynamic World estimates land cover from satellite imagery. Its built-share layer estimates the fraction of a cell covered by built surfaces. The workshop uses it as a settlement proxy, an indirect indicator for areas likely to be built up.",
    why: "Building maps from a single year cannot show where settlement patterns were changing. A consistent satellite record lets staff map likely changes and identify where more recent building checks would help.",
    steps: ["For each year, compare the built share in a moving neighbourhood with the project’s reviewed threshold.",
      "Use the same vegetation and WUI criteria to estimate annual WUI. Keep partial years in the table and distinguish them from complete years when comparing changes.",
      "Compare early and late three-year periods by majority class. Summarise the annual trend with the median of the slopes between each pair of complete years."],
    formula: "A pairwise slope = (WUI area in later year − WUI area in earlier year) ÷ years between the observations.",
    result: "The reviewed WUI proxy is 131.785 km² in 2017 and 154.370 km² in 2025. Those two years differ by 22.585 km² over eight years. The script goes further by using the median slope across all pairs of complete years. Coverage matters because clouds and partial years can change how much evidence supports an estimate.",
    use: "Use newly persistent areas to target updated building inventories and site checks. Consider imagery coverage alongside apparent growth before directing resources.",
    question: "Why does the practical report the observation count alongside each annual area estimate?",
    figures: [["fig_02_wui_time_series.png", "Reviewed annual built-up and WUI proxies for Thimphu. Open symbols mark partial years."]],
    files: [
      ["annual_file", "data/derived/wui_annual_dynamic_world.csv", "Annual built-up and WUI proxy area with observation counts."],
      ["change_file", "data/derived/wui_change_2017_19_to_2023_25_50m.tif", "Reviewed majority-class change map for the early and late periods."],
    ],
    rebuildInputs: "2016–2026 annual Dynamic World shares, structural WUI layers and the reviewed calibration output.",
    import: 'annual <- read.csv(annual_file)\nchange_map <- terra::rast(change_file)',
    inspect: 'print(annual[, c("year", "partial", "wui_km2", "mean_valid_obs")], row.names = FALSE)',
    calculate: `results <- annual[!annual$partial, c("year", "wui_km2", "mean_valid_obs")]
pairs <- utils::combn(seq_len(nrow(results)), 2)
area_change <- results$wui_km2[pairs[2, ]] - results$wui_km2[pairs[1, ]]
years_between <- results$year[pairs[2, ]] - results$year[pairs[1, ]]
cat("Median pairwise slope (km2/year):", median(area_change / years_between), "\\n")`,
    plot: `plot(results$year, results$wui_km2, type = "b", col = "#176451",
  xlab = "Complete year", ylab = "WUI settlement proxy (km2)")
terra::plot(change_map, main = "Reviewed early-to-late WUI change")`,
    expected: ["Annual estimated areas and observation counts, with partial years flagged.", "A robust slope in km² per year calculated only over complete years.", "A trend chart and an actual change map. Use the plot history arrows to see both."],
  },
  {
    course: "wui", folder: "04-exposure", title: "Compare exposure and access by gewog",
    stages: ["05"], guide: 6, packages: ["jsonlite", "terra"],
    method: "Exposure counts the people and buildings in a mapped area that may be affected. The workshop compares exposure, proximity to recorded fire, susceptibility and walking access by gewog. Susceptibility describes how favourable the mapped conditions are for fire.",
    why: "A large exposed population and a small hard-to-reach settlement can both need attention for different reasons. Keeping the indicators visible helps staff understand why places rank differently.",
    steps: ["Overlay gridded population and buildings with the WUI map, then add up values by gewog.",
      "Compare how many WUI buildings are near known fire, in high-susceptibility areas or have long walking access.",
      "Read the reviewed priority rank. Inspect the components before selecting areas for field verification or community planning."],
    formula: "Population exposure here = sum of gridded population estimates in WUI cells.",
    result: "The reviewed estimate is about 126,584 people and 27,196 buildings in WUI. Population is modelled on a grid, and the rank summarizes the chosen indicators. Compare the individual columns before interpreting what the rank means for a specific gewog.",
    use: "Identify communities for preparedness visits, check access routes with local staff and plan field visits that test whether the mapped settings are accurate.",
    question: "Choose two gewogs. Which indicator would you use for a community meeting and which would you use for an access check?",
    figures: [["fig_02_wui_buildings_by_gewog.png", "Reviewed breakdown of WUI buildings by gewog. Compare the components as well as the total."]],
    files: [
      ["table_file", "data/derived/exposure_by_gewog.csv", "Reviewed exposure and priority indicators for each gewog."],
      ["summary_file", "data/derived/results_exposure.json", "Dzongkhag totals and field-sample counts."],
      ["map_file", "data/derived/wui_priority_50m.tif", "Actual priority classes which combine mapped susceptibility and fire evidence."],
    ],
    rebuildInputs: "Population, building, road, walking-access and susceptibility inputs, with the calibrated WUI layers and fire evidence.",
    import: 'exposure <- read.csv(table_file)\nreview <- jsonlite::read_json(summary_file, simplifyVector = TRUE)\npriority_map <- terra::rast(map_file)',
    inspect: 'print(head(exposure[, c("unit", "wui_people", "wui_buildings", "priority_rank")]))',
    calculate: `columns <- c("unit", "wui_people", "wui_buildings", "wui_fire_exposed_buildings",
  "wui_high_susceptibility_buildings", "wui_remote_buildings", "priority_rank")
results <- exposure[order(exposure$priority_rank), columns]
print(results, row.names = FALSE)
cat("Estimated people in WUI:", round(review$wui_people), "\\n")`,
    plot: 'terra::plot(priority_map, main = "Reviewed WUI priority classes")',
    expected: ["Gewog names and separate population, building and ranking columns.", "A ranked table and an estimated 126,584 WUI residents.", "A local priority map. Compare the mapped categories with the table and avoid sharing field answer keys."],
  },
  {
    course: "wui", folder: "05-fire-mgmt", title: "Interpret fire-management screening",
    stages: ["15", "16"], guide: 6, packages: ["terra"],
    method: "Screening applies the reviewed rules to remove ineligible areas and rank the remaining fire-line and prescribed-burn candidates. An exclusion funnel shows how much candidate land or line length remains after adding one constraint at a time.",
    why: "A high score is useful only after the candidate passes the required constraints. Showing each exclusion makes it possible to explain why many apparently suitable areas did not remain in the shortlist.",
    steps: ["Start from prepared candidate edges or cells and apply the reviewed land, terrain, vegetation and infrastructure exclusions.",
      "Compare the remaining length or area after each exclusion. The analysis ranks the eligible candidates and selects combinations that meet the documented constraints.",
      "Read the weight-sensitivity outputs to see whether the shortlist is stable when the relative importance of indicators changes."],
    formula: "Area removed at a step = previous eligible area − current eligible area. The screening score combines the criteria with the reviewed weights.",
    result: "The reviewed screening identified about 112 ha of eligible land and seven candidate sites totalling about 25 ha. The map and tables describe candidate screening under the project’s inputs. Field checks are necessary to confirm the terrain, access and local constraints.",
    use: "Use the exclusion and suitability evidence to plan joint field visits and discuss alternatives with Bhutan’s forestry staff and land managers.",
    question: "Which exclusion removes the greatest eligible area? What field observation would help confirm that rule locally?",
    figures: [["fig_08_exclusion_funnels.png", "Reviewed cumulative screening totals. Each successive row or bar adds another condition."]],
    files: [
      ["line_file", "data/derived/fire_mgmt/fire_line_exclusion_funnel.csv", "Counts and length after each fire-line constraint."],
      ["area_file", "data/derived/fire_mgmt/rx_eligibility_funnel.csv", "Remaining cells and hectares after each area constraint."],
      ["sensitivity_file", "data/derived/fire_mgmt/sensitivity_rx_sites.csv", "How selected sites respond when ranking weights change."],
      ["map_file", "data/derived/fire_mgmt/rx_suitability_50m.tif", "Reviewed local map of suitability categories."],
    ],
    rebuildInputs: "Calibrated WUI, terrain and soil, mapped access, vegetation and fuel, private-land cover, and prepared management boundaries and exclusions.",
    import: 'lines <- read.csv(line_file)\nareas <- read.csv(area_file)\nweights <- read.csv(sensitivity_file)\nsuitability <- terra::rast(map_file)',
    inspect: 'print(lines[, c("rule", "cumulative_km")], row.names = FALSE)\nprint(weights)',
    calculate: `results <- areas[, c("rule", "cumulative_ha")]
previous <- c(NA, head(results$cumulative_ha, -1))
results$removed_ha <- previous - results$cumulative_ha
print(results, row.names = FALSE)`,
    plot: 'terra::plot(suitability, main = "Reviewed management screening classes")',
    expected: ["Remaining kilometres after each line exclusion and the reviewed weight-sensitivity rows.", "Remaining and removed area in hectares at each step. The first row has no previous row.", "The actual local suitability map. Compare it with the exclusion totals before planning a field visit."],
  },
  {
    course: "burn", folder: "01-severity", title: "Detect spectral change after a forest fire",
    stages: ["02"], guide: 6, packages: ["jsonlite", "terra"],
    method: "Satellites measure reflected light. Near-infrared (NIR) and shortwave infrared (SWIR) are bands outside visible light. The normalized burn ratio (NBR) combines them. Changes in NBR can reveal where the surface changed after a fire.",
    why: "A post-fire image alone cannot tell whether a dark area was previously dark. The analysis compares before and after images, masks unreliable pixels and estimates background change from surrounding areas.",
    steps: ["Compare screened imagery windows and keep pixels with sufficient vegetation and usable observations.",
      "Subtract post-fire NBR from pre-fire NBR, remove the reference-ring offset and calculate the relativized burn ratio (RBR). This ratio scales the change by the pre-fire NBR.",
      "Apply the reviewed threshold and minimum patch area. Compare detection on held-out background zones and independent thermal evidence, which measures heat or burned area separately."],
    formula: "NBR = (NIR − SWIR) ÷ (NIR + SWIR). Corrected dNBR = pre-fire NBR − post-fire NBR − reference-ring offset.",
    result: "The reviewed input has 91 incident–sensor pairs, 46 incidents with usable imagery and 21 mapped incidents. The practical compares sensors and displays a reviewed example map. A detected change is spectral evidence. Ecological severity requires field calibration.",
    use: "Use mapped change and confidence checks to prioritise reconnaissance and identify where to collect field evidence. Review small fires and cloudy windows carefully before drawing conclusions.",
    question: "Why can a real fire appear in the incident records and still have no detectable satellite patch?",
    figures: [["fig_05_detection_by_area_sensor.png", "Reviewed detection by reported area and sensor. The intervals show sampling uncertainty."]],
    files: [
      ["pairs_file", "data/derived/incident_sensor_metrics.csv", "One row for each usable incident and sensor. Includes the detection flag and area."],
      ["summary_file", "data/derived/results_severity.json", "Reviewed coverage, thresholds and independent evaluation results."],
      ["example_file", "config/training_examples.json", "Chooses the same approved real event for every participant."],
    ],
    extraPaths: `example <- jsonlite::read_json(example_file)
map_name <- paste0(example$mapping_event, "_", example$mapping_sensor, "_severity.tif")
map_file <- file.path(workshop_folder, "data/derived/severity_rasters", map_name)`,
    rebuildInputs: "Approved incident reports, seasonal and adjacent-window composites, annual land-cover masks, terrain, FIRMS and MCD64A1 evidence, and the approved derived NFI fuel layer for the optional fuel models.",
    import: 'pairs <- read.csv(pairs_file)\nreview <- jsonlite::read_json(summary_file, simplifyVector = TRUE)\nchange_map <- terra::rast(map_file)',
    inspect: 'print(with(pairs, table(sensor, detected, useNA = "ifany")))\nprint(review[c("rule_q", "rule_min_ha", "placebo_selection", "placebo_heldout")])',
    calculate: `results <- aggregate(detected ~ sensor, data = pairs, FUN = mean)
results$detection_pct <- 100 * results$detected
print(results[, c("sensor", "detection_pct")], row.names = FALSE)
print(review[c("pairs", "incidents_imaged", "incidents_mapped")])`,
    plot: 'terra::plot(change_map, main = "Reviewed spectral change for the training event")',
    expected: ["Detection counts for each sensor, with the selected threshold and background-check rates.", "Detection percentages by sensor, and coverage counts of 91 pairs, 46 imaged incidents and 21 mapped incidents.", "An actual example map from the participant data. Read the change categories alongside the legend and input coverage."],
  },
  {
    course: "burn", folder: "02-recovery", title: "Read the signal in the years after fire",
    stages: ["03"], guide: 6, packages: ["jsonlite", "openxlsx"],
    method: "A spectral trajectory tracks a satellite signal across time. The workshop compares NBR inside each mapped fire patch with NBR in a surrounding reference ring and removes the same contrast from before the fire.",
    why: "The ring helps account for changes common to the surrounding landscape. A mixed model recognises that several observations come from the same fire and that fewer fires have long follow-up.",
    steps: ["Extract annual NBR for the fire patch and reference ring from the Landsat record.",
      "Subtract the ring from the patch in each year, then subtract the pre-fire contrast to give a baseline-adjusted series.",
      "Fit the reviewed mixed model with recurring observations for each fire. Read estimates with their uncertainty and compare them with the number of fires represented each year."],
    formula: "Adjusted NBR = (patch − ring in that year) − (patch − ring before fire).",
    result: "The model uses 21 mapped incidents. By year 4, six contribute observations. A rising trajectory toward zero suggests the difference in satellite signal has narrowed. The evidence concerns reflectance, so species recovery and fuel changes require field evidence.",
    use: "Combine trajectory and follow-up coverage to decide which areas should be revisited or monitored for longer after fire.",
    question: "Why should you compare the number of incidents represented before interpreting the last year?",
    figures: [["fig_03_reference_and_followup.png", "Reviewed reference-ring check and the number of fires represented in each year."]],
    files: [
      ["table_file", "outputs/02-recovery/process_data/02_incident_year_trajectory.xlsx", "Annual patch and ring contrasts for individual mapped fires."],
      ["model_file", "data/derived/results_recovery.json", "Reviewed model estimates, intervals and coverage counts."],
    ],
    rebuildInputs: "Selected burn patches and incident points, along with annual Landsat NBR and valid observation counts for 2012–2025.",
    import: 'trajectory <- openxlsx::read.xlsx(table_file)\nreview <- jsonlite::read_json(model_file, simplifyVector = TRUE)',
    inspect: 'print(table(trajectory$t))\nprint(review$followup, row.names = FALSE)',
    calculate: `results <- review$emm[, c("t", "emmean", "lower.CL", "upper.CL")]
results <- results[order(results$t), ]
print(results, row.names = FALSE)
cat("Incidents in the model:", review$n_incidents, "\\n")`,
    plot: `plot(results$t, results$emmean, type = "b", xlab = "Years since fire",
  ylab = "Adjusted NBR", ylim = range(results$lower.CL, results$upper.CL))
segments(results$t, results$lower.CL, results$t, results$upper.CL)
abline(h = 0, lty = 2)`,
    expected: ["Different numbers of observations per year, especially in later years.", "A reviewed estimate and confidence interval for each modelled year.", "A trajectory with uncertainty marks and the zero-contrast reference line."],
  },
  {
    course: "burn", folder: "03-cbi-plan", title: "Design field checks for spectral change",
    stages: ["04"], guide: 6, packages: ["jsonlite"],
    method: "The Composite Burn Index (CBI) is a way to record fire effects observed on the ground. Calibration plots link field scores to spectral change. A different, independent accuracy sample supports map accuracy and class-area estimation.",
    why: "Clean examples are useful for learning the link between field measurements and satellite values. Accuracy also needs a sample drawn across the target area with known selection probabilities so that results can represent the area.",
    steps: ["Read the reviewed map-derived strata, the groups of places assigned to the same mapped class.",
      "Compare the two sampling designs. Calibration uses relatively uniform neighbourhoods. The independent accuracy design uses declared inclusion probabilities.",
      "Calculate design weights from these probabilities. Actual field reference labels are needed before calculating accuracy or adjusted area."],
    formula: "Design weight = 1 ÷ probability of being selected. The reviewed low-change stratum has probability about 0.01834, corresponding to a weight of about 54.5.",
    result: "The reviewed design has 100 calibration plots, including 80 primary and 20 reserve, and 200 independent accuracy points. These are planned sample counts. A large design weight reflects a lower selection probability in its stratum.",
    use: "Use the separate sampling designs when organising field teams, and maintain independent reference labels for accuracy assessment across the accessible survey area.",
    question: "Why would the selection of especially uniform map pixels make a poor independent accuracy sample?",
    figures: [],
    files: [
      ["calibration_file", "data/derived/field_plan/A_calibration_plots.csv", "Planned calibration plots, strata and primary or reserve roles."],
      ["accuracy_file", "data/derived/field_plan/B_accuracy_sample.csv", "Independent accuracy design with strata, area and inclusion probability."],
      ["summary_file", "data/derived/results_field_plan.json", "Reviewed sample counts for both designs."],
    ],
    rebuildInputs: "Mapped incident windows and selected spectral-class rasters, elevation, slope and walking access.",
    import: 'calibration <- read.csv(calibration_file)\naccuracy <- read.csv(accuracy_file)\nreview <- jsonlite::read_json(summary_file, simplifyVector = TRUE)',
    inspect: 'print(with(calibration, table(stratum, role)))\nprint(table(accuracy$stratum))',
    calculate: `results <- unique(accuracy[, c("stratum", "inclusion_probability", "stratum_area_ha")])
results$design_weight <- 1 / results$inclusion_probability
print(results, row.names = FALSE)
print(review[c("n_A", "n_A_primary", "n_A_reserve", "n_B")])`,
    plot: 'barplot(c(Calibration = nrow(calibration), Accuracy = nrow(accuracy)),\n  ylab = "Planned points", col = c("#176451", "#a14b27"), main = "Two field samples")',
    expected: ["Planned sampling counts by mapped class and by calibration role.", "Design weights and the reviewed 100 calibration and 200 accuracy points.", "Two bars showing the number of proposed points in each sampling design."],
  },
];
