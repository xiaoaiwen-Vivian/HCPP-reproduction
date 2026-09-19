* Author: Xiaoai
* Figure 2: city-clustered event study, 2015 reference wave.
* Figure 3: omitted-variable sensitivity of the point estimate only.
* Input is the NEW primary sample produced by the complete raw-data run.
* This script does not read the old dataset 0507.dta or alter source data.
* Called by RUN_ALL.do; paths always refer to this new run.

version 18.0
clear all
set more off

local package "$package_root"
local run "$project"
local output "$outpath/figures"
capture mkdir "`output'"
capture log close hcppfigures
log using "`output'/Figures_2_3_reproduction.log", text replace name(hcppfigures)
display "Source: `run'/output/primary_estimation_sample.dta"
display "Outputs: `output'"

sysdir set PLUS "`package'/vendor/stata_plus/"
adopath ++ "`package'/vendor/stata_plus"
foreach letter in _ e f j l m p r s {
    adopath ++ "`package'/vendor/stata_plus/`letter'"
}
which reghdfe
which ftools
confirm file "`run'/output/primary_estimation_sample.dta"
use "`run'/output/primary_estimation_sample.dta", clear
isid ID iwy
assert _N == 16661
assert inrange(rgoingl_clean, 1, 4)
assert inlist(iwy, 2011, 2013, 2015, 2018, 2020)
assert did == treat * (iwy >= 2018)
local controls gender marry log_real_inc_per rwork rural2 edu hchild retire adlab_c smoken drinkl srh age
foreach var in rgoingl_clean did treat city ID iwy `controls' {
    assert !missing(`var')
}
tempvar citytag persontag
egen byte `citytag' = tag(city)
quietly count if `citytag'
assert r(N) == 94
quietly count if `citytag' & treat == 1
assert r(N) == 10
egen byte `persontag' = tag(ID)
quietly count if `persontag'
assert r(N) == 7995

* Figure 2 reads this run's city-clustered event-study output.
preserve
    import excel "$outpath/event_study_city_cluster.xlsx", firstrow clear
    local pre_F=Joint_pretrend_F[1]
    local pre_p=Joint_pretrend_P[1]
    export delimited using "`output'/Figure2_event_study_results.csv", replace
    twoway (rcap CI_L CI_U Wave if Wave != 2015, lcolor(navy)) ///
        (scatter Estimate Wave if Wave != 2015, mcolor(navy) msymbol(O)) ///
        (scatter Estimate Wave if Wave == 2015, mcolor(maroon) msymbol(D)), ///
        yline(0, lpattern(dash) lcolor(gs8)) ///
        xline(2016.5, lpattern(dash) lcolor(cranberry)) ///
        xlabel(2011 2013 2015 2018 2020) legend(off) ///
        xtitle("Survey wave") ytitle("Treatment x wave coefficient") ///
        title("Event-study estimates") subtitle("2015 reference wave") ///
        note("City and wave fixed effects and all 13 controls; N = 16,661; 94 city clusters." ///
             "Bars: 95% confidence intervals using city-clustered SEs and t(93)." ///
             "Joint pre-policy test: F(2,93) = 0.1695, p = 0.8444. The 2015 point is fixed at zero.", size(vsmall)) ///
        graphregion(color(white)) scheme(s2color) xsize(9) ysize(5.4)
    graph save "`output'/Figure2_event_study.gph", replace
    graph export "`output'/Figure2_event_study.png", replace width(3000)
    graph export "`output'/Figure2_event_study.pdf", replace
restore

* ---------------- Figure 3: same sample and model geometry ----------------
* Ordinary OLS SE and residual df are used ONLY for the algebraic bias formula.
* Do NOT insert a city-clustered t statistic/SE into this calculation.
* This is not a cluster-robust CI or a test of significance under confounding.
tempvar city_number
encode city, gen(`city_number')
regress rgoingl_clean did `controls' i.`city_number' i.iwy
assert e(N) == 16661
assert e(df_r) == 16549
scalar hcpp_b = _b[did]
scalar hcpp_se_ols = _se[did]
scalar hcpp_df = e(df_r)
scalar hcpp_srh_y = (_b[srh]/_se[srh])^2/((_b[srh]/_se[srh])^2+e(df_r))
quietly regress did `controls' i.`city_number' i.iwy
scalar hcpp_srh_d = (_b[srh]/_se[srh])^2/((_b[srh]/_se[srh])^2+e(df_r))
preserve
    clear
    set obs 1
    gen double b=hcpp_b
    gen double se=hcpp_se_ols
    gen double df=hcpp_df
    gen double r2_srh_y=hcpp_srh_y
    gen double r2_srh_d=hcpp_srh_d
    export delimited using "$outpath/sensitivity_geometry.csv",replace
restore
scalar hcpp_f2 = (hcpp_b/hcpp_se_ols)^2/hcpp_df
scalar hcpp_r2 = hcpp_f2/(1+hcpp_f2)
scalar hcpp_rv = (sqrt(hcpp_f2^2+4*hcpp_f2)-hcpp_f2)/2
assert abs(hcpp_b - (-.0866794779116242)) < 1e-8
assert abs(hcpp_rv - .01986103) < 1e-7
local rv_percent = 100*hcpp_rv
local rv_label : display %5.3f `rv_percent'

preserve
    clear
    set obs 1
    gen double N = 16661
    gen double DID_coefficient = hcpp_b
    gen double OLS_SE_geometry_only = hcpp_se_ols
    gen double OLS_residual_df = hcpp_df
    gen double DID_outcome_partial_R2 = hcpp_r2
    gen double RV_point_estimate = hcpp_rv
    gen double RV_percent = 100*hcpp_rv
    export delimited using "`output'/Figure3_sensitivity_summary.csv", replace
    export excel using "`output'/Figure3_sensitivity_summary.xlsx", firstrow(variables) replace
restore

preserve
    clear
    set obs 401
    gen double r2 = (_n-1)*.0001
    gen double r2_percent = 100*r2
    * Bias direction is chosen to move the observed negative coefficient to zero.
    gen double adjusted_estimate = hcpp_b + hcpp_se_ols*sqrt(hcpp_df)*r2/sqrt(1-r2)
    export delimited using "`output'/Figure3_sensitivity_curve.csv", replace
    twoway line adjusted_estimate r2_percent, lcolor(navy) lwidth(medthick) ///
        xline(`rv_percent', lcolor(maroon) lpattern(dash)) ///
        yline(0, lcolor(gs7) lpattern(shortdash)) ///
        xlabel(0(.5)4, labsize(small)) ///
        ylabel(-.1(.025).1, labsize(small) angle(0) format(%5.3f)) ///
        xtitle("Equal partial R-squared with treatment and outcome (%)", size(small)) ///
        ytitle("Bias-adjusted DID coefficient", size(small)) ///
        title("Sensitivity of the DID point estimate", size(medium)) ///
        subtitle("Equal-strength residual confounding scenario", size(small)) ///
        text(.081 3.0 "Point estimate reaches zero at `rv_label'%", size(small) color(maroon)) ///
        note("Ordinary-OLS residual geometry; N = 16,661; all 13 controls and city/year effects are retained." ///
             "The same partial R-squared is assigned to treatment and outcome; bias attenuates the estimate." ///
             "This is not a city-clustered confidence interval or a significance-robustness threshold.", size(vsmall)) ///
        legend(off) graphregion(color(white)) scheme(s2color) xsize(9) ysize(5.4)
    graph save "`output'/Figure3_sensitivity.gph", replace
    graph export "`output'/Figure3_sensitivity.png", replace width(3000)
    graph export "`output'/Figure3_sensitivity.pdf", replace
restore

display "FIGURES_2_3_REPRODUCTION_COMPLETE"
display "Output folder: `output'"
display "Figure 2 pre-policy joint p = " %12.10f `pre_p'
display "Figure 3 robustness value = " %12.10f hcpp_rv
log close hcppfigures
