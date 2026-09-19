* Xiaoai: restore original A1a Sobel formula; audit joint city covariance.
version 18.0
clear all
set more off
set type double
capture set processors 2
local input "$analysisfile"
local output "$outpath"
log using "$project/logs/sobel_city.log", text replace
use "`input'", clear
drop if missing(ID) | missing(wave)
isid ID wave
capture drop rgoingl_clean baseline_sample city_sobel
gen double rgoingl_clean=rgoingl
egen long city_sobel=group(city)
local ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire adlab_c smoken drinkl srh age
local eligible age>=45 & age<. & rural==0
quietly reghdfe rgoingl_clean did `ctrl' if `eligible', absorb(city iwy) vce(cluster city)
gen byte baseline_sample=e(sample)
assert e(N)==16661
tempname h
postfile `h' str10 Mediator str12 Sample double(a se_a b se_b N_a N_b G_a G_b Indirect Sobel_SE Sobel_z Sobel_p Joint_cov Joint_SE Joint_z Joint_p Joint_se_a Joint_se_b) using "`output'/sobel_city.dta", replace
foreach item in "Green GreenCoverageRateBD" "Social act_12" {
 tokenize `"`item'"'
 local lab "`1'"
 local med "`2'"
 foreach spec in original {
  local cond "`eligible'"
  if "`spec'"=="common" local cond "baseline_sample & !missing(`med')"
  quietly reghdfe `med' did `ctrl' if `cond', absorb(city iwy) vce(cluster city)
  scalar sx_aa=_b[did]
  scalar sx_sa=_se[did]
  scalar sx_na=e(N)
  scalar sx_ga=e(N_clust)
  capture drop sample_a sample_b
  gen byte sample_a=e(sample)
  quietly reghdfe rgoingl_clean `med' did `ctrl' if baseline_sample & !missing(`med'), absorb(city iwy) vce(cluster city)
  scalar sx_bb=_b[`med']
  scalar sx_sb=_se[`med']
  scalar sx_nb=e(N)
  scalar sx_gb=e(N_clust)
  gen byte sample_b=e(sample)
  scalar sx_ab=sx_aa*sx_bb
  scalar sx_ss=sqrt(sx_bb^2*sx_sa^2+sx_aa^2*sx_sb^2)
  scalar sx_zz=sx_ab/sx_ss
  scalar sx_pp=2*normal(-abs(sx_zz))
  quietly regress `med' did `ctrl' i.city_sobel i.iwy if sample_a
  assert abs(_b[did]-sx_aa)<1e-9
  estimates store path_a
  quietly regress rgoingl_clean `med' did `ctrl' i.city_sobel i.iwy if sample_b
  assert abs(_b[`med']-sx_bb)<1e-9
  estimates store path_b
  quietly suest path_a path_b, vce(cluster city_sobel)
  matrix V=e(V)
  scalar sx_covab=V[colnumb(V,"path_a_mean:did"),colnumb(V,"path_b_mean:`med'")]
  scalar sx_jsa=_se[path_a_mean:did]
  scalar sx_jsb=_se[path_b_mean:`med']
  quietly nlcom (indirect: _b[path_a_mean:did]*_b[path_b_mean:`med'])
  matrix JV=r(V)
  scalar sx_jse=sqrt(JV[1,1])
  assert abs(sx_jse-sqrt(sx_bb^2*sx_jsa^2+sx_aa^2*sx_jsb^2+2*sx_aa*sx_bb*sx_covab))<1e-9
  scalar sx_jz=sx_ab/sx_jse
  scalar sx_jp=2*normal(-abs(sx_jz))
  assert sx_na==16968 if "`lab'"=="Green" & "`spec'"=="original"
  assert sx_na==16876 if "`lab'"=="Social" & "`spec'"=="original"
  post `h' ("`lab'") ("`spec'") (sx_aa) (sx_sa) (sx_bb) (sx_sb) (sx_na) (sx_nb) (sx_ga) (sx_gb) (sx_ab) (sx_ss) (sx_zz) (sx_pp) (sx_covab) (sx_jse) (sx_jz) (sx_jp) (sx_jsa) (sx_jsb)
 }
}
postclose `h'
use "`output'/sobel_city.dta",clear
format a se_a b se_b Indirect Sobel_SE Sobel_z Sobel_p Joint_cov Joint_SE Joint_z Joint_p %12.8f
list Mediator Sample Indirect Sobel_SE Sobel_z Sobel_p Joint_p N_a N_b, noobs
export delimited using "`output'/sobel_city.csv",replace
export excel using "`output'/sobel_city.xlsx",firstrow(variables) replace
display "SOBEL_CITY_COMPLETED"
log close
