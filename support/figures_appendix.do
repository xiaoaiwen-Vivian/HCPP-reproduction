* Xiaoai: appendix figures from this run's final outputs.
version 18.0
clear all
set more off
local w "$outpath/figures"
log using "$project/logs/figures_appendix.log",text replace
import excel "$outpath/prepolicy_psm_balance.xlsx", firstrow clear
gen position=13-_n
twoway (scatter position Bias_U, msymbol(O) mcolor(maroon)) (scatter position Bias_M, msymbol(D) mcolor(navy)), ylabel(12 "Male" 11 "Married" 10 "Log real income per capita" 9 "Working" 8 "Agricultural hukou" 7 "Education" 6 "Number of children" 5 "Retired" 4 "ADL limitations" 3 "Current smoking" 2 "Alcohol use" 1 "Self-rated health", angle(0) labsize(small)) ytitle("") xtitle("Standardized difference (%)") xline(0, lcolor(gs8)) xline(-10 10, lpattern(dash) lcolor(gs10)) legend(order(1 "Before matching" 2 "After kernel matching") rows(1) size(small)) title("Balance of pre-policy respondent means", size(medium)) graphregion(color(white)) scheme(s2color) xsize(9) ysize(5.8)
graph export "`w'/Appendix_Figure_A2_balance.png", width(2800) replace
graph save "`w'/Appendix_Figure_A2_balance.gph",replace
graph export "`w'/Appendix_Figure_A2_balance.pdf",replace
import delimited "$outpath/city_level_placebo_5000.csv", clear
local observed=actual_beta[1]
local bp : display %6.4f empirical_p[1]
local tp : display %6.4f t_empirical_p[1]
kdensity beta, xline(`observed', lcolor(maroon) lpattern(dash)) xtitle("Placebo DID coefficient") ytitle("Density") title("City-level placebo assignments", size(medium)) subtitle("5,000 valid draws; 10 of 94 cities assigned treatment") note("Observed DID = -0.0867; coefficient p = `bp'; studentized p = `tp'.") graphregion(color(white)) scheme(s2color)
graph export "`w'/Appendix_Figure_A1_placebo.png", width(2800) replace

graph save "`w'/Appendix_Figure_A1_placebo.gph",replace
graph export "`w'/Appendix_Figure_A1_placebo.pdf",replace
use "$outpath/prepolicy_psm_diagnostics.dta",clear
twoway (kdensity pscore_pre if treat==1, lcolor(navy)) (kdensity pscore_pre if treat==0, lcolor(maroon) lpattern(dash)), legend(order(1 "Treated" 2 "Controls")) name(ps_before,replace) title("Before matching") xtitle("Propensity score") ytitle("Density") graphregion(color(white))
twoway (kdensity pscore_pre [aw=_weight] if treat==1 & _support==1 & _weight>0 & _weight<., lcolor(navy)) (kdensity pscore_pre [aw=_weight] if treat==0 & _support==1 & _weight>0 & _weight<., lcolor(maroon) lpattern(dash)), legend(order(1 "Treated" 2 "Weighted controls")) name(ps_after,replace) title("After kernel matching") xtitle("Propensity score") ytitle("Density") graphregion(color(white))
graph combine ps_before ps_after,cols(2) graphregion(color(white))
graph export "`w'/Appendix_Figure_A3_overlap.png",width(3200) replace
graph export "`w'/Appendix_Figure_A3_overlap.pdf",replace
graph save "`w'/Appendix_Figure_A3_overlap.gph",replace
display "APPENDIX_FIGURES_COMPLETED"
log close
