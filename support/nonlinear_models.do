* Xiaoai: ordered and binary logit, with city-clustered inference.
* City indicators with outcomes entirely at a boundary imply separation.
* Exclude these observations before fitting either model; record each exclusion.
version 18.0
set type double
preserve
keep if baseline_sample == 1
local base_n = _N
assert inrange(rgoingl_clean,1,4)
bysort city_num: egen double nl_min = min(rgoingl_clean)
bysort city_num: egen double nl_max = max(rgoingl_clean)
gen byte nl_excluded = (nl_min==nl_max & inlist(nl_min,1,4))
quietly count if nl_excluded
local excluded = r(N)
egen byte nl_tag = tag(city_num) if nl_excluded
quietly count if nl_tag==1
local excluded_cities = r(N)
tempfile nl_complete
save `nl_complete', replace
keep if nl_excluded
collapse (count) Observations=rgoingl_clean (min) Outcome_min=rgoingl_clean ///
    (max) Outcome_max=rgoingl_clean (mean) Treated=treat, by(city iwy)
export delimited using "$outpath/nonlinear_separation_cells.csv", replace
use `nl_complete', clear
drop if nl_excluded
quietly tabulate city_num, generate(nlc_)
quietly tabulate iwy, generate(nly_)
drop nlc_1 nly_1
unab indicators : nlc_* nly_*
save "$outpath/nonlinear_estimation_sample.dta", replace
tempname results
tempfile fits
postfile `results' str46 Model double(Coef SE P) long(N Base_N) ///
    int(Clusters Parameters) byte(Params_exceed_clusters Wald_unavailable) ///
    int Return_code byte Converged long Separated_obs int Separated_cities ///
    long Invalid_fitted_prob double(Min_fitted_prob Max_fitted_prob) ///
    str180 Status using `fits', replace
foreach model in ologit logit {
    if "`model'"=="ologit" local outcome rgoingl_clean
    else local outcome rgoingl_bin
    `model' `outcome' did $ctrl `indicators', vce(cluster city_num) iterate(200) tolerance(1e-10) ltolerance(1e-12) nrtolerance(1e-8)
    assert e(converged)==1
    assert e(N)==_N
    hcpp_export_estimate `model' "did"
    estimates save "$outpath/`model'_city_cluster.ster", replace
    local npar=colsof(e(b))
    local waldna=missing(e(chi2))
    local pexc=(`npar'>e(N_clust))
    local p=2*normal(-abs(_b[did]/_se[did]))
    if "`model'"=="ologit" {
        predict double nl_p1 nl_p2 nl_p3 nl_p4, pr
        gen byte nl_invalid=missing(nl_p1,nl_p2,nl_p3,nl_p4) | ///
            min(nl_p1,nl_p2,nl_p3,nl_p4)<0 | max(nl_p1,nl_p2,nl_p3,nl_p4)>1 | ///
            abs(nl_p1+nl_p2+nl_p3+nl_p4-1)>1e-10
        egen double nl_pmin=rowmin(nl_p1 nl_p2 nl_p3 nl_p4)
        egen double nl_pmax=rowmax(nl_p1 nl_p2 nl_p3 nl_p4)
    }
    else {
        predict double nl_p1, pr
        gen byte nl_invalid=missing(nl_p1) | !inrange(nl_p1,0,1)
        gen double nl_pmin=min(nl_p1,1-nl_p1)
        gen double nl_pmax=max(nl_p1,1-nl_p1)
    }
    quietly count if nl_invalid
    local invalid=r(N)
    if `invalid'>0 {
        list nl_p* if nl_invalid in 1/20
        summarize nl_p*
        display "INVALID_PROBABILITIES=" `invalid'
    }
    assert `invalid'==0
    quietly summarize nl_pmin
    local minp=r(min)
    quietly summarize nl_pmax
    local maxp=r(max)
    post `results' ("`model' + city and wave indicators") (_b[did]) (_se[did]) ///
        (`p') (e(N)) (`base_n') (e(N_clust)) (`npar') (`pexc') (`waldna') ///
        (0) (e(converged)) (`excluded') (`excluded_cities') (`invalid') (`minp') (`maxp') ///
        ("Log-odds association; city-clustered coefficient inference; overall Wald test unavailable")
    drop nl_p* nl_invalid
}
postclose `results'
use `fits', clear
export excel using "$outpath/nonlinear_cityFE_citycluster.xlsx", firstrow(variables) replace
export delimited using "$outpath/nonlinear_cityFE_citycluster.csv", replace
restore
display as result "NONLINEAR_MODELS_COMPLETED"
