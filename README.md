# HCPP manuscript reproduction

Maintainer: Xiaoai. Release: 2026-09-26. Manuscript target: `final draft0923_开会.docx`.

The entry point constructs `charls.dta` and `dataset 0507.dta` from the listed upstream inputs, estimates the manuscript models, and exports 19 numbered aggregate tables and six figures. Each execution uses a separate run directory.

## Quick start

1. Obtain the licensed CHARLS raw modules, Harmonized CHARLS C/D files, PSU files, and the external city/COVID/PM2.5 source files listed in `verification/INPUT_MANIFEST.json`. These are **not included**. The municipal input must be the **2011–2020 workbook that includes all four municipalities**.
2. Use licensed Stata 18. Install Python and the exact Python dependencies in `requirements.txt` in your own environment: `python3 -m pip install -r requirements.txt`.
3. Copy `config.example.do` to `config.local.do`; enter your actual input locations and Python executable. The private override is excluded from GitHub. Do not change the reference hashes just to bypass a source mismatch.
4. Set Stata's working directory to this repository, then run:

```stata
do RUN_ALL.do
```

The final success message is `REPRODUCTION_PACKAGE_RUN_VERIFIED`. Also check that the run contains `verification_passed.ok` and that `verification.json` has `passed: true`. Stata's batch-process exit code by itself is not sufficient.

Optional data construction:

```stata
do RUN_ALL.do build
```

Each invocation makes a fresh directory under `runs/`. Missing or mismatched inputs stop the run. Harmonized files are upstream inputs; the code does not claim to reconstruct every Harmonized variable from raw questionnaires.

## Directory structure

```text
RUN_ALL.do                 Entry point: data construction, models, figures, export, validation
config.do                  Portable defaults and private override loader
config.example.do          Copy to config.local.do and edit paths
pipeline_v4.do             Established cleaning and main city-clustered analyses
support/                   Python helpers and final supplementary Stata modules
vendor/                    Third-party Stata commands, original attribution preserved
verification/              Input hashes and aggregate reference results
requirements.txt           Python versions
MANIFEST_SHA256.json        Release file checksums
runs/                      Local generated data/results; excluded from upload
```

`support/`, `vendor/`, and `verification/` must be actual directories, not three unextracted ZIP files. An outer repository ZIP may be extracted once normally.

## Retained specifications

- Principal DID: all 13 controls, city/year fixed effects, city-clustered standard errors; 94 cities, including 10 treated and 84 control cities.
- Wild cluster inference: null-imposed Webb and Rademacher weights, 9,999 replications, seed 2025. Algebraically equivalent `areg` is used for wild bootstrap; conventional uncertainty comes from the primary `reghdfe` fit.
- Event study: 2015 reference; city-clustered confidence intervals and joint 2011/2013 pre-trend test.
- PSM: respondent means of 12 covariates from eligible 2011/2013/2015 observations only; Epanechnikov kernel, bandwidth 0.06, common support. Final DID includes age and the full control set. Inference conditions on estimated weights.
- Table 5: Panel A uses available pathway/control observations, including missing outcomes. Panel B additionally requires an observed outcome. Six-test BH correction is applied separately within each panel.
- A1a: traditional Sobel with city-clustered path SEs and path-specific samples, plus a joint-covariance delta-method diagnostic. Both are unadjusted supplementary diagnostics.
- A1b: 2,000 whole-city resamples for each of six products, using one common sample per pathway and BH correction across products. Table 5 Panel A coefficients are not substituted into these common-sample products. Empirical sign-tail summaries are not null-imposed bootstrap tests.
- Heterogeneity: nine descriptive subgroup models, but only five pooled Group × DID tests in A3. The middle-income descriptive subgroup remains in Table 4; there is no additional middle-income A3 interaction.
- A4: low income versus combined middle/high income; other groupings retained. Full Chow tests concern specified intercept/slopes jointly, not the DID coefficient alone.
- City placebo: 5,000 assignments of 10 out of 94 cities, preserving all within-city observations. Accelerated calculations are checked against Stata draws. Pre-policy placebo dates are also reported.
- COVID: additive model and interaction centered at 0.1397 thousand cases, the unweighted treated-city mean in 2020; margins use the full clustered coefficient covariance. Unknown case counts are not set to invented zero values.
- Nonlinear fits: ordered and binary logit with all 13 controls, explicit city/year indicators, and city clustering. Exclude 23 boundary-separated observations from Anshan before both fits, giving 16,638 observations in 93 cities. Coefficients are supplementary log-odds diagnostics. Their overall cluster-robust Wald tests are unavailable.
- DID-specific proportional odds: a partial proportional-odds likelihood allows only the DID slope to differ across three thresholds. The city-clustered Wald test concerns the two DID restrictions, not all slopes. Starting values are estimated within each execution. Outputs include `did_parallel_lines.csv` and `did_threshold_slopes.csv`.
- The fully generalized ordered-logit specification is excluded from the reported models because numerical checks did not yield a stable fit with valid category probabilities. It is not executed by the principal reproduction entry point.
- Respondent fixed effects: year effects and city clustering; singleton exclusions and absorbed controls are documented.
- Income missingness: wave/treatment rates and retained-versus-missing comparisons only. These analyses report descriptive differences rather than a correction for selection.
- Table 6a/Figure 3: ordinary-OLS residual geometry for point-estimate sensitivity; city-clustered SEs are not inserted into the algebraic bias formula.

## Outputs

Each complete run creates:

```text
runs/run_DATE_TIME/
  data/charls.dta
  data/dataset 0507.dta
  output/primary_estimation_sample.dta
  output/manuscript_tables/       Table_1.csv through Appendix_Table_A8.csv (19 tables)
  output/manuscript_tables/TABLE_INDEX.csv
  output/figures/                 Figure1 SVG; Figure2/3 and A1/A2/A3 PNG/PDF/GPH
  output/analysis_sample_flow.csv
  output/                        Full-precision estimates, diagnostics, bootstrap draws
  logs/                          Stata analysis and supplementary-module logs
  preflight.json                 Input hashes and environment information
  verification.json              Numerical checks against aggregate references
  verification_passed.ok
```

The tables are numerical exports, not replacements for the manuscript's Word layout. `TABLE_INDEX.csv` identifies the exact model output and interpretation for every table. Figure 1 is editable vector SVG. It is calculated from this run's data, not from hard-coded sample counts. Other figures are drawn from this run's results and saved at publication-friendly resolution.

## Manuscript alignment notes

- Table 1 COVID statistics use **86,654 nonmissing observations** and SD **0.2297963855** (0.230 when rounded). The supplied manuscript displays 86,696 and 0.228. The 42 missing case-count records are environmental-only rows. The principal estimation sample remains 16,661.
- Binary logit has 110 estimated slopes plus an intercept (**111 parameters**) when city indicators are generated after excluding Anshan. The manuscript count of 112 includes an omitted all-zero city indicator. The fitted model and reported DID coefficient do not change when that redundant column is removed. Ordered logit has 113 parameters.
- Small numerical differences in the DID-specific Wald statistic can arise from likelihood optimization and numerical differentiation. Validation permits an absolute difference of 0.0001 in chi-squared and 0.00001 in its p-value against the independent diagnostic calculation; the p-value remains 0.1749 when rounded to four decimals. Each run exports its actual statistic.
- A5b exports means and nonmissing counts only. The 14,469 income-unavailable observations form a comparison group separate from the 16,661 retained observations. Of those 14,469, 12,507 have an observed outcome. Sample counts vary by characteristic. The internal comparison workbook retains additional diagnostic calculations, which are not columns in the manuscript table export.

## Verification and data access

Input hashes prevent unnoticed source-version changes. Aggregate expected results are used only after estimation for checking, never to select observations, fit coefficients, or construct plotted values. The package checks sample identity/counts, final model values, Table 5 samples, Sobel results, binary-income Chow statistics, bootstrap calculations, and all numbered outputs. See `verification/RELEASE_TEST.json` for the tested release.

Data and local paths are not published. Exact reproduction requires the listed upstream files; the municipal, COVID, and other externally compiled workbooks are not all automatically downloaded. Researchers must obtain access to the appropriate CHARLS releases and the specified external files. This release has been tested on the author's macOS/Stata 18 system, not on every operating system.

Third-party commands retain their original author and license information in `vendor/`. No third-party code is relabeled as Xiaoai's work. No software-license grant is added to the authors' research code by this packaging step.

A DOI is not yet assigned. Deposit the final synchronized release in a DOI-assigning repository and update the manuscript's Code Availability statement after the DOI exists.

See `README_复现说明.md`, `MANUSCRIPT_MAP.md`, and `CHANGELOG.md` for Chinese instructions and the manuscript mapping.
