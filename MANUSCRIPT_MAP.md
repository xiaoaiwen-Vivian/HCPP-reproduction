# Manuscript-to-code map

Maintainer: Xiaoai. All paths are relative to the repository. Outputs are under the run directory.

| Manuscript item | Code | Data / calculation |
|---|---|---|
| Table 1/2 | `support/export_manuscript.py` | Merged and primary DTA; available-case summaries |
| Table 3 | `pipeline_v4.do + support/export_estimate.do` | Four main fits and pre-policy PSM-DID |
| Table 4 | `pipeline_v4.do` | Nine descriptive subgroup fits |
| Table 5 | `support/table5_panels.do` | Available-case Panel A; outcome-complete Panel B |
| Table 6a | `support/figures_main.do + support/export_manuscript.py` | OLS sensitivity geometry and benchmark calculations |
| Table 6b | `pipeline_v4.do + support/export_estimate.do` | Linear models, nonlinear diagnostics, respondent FE; nonlinear code in support/nonlinear_models.do |
| Table 6c | `pipeline_v4.do` | Additive COVID, centered interaction and covariance-based marginal associations |
| A1a | `support/sobel_city.do` | Conventional Sobel and joint city-covariance diagnostic |
| A1b | `support/mediation_cluster_bootstrap.py` | Six common-sample city-bootstrap indirect associations |
| A2a/A2b | `pipeline_v4.do` | Pre-policy logit and auxiliary probit/balance diagnostics |
| A3 | `pipeline_v4.do` | Five Group × DID contrasts |
| A4 | `pipeline_v4.do` | Four Full Chow tests, income binary low vs middle/high |
| A5a/A5b | `pipeline_v4.do` | Income missingness rates and group comparisons |
| A6 | `pipeline_v4.do` | Respondent FE; urban residence, age >=45, complete model variables |
| A7 | `pipeline_v4.do` | Webb/Rademacher 9,999 replications |
| A8 | `pipeline_v4.do` | Two pre-policy placebo dates |
| Figure 1 | `support/export_manuscript.py` | Selection flow calculated from the run data |
| Figure 2 | `support/figures_main.do` | Reads estimated event-study coefficients and city CIs |
| Figure 3 | `support/figures_main.do` | Ordinary-OLS point-estimate sensitivity curve |
| Appendix Figure A1 | `support/figures_appendix.do` | City placebo coefficient draws |
| Appendix Figure A2 | `support/figures_appendix.do` | Pre-policy respondent-mean covariate balance |
| Appendix Figure A3 | `support/figures_appendix.do` | Score distributions with kernel weights |
| DID-specific parallel-lines test | `support/did_parallel_lines.do` | Partial proportional odds, two DID restrictions, 93 city clusters |

## Interpretation

All primary policy-level inference clusters by city. Formal interaction tests govern subgroup claims. Bootstrap FDR governs the primary indirect-association summary; Sobel is supplementary. Logit outputs are diagnostic, and Table6a/Figure3 concern the point estimate only. None of these results validates the anergia item as a direct suicide outcome.
