* Xiaoai: Table 5 Panel A uses available pathway/control observations.
* Panel B requires the outcome. Bootstrap path A is estimated separately on
* the common sample and is not replaced by the larger-sample Panel A estimate.
tempname mechpost
tempfile mechresults
postfile `mechpost' str8 Panel str20 Mediator double Coef SE P N Cities R2 DID_Coef DID_SE DID_P ///
    using `mechresults', replace
foreach item in "Green GreenCoverageRateBD" "Road RoadSurAreaPerCap" ///
    "SO2 工业二氧化硫排放量吨" "Medical hosper" "PM25 pm" "Social act_12" {
    tokenize `"`item'"'
    local lab "`1'"
    local med "`2'"
    tempvar medsample
    gen byte `medsample' = baseline_sample & !missing(`med')
    quietly reghdfe `med' did $ctrl if $sample, ///
        absorb(city iwy) vce(cluster city)
    post `mechpost' ("Panel A") ("`lab'") (_b[did]) (_se[did]) ///
        (2*ttail(e(df_r),abs(_b[did]/_se[did]))) (e(N)) (e(N_clust)) ///
        (e(r2)) (_b[did]) (_se[did]) (2*ttail(e(df_r),abs(_b[did]/_se[did])))
    quietly reghdfe rgoingl_clean `med' did $ctrl if `medsample', ///
        absorb(city iwy) vce(cluster city)
    post `mechpost' ("Panel B") ("`lab'") (_b[`med']) (_se[`med']) ///
        (2*ttail(e(df_r),abs(_b[`med']/_se[`med']))) (e(N)) (e(N_clust)) ///
        (e(r2)) (_b[did]) (_se[did]) (2*ttail(e(df_r),abs(_b[did]/_se[did])))
}
postclose `mechpost'
preserve
    use `mechresults', clear
    gen double Bonferroni_P = min(P*6,1)
    sort Panel P
    by Panel: gen int Rank = _n
    by Panel: gen double BH_raw = P*_N/Rank
    gsort Panel -Rank
    by Panel: gen double FDR_Q = BH_raw if _n==1
    by Panel: replace FDR_Q = min(BH_raw,FDR_Q[_n-1]) if _n>1
    replace FDR_Q = min(FDR_Q,1)
    sort Panel Rank
    drop BH_raw
    export delimited using "$outpath/mechanism_panelAB_city_cluster.csv", replace
    export excel using "$outpath/mechanism_panelAB_city_cluster.xlsx", ///
        firstrow(variables) replace
restore


