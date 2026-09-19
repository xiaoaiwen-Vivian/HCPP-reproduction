* Maintainer: Xiaoai. Set Stata's working directory to this package first.
* Default: raw inputs -> NEW charls -> NEW 0507 -> all retained final analyses.
* Optional: do RUN_ALL.do build   (rebuild data only).
version 18.0
clear all
set more off
args mode
if !inlist("`mode'", "", "build") {
    display as error "Use RUN_ALL.do or RUN_ALL.do build. Every run starts from raw inputs."
    exit 198
}
global package_root "`c(pwd)'"
confirm file "$package_root/config.do"
confirm file "$package_root/pipeline_v4.do"
do "$package_root/config.do"
local stamp = subinstr("`c(current_date)'_`c(current_time)'", " ", "", .)
local stamp = subinstr("`stamp'", ":", "", .)
capture mkdir "$package_root/runs"
global project "$package_root/runs/run_`stamp'"
capture mkdir "$project"
if _rc {
    display as error "Cannot create a fresh run directory; no existing run will be reused."
    exit 603
}
global code "$package_root/support"
global temp_data "$project/temp"
global working_data "$project/data"
global outpath "$project/output"
global analysisfile "$working_data/dataset 0507.dta"
foreach dir in data temp output logs {
    mkdir "$project/`dir'"
}
tempname paths
file open `paths' using "$project/input_paths.tsv", write text replace
foreach key in rawroot raw2011 raw2013 raw2015 raw2018 raw2020 harmonized harmonizedC citybook municipal covidbook pm25 {
    file write `paths' "`key'" _tab "${`key'}" _n
}
file close `paths'
shell "$python" "$code/preflight.py" "$package_root" "$project"
confirm file "$project/preflight_passed.ok"

* Give the bundled community commands precedence over machine installations.
sysdir set PLUS "$package_root/vendor/stata_plus/"
adopath ++ "$package_root/vendor/stata_plus"
foreach letter in _ e f j l m p r s {
    adopath ++ "$package_root/vendor/stata_plus/`letter'"
}
capture log close _all
log using "$project/logs/dependencies.log", text replace
foreach cmd in sreshape reghdfe ftools psmatch2 pstest esttab estpost {
    which `cmd'
    quietly findfile `cmd'.ado
    if strpos("`r(fn)'", "$package_root/vendor/stata_plus/")!=1 {
        display as error "A required command did not resolve to the bundled snapshot."
        exit 499
    }
}
log close
do "$package_root/pipeline_v4.do" `mode'
if "`mode'"=="build" {
    shell "$python" "$code/verify_run.py" "$package_root" "$project" --build-only
}
else {
    sysdir set PLUS "$package_root/vendor/stata_plus/"
    do "$code/sobel_city.do"
    do "$code/figures_main.do"
    do "$code/figures_appendix.do"
    shell "$python" "$code/export_manuscript.py" "$project"
    confirm file "$outpath/manuscript_exports.ok"
    shell "$python" "$code/verify_run.py" "$package_root" "$project"
}
confirm file "$project/verification_passed.ok"
display as result "REPRODUCTION_PACKAGE_RUN_VERIFIED"
display as result "New data and results: $project"
