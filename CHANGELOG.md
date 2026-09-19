# Changes for manuscript0918 alignment — 2026-09-19

Maintainer: Xiaoai.

1. Retain the verified raw cleaning and corrected 2020 household-income construction. Restore the archived 2011–2020 municipal workbook through the input configuration and hash manifest.
2. Use the common Table5 module for the approved available-case PanelA and outcome-complete PanelB; city clustering and separate six-test BH correction.
3. Integrate the previously separate Sobel and joint-covariance diagnostics into the full run.
4. Replace the three-tertile A4 joint test with low income versus pooled middle/high. Remove the unretained middle-income A3 interaction, keeping the descriptive middle-income Table4 model.
5. Export fitted-model metadata immediately from existing fits; this preserves R2, covariance-based intervals, sample sizes and cluster counts without estimating duplicate table models.
6. Integrate the additive COVID model, OLS sensitivity geometry, sample flow and all manuscript figures. Draw figures from the new run, not saved old result paths.
7. Export 19 numbered aggregate CSV tables and a source/interpretation index. Correct the two stale Table1 COVID cells in the exports: N86,654; SD0.230.
8. Extend checks to final Sobel/A4/Table5, five interactions, full bootstrap draws, PSM diagnostics and all table/figure outputs.
9. Add portable configuration plus private overrides, expanded directories, release hashes, upload exclusions and instructions.

No new income-missingness sensitivity specification was added. No manuscript Word file or remote repository was changed. Generalized ordered logit remains excluded as an unsuccessful historical specification. Nonlinear outputs remain diagnostic only.
