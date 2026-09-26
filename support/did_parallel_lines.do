* Xiaoai: DID-specific proportional-odds restriction, tested with city clustering.
* Only the DID slope can vary across thresholds. Other slopes remain common.
* Starting values come from ordered logit fitted to this run's nonlinear sample.
version 18.0
set type double
clear
capture log close
log using "$project/logs/did_parallel_lines.log", text replace
use "$outpath/nonlinear_estimation_sample.dta", clear
unab indicators : nlc_* nly_*
quietly ologit rgoingl_clean did $ctrl `indicators', vce(cluster city_num) iterate(200) tolerance(1e-10) ltolerance(1e-12) nrtolerance(1e-8)
assert e(converged)==1
matrix ppo_start = e(b), (0,0)
capture program drop hcpp_ppo_ll
program define hcpp_ppo_ll
    args lnf xb cut1 cut2 cut3 delta2 delta3
    tempvar z1 z2 z3
    quietly gen double `z1'=`cut1'-`xb'
    quietly gen double `z2'=`cut2'-`xb'-did*`delta2'
    quietly gen double `z3'=`cut3'-`xb'-did*`delta3'
    quietly replace `lnf'=ln(invlogit(`z1')) if $ML_y1==1
    quietly replace `lnf'=ln(invlogit(`z2')-invlogit(`z1')) if $ML_y1==2
    quietly replace `lnf'=ln(invlogit(`z3')-invlogit(`z2')) if $ML_y1==3
    quietly replace `lnf'=ln(invlogit(-`z3')) if $ML_y1==4
end
ml model lf hcpp_ppo_ll (xb:rgoingl_clean=did $ctrl `indicators', nocons) ///
    /cut1 /cut2 /cut3 /delta2 /delta3, vce(cluster city_num)
ml init ppo_start, copy
ml maximize, iterate(200) tolerance(1e-10) ltolerance(1e-12) nrtolerance(1e-8)
assert e(converged)==1
local N=e(N)
local G=e(N_clust)
test (_b[/delta2]=0) (_b[/delta3]=0)
local chi=r(chi2)
local df=r(df)
local p=r(p)
assert `df'==2
predict double ppo_xb, equation(xb)
gen double ppo_c1=invlogit(_b[/cut1]-ppo_xb)
gen double ppo_c2=invlogit(_b[/cut2]-ppo_xb-did*_b[/delta2])
gen double ppo_c3=invlogit(_b[/cut3]-ppo_xb-did*_b[/delta3])
gen double ppo_p1=ppo_c1
gen double ppo_p2=ppo_c2-ppo_c1
gen double ppo_p3=ppo_c3-ppo_c2
gen double ppo_p4=1-ppo_c3
assert !missing(ppo_p1,ppo_p2,ppo_p3,ppo_p4)
assert min(ppo_p1,ppo_p2,ppo_p3,ppo_p4)>=0
assert max(ppo_p1,ppo_p2,ppo_p3,ppo_p4)<=1
assert abs(ppo_p1+ppo_p2+ppo_p3+ppo_p4-1)<1e-10
estimates save "$outpath/did_partial_proportional_odds.ster", replace
tempname slopes
tempfile contrasts
postfile `slopes' byte Threshold double(Coef SE P) using `contrasts', replace
forvalues k=1/3 {
    if `k'==1 lincom [xb]did
    else lincom [xb]did+_b[/delta`k']
    post `slopes' (`k') (r(estimate)) (r(se)) (r(p))
}
postclose `slopes'
use `contrasts', clear
export delimited using "$outpath/did_threshold_slopes.csv", replace
clear
set obs 1
gen long N=`N'
gen int Cities=`G'
gen double Wald_chi2=`chi'
gen byte df=`df'
gen double P=`p'
gen byte Converged=1
gen long Invalid_fitted_prob=0
gen str90 Scope="Equality of the DID slope across three thresholds; other slopes constrained equal"
export delimited using "$outpath/did_parallel_lines.csv", replace
display as result "DID_PARALLEL_LINES_COMPLETED"
log close
