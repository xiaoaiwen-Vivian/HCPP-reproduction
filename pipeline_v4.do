version 18.0
clear all
set more off
set maxvar 30000
set type double
set rng mt64
set seed 2025
set sortseed 2025
args mode
if !inlist("`mode'","","build","models") {
    display as error "Supported modes: default, build, models"
    exit 198
}
* Xiaoai: 2015 uses Harmonized C; income correction is mandatory.
* 16,661 is a validation result, never a sample-selection target.
* The anergia item is a proxy; no model here measures suicide directly.
* Xiaoai: default = raw data -> newly generated 0507 -> final models.
* Optional: do this_file.do build (data only); models (use this run's 0507).
* No old charls.dta, 0727, 1208 or 0507 is an input to the build.
* Paths are initialized by RUN_ALL.do; output is a fresh run directory.
if "$package_root"=="" | "$project"=="" {
    display as error "Change to the package folder and run RUN_ALL.do."
    exit 198
}
* Harmonized C is required for the author-confirmed 2015 education definition.
foreach folder in data temp output logs {
    capture mkdir "$project/`folder'"
}
capture log close _all
log using "$project/logs/pipeline_`mode'.log", text replace
foreach cmd in sreshape reghdfe ftools psmatch2 pstest esttab estpost {
    capture which `cmd'
    if _rc {
        display as error "Missing required command: `cmd'"
        exit 199
    }
}
if "`mode'" != "models" {
confirm file "$harmonized/H_CHARLS_D_Data 2.dta"
confirm file "$harmonizedC/H_CHARLS_C_Data.dta"
* Distinct PSU filenames prevent case-insensitive filesystem collisions.
foreach yy in 2011 2013 {
    if `yy'==2011 use "$raw2011/psu.dta", clear
    else use "$raw2013/PSU.dta", clear
    ds, has(type string)
    foreach vv in `r(varlist)' {
        replace `vv'=ustrfrom(`vv',"gb18030",1) if ustrinvalidcnt(`vv')>0
        assert ustrinvalidcnt(`vv')==0
    }
    save "$temp_data/psu_`yy'_utf8.dta", replace
}
clear
global psu2011 "$temp_data/psu_2011_utf8.dta"
global psu2013 "$temp_data/psu_2013_utf8.dta"
tempname flowpost
tempfile sampleflow
postfile `flowpost' str100 Stage long N using `sampleflow', replace

* ==================== RAW CLEANING ====================
******************************** 2011年数据清洗 ********************************
use "$raw2013/Demographic_Background.dta",clear   //导入数据
keep ID bd001_w2_1 bd001_w2_2 bd001_w2_3
rename (bd001_w2_1 bd001_w2_2 bd001_w2_3) (r2bd001_w2_1 r2bd001_w2_2 r2bd001_w2_3)  //更改名称,避免后续合并造成变量重复
save "$temp_data/2013_Demographic_Background.dta", replace   //保存数据

***合并2011年的原始数据集
use "$raw2011/Demographic_Background.dta",clear    //导入数据
merge 1:1 ID using "$raw2011/health_status_and_functioning.dta",nogen
merge 1:1 ID using "$raw2011/health_care_and_insurance.dta",nogen
merge 1:1 ID using "$raw2011/biomarkers.dta",nogen
* 作者说明：未使用血样指标，本句注释
*merge 1:1 ID using "$raw2011/Blood_20140429.dta",nogen
merge 1:1 ID using "$raw2011/family_transfer.dta",nogen
merge 1:1 ID using "$raw2011/individual_income.dta",nogen
merge 1:1 ID using "$raw2011/interviewer_observation.dta",nogen
merge 1:1 ID using "$raw2011/work_retirement_and_pension.dta",nogen
merge m:1 householdID using "$raw2011/household_income.dta",nogen
merge m:1 householdID using "$raw2011/family_information.dta",nogen
merge m:1 householdID using "$raw2011/household_roster.dta",nogen
merge m:1 householdID using "$raw2011/housing_characteristics.dta",nogen

***残疾
gen r1disability=.
replace r1disability=1 if da005_1_==1 | da005_2_==1 | da005_3_==1 | da005_4_==1 | da005_5_==1 
replace r1disability=0 if da005_1_==2 & da005_2_==2 & da005_3_==2 & da005_4_==2 & da005_5_==2 

***认知能力=心智状况+情景记忆能力(此处的量表得分0-21分)
***心智状况=日期认知+计算+画图能力(11分)
***情景记忆能力=词组回忆(即时回忆+延时回忆)(10分)
***日期认知得分
*月
gen r1mo = .m 
replace r1mo = .d if db032 == .d | dc001s2 == .d
replace r1mo = .r if db032 == .r | dc001s2 == .r
replace r1mo = .p if db032 == 4 | proxy == 1
replace r1mo = 0 if !mi(dc001s1) | !mi(dc001s3) | !mi(dc002)
replace r1mo = 1 if dc001s2 == 2

*日
gen r1dy = .m
replace r1dy = .d if db032 == .d | dc001s3 == .d
replace r1dy = .r if db032 == .r | dc001s3 == .r
replace r1dy = .p if db032 == 4 | proxy == 1
replace r1dy = 0 if !mi(dc001s1) | !mi(dc001s2) | !mi(dc002)
replace r1dy = 1 if dc001s3 == 3 

*年
gen r1yr =.m 
replace r1yr = .d if db032 == .d | dc001s1 == .d
replace r1yr = .r if db032 == .r | dc001s1 == .r
replace r1yr = .p if db032 == 4 | proxy == 1
replace r1yr = 0 if !mi(dc001s2) | !mi(dc001s3) | !mi(dc002)
replace r1yr = 1 if dc001s1 == 1 

*周
gen r1dw =.m
replace r1dw = .d if db032 == .d | dc002 == .d
replace r1dw = .r if db032 == .r | dc002 == .r
replace r1dw = .p if db032 == 4 | proxy == 1
replace r1dw = 0 if dc002 == 2 | (!mi(dc001s1) | !mi(dc001s2) | !mi(dc001s3))
replace r1dw = 1 if dc002 == 1 

*季节
gen r1ds =.m
replace r1ds = .d if db032 == .d | dc003 == .d
replace r1ds = .r if db032 == .r | dc003 == .r
replace r1ds = .p if db032 == 4 | proxy == 1
replace r1ds = 0 if dc003 == 2 | (!mi(dc001s1) | !mi(dc001s2) | !mi(dc001s3))
replace r1ds = 1 if dc003 == 1 

*计算日期认知得分
egen r1date_cognition = rowtotal(r1mo r1dy r1yr r1dw r1ds), m
replace r1date_cognition = .m if (r1mo == .m | r1dy == .m | r1yr == .m | r1dw == .m | r1ds == .m) & mi(r1date_cognition)
replace r1date_cognition = .d if (r1mo == .d | r1dy == .d | r1yr == .d | r1dw == .d | r1ds == .d) & mi(r1date_cognition)
replace r1date_cognition = .r if (r1mo == .r | r1dy == .r | r1yr == .r | r1dw == .r | r1ds == .r) & mi(r1date_cognition)
replace r1date_cognition = .p if (r1mo == .p | r1dy == .p | r1yr == .p | r1dw == .p | r1ds == .p) & mi(r1date_cognition)


***社交活动
recode da056s1-da056s11 (1/11=1) (.e=0)
replace da056s6=1 if da056s7==1
rename (da056s1 da056s2 da056s3 da056s4 da056s5 da056s6 da056s8 da056s11) ///
  (r1act_1 r1act_2 r1act_3 r1act_4 r1act_5 r1act_6 r1act_7 r1act_8)

***各种医保类型
recode ea001s1 ea001s2 ea001s3 ea001s4 ea001s5 ea001s6 ea001s7 ea001s8 ///
  ea001s9 (.e=0) (1/9=1)

rename (ea001s1 ea001s2 ea001s3 ea001s4 ea001s5 ea001s6 ea001s7 ea001s8 ///
  ea001s9) (r1ea001s1 r1ea001s3 r1ea001s4 r1ea001s2 r1ea001s5 r1ea001s6 ///
  r1ea001s7 r1ea001s8 r1ea001s11)   //保持每年的医保名字相同
 
***修改ID 和 householdID
drop if mi(ID)
rename (ID householdID) (id_w1 hhid_w1)
gen householdID = hhid_w1 + "0"
gen ID = householdID + substr(id_w1,-2,2)  //由于2011年ID和2013年不一样

***2013年部分用户声称2011年错误，因此需要修改
merge 1:1 ID using "$temp_data/2013_Demographic_Background.dta" 
drop if _merge==2
replace bd001 = r2bd001_w2_3 if r2bd001_w2_1==2 | (r2bd001_w2_1==1 & r2bd001_w2_2==1)  //上次学历错误或者包含成人教育
rename bd001 r1educ_c

keep ID r1date_cognition r1educ_c r1act_1 r1act_2 r1act_3 r1act_4 r1act_5 r1act_6 ///
  r1act_7 r1act_8 r1ea001s1 r1ea001s2 r1ea001s3 r1ea001s4 r1ea001s5 r1ea001s6 ///
  r1ea001s7 r1ea001s8 r1ea001s11 r1disability
 
save "$temp_data/charls11.dta",replace //保存数据


* =============================================================================
* 第 2 段 / 共 6 段：2013 波清洗 → charls13.dta
*   原文件 no.2_charls_13.do
* =============================================================================

******************************** 2013年数据清理 ********************************
use "$raw2013/Demographic_Background.dta",clear  //导入数据
merge 1:1 ID using "$raw2013/Health_Status_and_Functioning.dta", nogen
merge 1:1 ID using "$raw2013/Health_Care_and_Insurance.dta",nogen
merge 1:1 ID using "$raw2013/Biomarker.dta",nogen
merge 1:1 ID using "$raw2013/Individual_Income.dta",nogen
merge 1:1 ID using "$raw2013/Work_Retirement_and_Pension.dta",nogen
merge m:1 householdID using "$raw2013/Household_Income.dta",nogen
merge m:1 householdID using "$raw2013/Family_Information.dta",nogen
merge m:1 householdID using "$raw2013/Family_Transfer.dta",nogen
merge m:1 householdID using "$raw2013/Housing_Characteristics.dta",nogen

***教育程度
replace zbd001= bd001 if !mi(bd001) & mi(zbd001)  //将新受访者和回访者合并   
replace zbd001 = bd001_w2_3 if bd001_w2_1==2 | (bd001_w2_1==1 & bd001_w2_2==1)   //上次学历错误或者包含成人教育
gen r2educ_c=zbd001                                        
replace r2educ_c=bd001_w2_4 if bd001_w2_4<12               //学历发生改变  

***残疾
gen r2disability=.
replace r2disability=1 if da005_1_==1 | da005_2_==1 | da005_3_==1 | da005_4_==1 | da005_5_==1 
replace r2disability=0 if da005_1_==2 & da005_2_==2 & da005_3_==2 & da005_4_==2 & da005_5_==2 

***日期认知得分
*月
gen r2mo = .m 
replace r2mo = .d if db032 == .d | dc001s2 == .d
replace r2mo = .r if db032 == .r | dc001s2 == .r
replace r2mo = .p if db032 == 4 
replace r2mo = 0 if !mi(dc001s1) | !mi(dc001s3) | !mi(dc002)
replace r2mo = 1 if dc001s2 == 2

*日
gen r2dy = .m
replace r2dy = .d if db032 == .d | dc001s3 == .d
replace r2dy = .r if db032 == .r | dc001s3 == .r
replace r2dy = .p if db032 == 4 
replace r2dy = 0 if !mi(dc001s1) | !mi(dc001s2) | !mi(dc002)
replace r2dy = 1 if dc001s3 == 3 

*年
gen r2yr =.m 
replace r2yr = .d if db032 == .d | dc001s1 == .d
replace r2yr = .r if db032 == .r | dc001s1 == .r
replace r2yr = .p if db032 == 4 
replace r2yr = 0 if !mi(dc001s2) | !mi(dc001s3) | !mi(dc002)
replace r2yr = 1 if dc001s1 == 1 

*周
gen r2dw =.m
replace r2dw = .d if db032 == .d | dc002 == .d
replace r2dw = .r if db032 == .r | dc002 == .r
replace r2dw = .p if db032 == 4 
replace r2dw = 0 if dc002 == 2 | (!mi(dc001s1) | !mi(dc001s2) | !mi(dc001s3))
replace r2dw = 1 if dc002 == 1 

*季节
gen r2ds =.m
replace r2ds = .d if db032 == .d | dc003 == .d
replace r2ds = .r if db032 == .r | dc003 == .r
replace r2ds = .p if db032 == 4 
replace r2ds = 0 if dc003 == 2 | (!mi(dc001s1) | !mi(dc001s2) | !mi(dc001s3))
replace r2ds = 1 if dc003 == 1 

*计算日期认知得分
egen r2date_cognition = rowtotal(r2mo r2dy r2yr r2dw r2ds), m
replace r2date_cognition = .m if (r2mo == .m | r2dy == .m | r2yr == .m | r2dw == .m | r2ds == .m) & mi(r2date_cognition)
replace r2date_cognition = .d if (r2mo == .d | r2dy == .d | r2yr == .d | r2dw == .d | r2ds == .d) & mi(r2date_cognition)
replace r2date_cognition = .r if (r2mo == .r | r2dy == .r | r2yr == .r | r2dw == .r | r2ds == .r) & mi(r2date_cognition)
replace r2date_cognition = .p if (r2mo == .p | r2dy == .p | r2yr == .p | r2dw == .p | r2ds == .p) & mi(r2date_cognition)


***社交活动
recode da056s* (1/11=1) (.=0)
replace da056s6=1 if da056s7==1
rename (da056s1 da056s2 da056s3 da056s4 da056s5 da056s6 da056s8 da056s11) ///
 (r2act_1 r2act_2 r2act_3 r2act_4 r2act_5 r2act_6 r2act_7 r2act_8)

***各种医保类型
recode ea001s1 ea001s2 ea001s3 ea001s4 ea001s5 ea001s6 ea001s7 ea001s8 ///
 ea001s9 ea001s10 (.=0) (1/10=1)
rename (ea001s1 ea001s2 ea001s3 ea001s4 ea001s5 ea001s6 ea001s7 ea001s8 ///
 ea001s9 ea001s10) (r2ea001s1 r2ea001s3 r2ea001s4 r2ea001s2 r2ea001s5 r2ea001s6 ///
 r2ea001s7 r2ea001s8 r2ea001s9 r2ea001s11)


***保留所需变量
keep ID r2educ_c r2date_cognition r2act_1 r2act_2 r2act_3 r2act_4 r2act_5 r2act_6 ///
  r2act_7 r2act_8 r2ea001s1 r2ea001s3 r2ea001s4 r2ea001s2 r2ea001s5 r2ea001s6 ///
  r2ea001s7 r2ea001s8 r2ea001s9 r2ea001s11 r2disability
  
save "$temp_data/charls13.dta",replace	 //保存数据


* =============================================================================
* 第 3 段 / 共 6 段：2015 波清洗 → charls15.dta
*   原文件 no.3_charls_15.do
* =============================================================================

******************************** 2015年数据清理 ********************************
***教育程度
*使用H_CHARLS_C_Data.dta识别
use "$harmonizedC/H_CHARLS_C_Data.dta", clear
merge 1:1 ID using "$raw2015/Health_Status_and_Functioning.dta", nogen	
merge 1:1 ID using "$raw2015/Health_Care_and_Insurance.dta", nogen	
merge 1:1 ID using "$raw2015/Biomarker.dta", nogen	
* 作者说明：未使用血样指标，本句注释
*merge 1:1 ID using "$raw2015/Blood.dta", nogen	
merge 1:1 ID using "$raw2015/Demographic_Background.dta", nogen	
merge 1:1 ID using "$raw2015/Individual_Income.dta", nogen	
merge m:1 householdID using "$raw2015/Household_Income.dta",nogen	
merge m:1 householdID using "$raw2015/Family_Information.dta", nogen	
merge m:1 householdID using "$raw2015/Family_Transfer.dta", nogen	
merge m:1 householdID using "$raw2015/Household_Income.dta", nogen	
merge m:1 householdID using "$raw2015/Housing_Characteristics.dta", nogen	


***教育
gen r3educ_c=raeduc_c
keep if inw4==1 // C version: inw4 denotes the 2015 interview.

***残疾
forvalues i=1/5 {
  replace da005_`i'_=zda005_`i'_ if mi(da005_`i'_) & !mi(zda005_`i'_)
}

gen r3disability=.
replace r3disability=1 if da005_1_==1 | da005_2_==1 | da005_3_==1 | da005_4_==1 | da005_5_==1 
replace r3disability=0 if da005_1_==2 & da005_2_==2 & da005_3_==2 & da005_4_==2 & da005_5_==2 		
				
***日期认知得分
*月
gen r3mo = .m 
replace r3mo = .d if db032 == .d | dc001s2 == .d
replace r3mo = .r if db032 == .r | dc001s2 == .r
replace r3mo = .p if db032 == 4 | proxy == 1
replace r3mo = 0 if !mi(dc001s1) | !mi(dc001s3) | !mi(dc002)
replace r3mo = 1 if dc001s2 == 2

*日
gen r3dy = .m
replace r3dy = .d if db032 == .d | dc001s3 == .d
replace r3dy = .r if db032 == .r | dc001s3 == .r
replace r3dy = .p if db032 == 4 | proxy == 1
replace r3dy = 0 if !mi(dc001s1) | !mi(dc001s2) | !mi(dc002)
replace r3dy = 1 if dc001s3 == 3 

*年
gen r3yr =.m 
replace r3yr = .d if db032 == .d | dc001s1 == .d
replace r3yr = .r if db032 == .r | dc001s1 == .r
replace r3yr = .p if db032 == 4 | proxy == 1
replace r3yr = 0 if !mi(dc001s2) | !mi(dc001s3) | !mi(dc002)
replace r3yr = 1 if dc001s1 == 1 

*周
gen r3dw =.m
replace r3dw = .d if db032 == .d | dc002 == .d
replace r3dw = .r if db032 == .r | dc002 == .r
replace r3dw = .p if db032 == 4 | proxy == 1
replace r3dw = 0 if dc002 == 2 | (!mi(dc001s1) | !mi(dc001s2) | !mi(dc001s3))
replace r3dw = 1 if dc002 == 1 

*季节
gen r3ds =.m
replace r3ds = .d if db032 == .d | dc003 == .d
replace r3ds = .r if db032 == .r | dc003 == .r
replace r3ds = .p if db032 == 4 | proxy == 1
replace r3ds = 0 if dc003 == 2 | (!mi(dc001s1) | !mi(dc001s2) | !mi(dc001s3))
replace r3ds = 1 if dc003 == 1 

*计算日期认知得分
egen r3date_cognition = rowtotal(r3mo r3dy r3yr r3dw r3ds), m
replace r3date_cognition = .m if (r3mo == .m | r3dy == .m | r3yr == .m | r3dw == .m | r3ds == .m) & mi(r3date_cognition)
replace r3date_cognition = .d if (r3mo == .d | r3dy == .d | r3yr == .d | r3dw == .d | r3ds == .d) & mi(r3date_cognition)
replace r3date_cognition = .r if (r3mo == .r | r3dy == .r | r3yr == .r | r3dw == .r | r3ds == .r) & mi(r3date_cognition)
replace r3date_cognition = .p if (r3mo == .p | r3dy == .p | r3yr == .p | r3dw == .p | r3ds == .p) & mi(r3date_cognition)


***社交活动
recode da056s* (1/11=1) (.=0)
replace da056s6=1 if da056s7==1
rename (da056s1 da056s2 da056s3 da056s4 da056s5 da056s6 da056s8 da056s11) ///
 (r3act_1 r3act_2 r3act_3 r3act_4 r3act_5 r3act_6 r3act_7 r3act_8)

***各种医保类型
forvalue i=1/10{
 gen r3ins`i'=. 
 replace r3ins`i'=0 if !mi(ea001_w3_1_`i'_) | !mi(ea001_w3_2_`i'_ ) | !mi(ea001_w3_3_`i'_)
 replace r3ins`i'=1 if ea001_w3_2_`i'_==1 | ea001_w3_3_`i'_==1
 replace r3ins`i'=. if mi(ea001_w3_2_`i'_) & mi(ea001_w3_3_`i'_)
}
rename (r3ins1 r3ins2 r3ins3 r3ins4 r3ins5 r3ins6 r3ins7 r3ins8 r3ins9 r3ins10) ///
(r3ea001s1 r3ea001s3 r3ea001s4 r3ea001s2 r3ea001s5 r3ea001s6 r3ea001s7 r3ea001s8 ///
r3ea001s9 r3ea001s11)

  
***保存所需变量  
keep ID r3educ_c r3date_cognition r3act_1 r3act_2 r3act_3 r3act_4 r3act_5 r3act_6 ///
  r3act_7 r3act_8 r3ea001s1 r3ea001s2 r3ea001s3 r3ea001s4 r3ea001s5 r3ea001s6 ///
  r3ea001s7 r3ea001s8 r3ea001s9 r3ea001s11 r3disability

save "$temp_data/charls15.dta",replace	 //保存数据


* =============================================================================
* 第 4 段 / 共 6 段：2018 波清洗 → charls18.dta
*   原文件 no.4_charls_18.do
* =============================================================================

******************************** 2018年数据清理 ********************************
use "$raw2018/Cognition.dta", clear
merge 1:1 ID using "$raw2018/Health_Status_and_Functioning.dta",nogen
merge 1:1 ID using "$raw2018/Demographic_Background.dta",nogen
merge 1:1 ID using "$raw2018/Health_Care_and_Insurance.dta",nogen
merge 1:1 ID using "$raw2018/Individual_Income.dta",nogen
merge 1:1 ID using "$raw2018/Pension.dta",nogen
merge 1:1 ID using "$raw2018/Work_Retirement.dta",nogen
merge m:1 householdID using "$raw2018/Household_Income.dta",nogen
merge m:1 householdID using "$raw2018/Family_Transfer.dta",nogen
merge m:1 householdID using "$raw2018/Household_Income.dta",nogen

***残疾
forvalues i=1/5 {
  replace da005_`i'_=zdisability_`i'_ if mi(da005_`i'_) & !mi(zdisability_`i'_)
}
gen r4disability=.
replace r4disability=1 if da005_1_==1 | da005_2_==1 | da005_3_==1 | da005_4_==1 | da005_5_==1 
replace r4disability=0 if da005_1_==2 & da005_2_==2 & da005_3_==2 & da005_4_==2 & da005_5_==2 


***日期认知得分
*月
gen r4mo = .m 
replace r4mo = .n if dc006_w4 == 97
replace r4mo = .p if db032 == 4
replace r4mo = 0 if dc006_w4 == 5
replace r4mo = 1 if dc006_w4 == 1

*日
gen r4dy = .m 
replace r4dy = .n if dc003_w4 == 97
replace r4dy = .p if db032 == 4
replace r4dy = 0 if dc003_w4 == 5
replace r4dy = 1 if dc003_w4 == 1

*年
gen r4yr = .m 
replace r4yr = .n if dc001_w4 == 97
replace r4yr = .p if db032 == 4
replace r4yr = 0 if dc001_w4 == 5
replace r4yr = 1 if dc001_w4 == 1

*星期
gen r4dw = .m 
replace r4dw = .n if dc005_w4 == 97
replace r4dw = .p if db032 == 4
replace r4dw = 0 if dc005_w4 == 5
replace r4dw = 1 if dc005_w4 == 1

*季节
gen r4ds = .m 
replace r4ds = .n if dc002_w4 == 97
replace r4ds = .p if db032 == 4
replace r4ds = 0 if dc002_w4 == 5
replace r4ds = 1 if dc002_w4 == 1


*计算日期认知得分
egen r4date_cognition = rowtotal(r4mo r4dy r4yr r4dw r4ds), m
replace r4date_cognition = .m if (r4mo == .m | r4dy == .m | r4yr == .m | r4dw == .m | r4ds == .m ) & mi(r4date_cognition)
replace r4date_cognition = .n if (r4mo == .n | r4dy == .n | r4yr == .n | r4dw == .n | r4ds == .n ) & mi(r4date_cognition)
replace r4date_cognition = .p if (r4mo == .p | r4dy == .p | r4yr == .p | r4dw == .p | r4ds == .p ) & mi(r4date_cognition)

***社交活动
recode da056_s* (1/11=1) 
replace da056_s6=1 if da056_s7==1
rename (da056_s1 da056_s2 da056_s3 da056_s4 da056_s5 da056_s6 da056_s8 da056_s11) ///
 (r4act_1 r4act_2 r4act_3 r4act_4 r4act_5 r4act_6 r4act_7 r4act_8)


***民族
recode bg001_w4 (1=1) (2/11=0) (else=.),gen (nation)

***各种医保类型
recode ea001_w4_s* (1/11=1)
rename (ea001_w4_s1 ea001_w4_s2 ea001_w4_s3 ea001_w4_s4 ea001_w4_s5 ///
 ea001_w4_s6 ea001_w4_s7 ea001_w4_s8 ea001_w4_s9 ea001_w4_s10 ea001_w4_s11) ///
 (r4ea001s1 r4ea001s2 r4ea001s3 r4ea001s4 r4ea001s5 r4ea001s6 r4ea001s7 ///
 r4ea001s8 r4ea001s9 r4ea001s10 r4ea001s11)

 
***保存所需变量  
keep ID r4date_cognition r4act_1 r4act_2 r4act_3 r4act_4 r4act_5 r4act_6 r4act_7 ///
 r4act_8 nation r4ea001s1 r4ea001s2 r4ea001s3 r4ea001s4 r4ea001s5 r4ea001s6 r4ea001s7 ///
 r4ea001s8 r4ea001s9 r4ea001s10 r4ea001s11 r4disability
  
save "$temp_data/charls18.dta",replace	 //保存数据


* =============================================================================
* 第 5 段 / 共 6 段：2020 波清洗 → charls2020.dta
*   原文件 no.5_charls_20.do
* =============================================================================

****************************************************************************
use "$raw2020/Demographic_Background.dta",clear 
*merge 1:1 ID using "$raw2020/Exit_Module.dta",nogen
merge 1:1 ID using "$raw2020/Health_Status_and_Functioning.dta",nogen
merge 1:1 ID using "$raw2020/Individual_Income.dta",nogen
merge 1:1 ID using "$raw2020/Sample_Infor.dta",nogen
merge 1:1 ID using "$raw2020/Weights.dta",nogen
merge 1:1 ID using "$raw2020/Work_Retirement.dta",nogen
merge m:1 householdID using "$raw2020/Family_Information.dta",nogen
merge m:1 householdID using "$raw2020/Household_Income.dta",nogen
merge m:1 communityID using "$psu2011",keep(match) nogen   //已转 UTF-8 的副本

***居住地
recode urban_nbs (0=1) (1=0),gen(h5rural)

***是否参与第五次调查
gen inw5=0
replace inw5=1 if !mi(ba001)  //未回答视为未参与本次调查

***家庭人口数
gen pnc=substr(ID,10,2) 
destring pnc, gen(pn)
bysort householdID: egen h5hhresp=count(pn) if inw5==1

* 如果cb001或cb002是"99"或空白，将其设为缺失值
replace cb001 = "" if cb001 == "99"
replace cb002 = "" if cb002 == "99"

* 使用split命令将cb001和cb002分割成多个变量
split cb001, generate(cb001_split) parse("~")
split cb002, generate(cb002_split) parse("~")

* 将分割后的字符串变量转换为数值变量
foreach var of varlist cb001_split* cb002_split* {
    destring `var', replace
}

* 计算cb001和cb002中的人数
egen count_cb001 = rownonmiss(cb001_split*)
egen count_cb002 = rownonmiss(cb002_split*)

* 计算总人数
egen h5hhres= rowtotal(count_cb001 count_cb002 h5hhresp),mi
replace h5hhres=. if mi(count_cb001) | mi(count_cb002) | mi(h5hhresp)

***年龄
replace zrbirthyear=ba003_1 if zrbirthyear==.

***性别
* 修正：2020 波性别改用 CHARLS 自带的跨波校正变量 xrgender。
* 原写法 rename ba001 r5gender 取的是本波原始作答；现有 charls.dta 里的
* gender 实际与 xrgender 逐行一致（96,628 行零差异），ba001 会差 29 行 / 9 人。
rename xrgender r5gender
capture rename ba001 ba001_raw2020   //本波原始作答，仅 inw5 判定用过，不再保留

***教育背景
replace zredu=ba010 if mi(zredu) & !mi(ba010)
rename zredu r5educ_c

***婚姻状况
gen r5mstath=.
replace r5mstath=1 if ba011==1
replace r5mstath=2 if ba011==2
replace r5mstath=4 if ba011==3
replace r5mstath=5 if ba011==4
replace r5mstath=7 if ba011==5
replace r5mstath=8 if ba011==6
replace r5mstath=3 if ba012==1

***户口
recode ba009 (1=1) (2/3=0) (else=.),gen(r5rural2)

***自评健康
recode da001 (997=.),gen(r5shlta)

***曾经是否吸烟
replace da046= zsmoke if !mi(zsmoke) & mi(da046)
recode da046 (1=1) (2=0),gen(r5smokev)

***现在是否吸烟
recode da047 (1=1) (2/3=0),gen(r5smoken) 
replace r5smoken=0 if da046==2

***现在饮酒
recode da051 (1/2=1) (3=0),gen(r5drinkl)

***锻炼
gen r5vgact_c =.
replace r5vgact_c = 1 if da032_1_==1
replace r5vgact_c = 0 if da032_1_==2

gen r5mdact_c =.
replace r5mdact_c = 1 if da032_2_==1
replace r5mdact_c = 0 if da032_2_==2

gen r5ltact_c =.
replace r5ltact_c = 1 if da032_3_==1
replace r5ltact_c = 0 if da032_3_==2 

***社交活动
recode da038_s1-da038_s8 (1/8=1)

forvalues i=1/8 {
  rename da038_s`i' r5act_`i'
}

***认知能力=心智状况+情景记忆能力(此处适用于经济学)
*心智状况(认知完整性)=日期认知+计算+画图能力
*情景记忆能力=词组回忆(即时回忆+延时回忆)
*词组即时回忆
recode dc012_s1 dc012_s2 dc012_s3 dc012_s4 dc012_s5 dc012_s6 dc012_s7 ///
  dc012_s8 dc012_s9 dc012_s10 (1/10=1)
egen r5imrc = rowtotal(dc012_s1 dc012_s2 dc012_s3 dc012_s4 dc012_s5 ///
  dc012_s6 dc012_s7 dc012_s8 dc012_s9 dc012_s10) 
replace r5imrc = .m if mi(dc012_s1) & mi(dc012_s2) & mi(dc012_s3) & ///
  mi(dc012_s4) & mi(dc012_s5) & mi(dc012_s6) & mi(dc012_s7) & mi(dc012_s8) & mi(dc012_s9) & mi(dc012_s10) 
  
replace r5imrc = .d if (db045 == .d | dc012_s1 == .d | dc012_s2 == .d | dc012_s3 == .d | dc012_s4 == .d | ///
                           dc012_s5 == .d | dc012_s6 == .d | dc012_s7 == .d | dc012_s8 == .d | ///
                           dc012_s9 == .d | dc012_s10 == .d) & mi(r5imrc)
replace r5imrc = .r if (db045 == .r | dc012_s1 == .r | dc012_s2 == .r | dc012_s3 == .r | dc012_s4 == .r | ///
                           dc012_s5 == .r | dc012_s6 == .r | dc012_s7 == .r | dc012_s8 == .r | ///
                           dc012_s9 == .r | dc012_s10 == .r) & mi(r5imrc)
replace r5imrc = .p if (db045 == 4 | proxy_5 == 1) & mi(r5imrc)

*词组延迟回忆
recode dc028_s1 dc028_s2 dc028_s3 dc028_s4 dc028_s5 dc028_s6 dc028_s7 ///
  dc028_s8 dc028_s9 dc028_s10 (1/10=1) 
egen r5dlrc = rowtotal(dc028_s1 dc028_s2 dc028_s3 dc028_s4 dc028_s5 ///
  dc028_s6 dc028_s7 dc028_s8 dc028_s9 dc028_s10) 
replace r5dlrc = .m if mi(dc028_s1) & mi(dc028_s2) & mi(dc028_s3) & /// 
  mi(dc028_s4) & mi(dc028_s5) & mi(dc028_s6) & mi(dc028_s7) & mi(dc028_s8) & mi(dc028_s9) & mi(dc028_s10)
replace r5dlrc = .d if (db045 == .d | dc028_s1 == .d | dc028_s2 == .d | dc028_s3 == .d | dc028_s4 == .d | ///
                           dc028_s5 == .d | dc028_s6 == .d | dc028_s7 == .d | dc028_s8 == .d | ///
                           dc028_s9 == .d | dc028_s10 == .d) & mi(r5dlrc)
replace r5dlrc = .r if (db045 == .r | dc028_s1 == .r | dc028_s2 == .r | dc028_s3 == .r | dc028_s4 == .r | ///
                           dc028_s5 == .r | dc028_s6 == .r | dc028_s7 == .r | dc028_s8 == .r | ///
						   dc028_s9 == .r | dc028_s10 == .r) & mi(r5dlrc)
                        
***计算词组回忆得分=(词组即时回忆+词组延迟回忆)/2   
gen r5memeory =.
replace r5memeory = .m if r5imrc == .m | r5dlrc == .m
replace r5memeory = .d if r5imrc == .d | r5dlrc == .d
replace r5memeory = .r if r5imrc == .r | r5dlrc == .r
replace r5memeory = .p if r5imrc == .p | r5dlrc == .p
replace r5memeory = (r5imrc + r5dlrc)/2 if !mi(r5imrc) & !mi(r5dlrc)

***日期认知得分
recode dc001-dc005 (997=.d) (999=.r)

*月
gen r5mo = .m 
replace r5mo = .d if dc005 == .d
replace r5mo = .r if dc005 == .r
replace r5mo = .p if db045 == 4 | proxy_5 == 1
replace r5mo = 0 if dc005 == 2 | (!mi(dc001) | !mi(dc002) | !mi(dc003) | !mi(dc004))
replace r5mo = 1 if dc005 == 1

*日
gen r5dy = .m 
replace r5dy = .d if dc003 == .d
replace r5dy = .r if dc003 == .r
replace r5dy = .p if db045 == 4 | proxy_5 == 1
replace r5dy = 0 if dc003 == 2 | (!mi(dc001) | !mi(dc002) | !mi(dc004) | !mi(dc005))
replace r5dy = 1 if dc003 == 1

*年份
gen r5yr = .m 
replace r5yr = .d if dc001 == .d
replace r5yr = .r if dc001 == .r
replace r5yr = .p if db045 == 4 | proxy_5 == 1
replace r5yr = 0 if dc001 == 2 | (!mi(dc002) | !mi(dc003) | !mi(dc004) | !mi(dc005))
replace r5yr = 1 if dc001 == 1

*星期
gen r5dw = .m 
replace r5dw = .d if dc002 == .d
replace r5dw = .r if dc002 == .r
replace r5dw = .p if db045 == 4 | proxy_5 == 1
replace r5dw = 0 if dc004 == 2 | (!mi(dc001) | !mi(dc002) | !mi(dc003) | !mi(dc005))
replace r5dw = 1 if dc004 == 1 

*季节
gen r5ds = .m 
replace r5ds = .d if dc002 == .d
replace r5ds = .r if dc002 == .r
replace r5ds = .p if db045 == 4 | proxy_5 == 1
replace r5ds = 0 if dc002 == 2 | (!mi(dc001) | !mi(dc003) | !mi(dc004) | !mi(dc005))
replace r5ds = 1 if dc002 == 1

***日期认知能力得分
egen r5date_cognition = rowtotal(r5mo r5dy r5yr r5dw r5ds), m
replace r5date_cognition = .m if (r5mo == .m | r5dy == .m | r5yr == .m | r5dw == .m | r5ds == .m) & mi(r5date_cognition)
replace r5date_cognition = .d if (r5mo == .d | r5dy == .d | r5yr == .d | r5dw == .d | r5ds == .d) & mi(r5date_cognition)
replace r5date_cognition = .r if (r5mo == .r | r5dy == .r | r5yr == .r | r5dw == .r | r5ds == .r) & mi(r5date_cognition)
replace r5date_cognition = .p if (r5mo == .p | r5dy == .p | r5yr == .p | r5dw == .p | r5ds == .p) & mi(r5date_cognition)


*画图能力得分
recode dc009 (997=.d) (999=.r)
gen r5draw = .m 
replace r5draw = .d if dc009 == .d
replace r5draw = .r if dc009 == .r
replace r5draw = .p if db045 == 4 | proxy_5 == 1
replace r5draw = 0 if dc009 == 2
replace r5draw = 1 if dc009 == 1


*数学题得分
recode dc007_1 dc007_2 dc007_3 dc007_4 dc007_5 (997=.d) (999=.r)
gen r5ser7 =.m
replace r5ser7 =.d if dc007_1==.d | dc007_2==.d | dc007_3==.d | dc007_4==.d | dc007_5==.d  
replace r5ser7 =.d if dc007_1_1==.d | dc007_2_1==.d | dc007_3_1==.d | dc007_4_1==.d | dc007_5_1==.d  
replace r5ser7 =.r if dc007_1==.r | dc007_2==.r | dc007_3==.r | dc007_4==.r | dc007_5==.r  
replace r5ser7 =.r if dc007_1_1==.r| dc007_2_1==.r | dc007_3_1==.r | dc007_4_1==.r | dc007_5_1==.r  
replace r5ser7 =.p if db045 == 4 | proxy_5 == 1
replace r5ser7 = 0 if !mi(dc007_1_1) | !mi(dc007_2_1) | !mi(dc007_3_1) | !mi(dc007_4_1) | !mi(dc007_5_1)
replace r5ser7 = r5ser7 + 1 if dc007_1_1 == 93
replace r5ser7 = r5ser7 + 1 if dc007_2_1 == (dc007_1_1 - 7) & !mi(dc007_1_1) & !mi(dc007_2_1)
replace r5ser7 = r5ser7 + 1 if dc007_3_1 == (dc007_2_1 - 7) & !mi(dc007_2_1) & !mi(dc007_3_1)
replace r5ser7 = r5ser7 + 1 if dc007_4_1 == (dc007_3_1 - 7) & !mi(dc007_3_1) & !mi(dc007_4_1)
replace r5ser7 = r5ser7 + 1 if dc007_5_1 == (dc007_4_1 - 7) & !mi(dc007_4_1) & !mi(dc007_5_1) 

*计算心智状况
egen r5executive=rowtotal(r5ser7 r5date_cognition r5draw),mi  //日期、绘画和减法
replace r5executive=.m if mi(r5date_cognition) | mi(r5ser7) | mi(r5draw)  
replace r5executive=.d if r5date_cognition==.d | r5ser7==.d | r5draw==.d
replace r5executive=.r if r5date_cognition==.r | r5ser7==.r | r5draw==.r  
replace r5executive=.p if r5date_cognition==.p | r5ser7==.p | r5draw==.p    

*计算认知能力总得分
egen r5total_cognition=rowtotal(r5memeory r5executive),mi //认知能力=情景记忆+心智状况
replace r5total_cognition=.m if mi(r5executive) | mi(r5memeory)
replace r5total_cognition=.d if r5executive==.d | r5memeory==.d
replace r5total_cognition=.r if r5executive==.r | r5memeory==.r
replace r5total_cognition=.p if r5executive==.p | r5memeory==.p 

***抑郁
recode dc020 dc023 (1=4) (2=3) (3=2) (4=1)  //反向编码
recode dc016-dc025 (1=0) (2=1) (3=2) (4=3) (else=.) 
egen r5cesd10=rowtotal(dc016 dc017 dc018 dc019 dc020 dc021 dc022 dc023 dc024 dc025),mi
replace r5cesd10=. if dc016==. | dc017==. | dc018==. | dc019==. | dc020==. | ///
  dc021==. | dc022==. | dc023==. | dc024==. | dc025==.

***慢性病
forvalues i=1/15 {
  replace da003_`i'_= zdisease_`i'_ if da003_`i'_==.
  recode da003_`i'_ (1=1) (2=0)
}

replace da003_12_=1 if da003_13_==1
rename (da003_1_ da003_2_ da003_3_ da003_4_ da003_5_ da003_6_ da003_7_ da003_8_ ///
 da003_9_ da003_10_ da003_11_ da003_12_ da003_14_ da003_15_) (r5hibpe r5dyslipe ///
 r5diabe r5cancre r5lunge r5livere r5hearte r5stroke r5kidneye r5digeste r5psyche ///
 r5memrye r5arthre r5asthmae)
 
***家庭总消费
*周消费
gen hh5cbfood=.
replace gf006=gf006 + gf008 if gf007==1 & !mi(gf008) & !mi(gf006)  //增加自家生产
replace hh5cbfood = gf006 if inrange(gf006,0,200000)

gen hh5codinn=.
replace hh5codinn = gf009 if inrange(gf009,0,200000)

gen hh5cacct=.
replace hh5cacct = gf010 if inrange(gf010,0,200000) 
 
gen hh5cfood =.
replace hh5cfood = hh5cbfood + hh5codinn + hh5cacct if ///
                    !mi(hh5cbfood) & !mi(hh5codinn) & !mi(hh5cacct)
 
*月消费
gen hh5ccomu=. 
replace hh5ccomu = gf011_1 if inrange(gf011_1,0,99999)

gen hh5cutil=.
replace hh5cutil = gf011_2 if inrange(gf011_2,0,99999)

gen hh5cfuel=.
replace hh5cfuel = gf011_3 if inrange(gf011_3,0,99999)

gen hh5cserv=.
replace hh5cserv = gf011_4 if inrange(gf011_4,0,99999)

gen hh5ctran=.
replace hh5ctran = gf011_5 if inrange(gf011_5,0,99999)

gen hh5cday=.
replace hh5cday = gf011_6 if inrange(gf011_6,0,99999)

gen hh5centa=.
replace hh5centa = gf011_7 if inrange(gf011_7,0,99999) 
 
*年消费
gen hh5cnf1m =.
replace hh5cnf1m = hh5ccomu + hh5cutil + hh5cfuel + hh5cserv +  ///
  hh5ctran + hh5cday + hh5centa if !mi(hh5ccomu) & !mi(hh5cutil) & ///
  !mi(hh5cfuel) & !mi(hh5cserv) & !mi(hh5ctran) & !mi(hh5cday) & !mi(hh5centa)

***
forvalues i=1/16 {
  replace gf013_`i'=. if inlist(gf013_`i',-1)
}
 
gen hh5cnf1y =.
replace hh5cnf1y = gf013_1 + gf013_2 + gf013_3 + gf013_4 + gf013_5 + ///
  gf013_6 + gf013_7 + gf013_8 + gf013_9 + gf013_10 + gf013_11 + gf013_12 + ///
  gf013_13 + gf013_14 + gf013_15 + gf013_16 if !mi(gf013_1) & !mi(gf013_2) & ///
  !mi(gf013_3) & !mi(gf013_4) & !mi(gf013_5) & !mi(gf013_6) & !mi(gf013_7) & ///
  !mi(gf013_8) & !mi(gf013_9) & !mi(gf013_10) & !mi(gf013_11) & !mi(gf013_12) & ///
  !mi(gf013_13) & !mi(gf013_14) & !mi(gf013_15) & !mi(gf013_16) 
   
***总消费   
gen hh5cfooda =.
replace hh5cfooda = hh5cfood*52 if !mi(hh5cfood)

gen hh5cnf1ma =.
replace hh5cnf1ma = hh5cnf1m*12 if !mi(hh5cnf1m)

gen hh5ctot =.
replace hh5ctot = hh5cfooda + hh5cnf1ma + hh5cnf1y if ///
                !mi(hh5cfooda) & !mi(hh5cnf1ma) & !mi(hh5cnf1y)
gen hh5cperc = hh5ctot/h5hhres		//人均消费


***受访时间
* 原始 xiwyear 在第五波 19,395 人里有 34 条缺失、4 条异常（2017×2、2018×2），
* 其中 2 条会与前面波次形成重复的 ID-iwy 合并键。第五波统一定为 2020，
* 与现有 charls.dta 的口径一致（该文件第五波 iwy 全部为 2020）。
rename xiwyear r5iwy_raw
gen r5iwy = 2020 if inw5 == 1
capture rename xiwmonth r5iwm

***健在子女数量   
recode ca002_*_  (1=1) (2=0)   
egen h5child=rowtotal(ca002_1_ ca002_2_ ca002_3_ ca002_4_ ca002_5_ ca002_6_ ///
  ca002_7_ ca002_8_ ca002_9_ ca002_10_ ca002_11_ ca002_12_ ca002_13_ ca002_14_ ///
  ca002_15_ ca002_16_ ca002_17_) 
  
***养老保险
recode ba014 (1/6=1) (7=0),gen(r5pension)

***医疗保险
recode ba016 (1/2=1) (3=0),gen(r5ins)   

***各种医保类型
tab ba017,gen(r5ea001s)
rename r5ea001s6 r5ea001s11  

***生活满意度
recode dc026 (1=5) (2=4) (3=3) (4=2) (5=1),gen(r5satlife)

***日常活动
recode db001 db003 db005 db007 db009 db011 (1=0) (2/4=1)
egen r5adlab_c=rowtotal(db001 db003 db005 db007 db009 db011),mi

***工具性日常活动
recode db012 db014 db016 db020 db022 (1=0) (2/4=1)
egen r5iadl=rowtotal(db012 db014 db016 db020 db022),mi

***子女对父母的经济支持
forvalues i=1/17 {
  recode ca017_1_`i'_ ca017_1_min_`i'_ ca017_1_max_`i'_ (-1=.) 
  replace ca017_1_`i'_=(ca017_1_min_`i'_ + ca017_1_max_`i'_)/2 if mi(ca017_1_`i'_) & !mi(ca017_1_min_`i'_) & !mi(ca017_1_max_`i'_)
}

forvalues i=1/17 {
  recode ca017_3_`i'_ ca017_3_min_`i'_ ca017_3_max_`i'_ (-1=.) 
  replace ca017_3_`i'_=(ca017_3_min_`i'_ + ca017_3_max_`i'_)/2 if !mi(ca017_3_min_`i'_) | !mi(ca017_3_max_`i'_)
}

***父母对子女的经济支持
forvalues i=1/11 {
  recode ca018_1_`i'_ ca018_1_min_`i'_ ca018_1_max_`i'_ (-1=.) 
  replace ca018_1_`i'_=(ca018_1_min_`i'_ + ca018_1_max_`i'_)/2 if mi(ca018_1_`i'_) & !mi(ca018_1_min_`i'_) & !mi(ca018_1_max_`i'_)
}

forvalues i=1/9 {
  recode ca018_3_`i'_ ca018_3_min_`i'_ ca018_3_max_`i'_ (-1=.) 
  replace ca018_3_`i'_=(ca018_3_min_`i'_ + ca018_3_max_`i'_)/2 if !mi(ca018_3_min_`i'_) | !mi(ca018_3_max_`i'_)
}  
  
egen h5fcamt=rowtotal(ca017_1_1_ ca017_1_2_ ca017_1_3_ ca017_1_4_ ca017_1_5_ ///
  ca017_1_6_ ca017_1_7_ ca017_1_8_ ca017_1_9_ ca017_1_10_ ca017_1_11_ ca017_1_12_ ///
  ca017_1_13_ ca017_1_14_ ca017_1_15_ ca017_1_16_ ca017_1_17_ ca017_3_1_ ///
  ca017_3_2_ ca017_3_3_ ca017_3_4_ ca017_3_5_ ca017_3_6_ ca017_3_7_ ca017_3_8_ ///
  ca017_3_9_ ca017_3_10_ ca017_3_11_ ca017_3_12_ ca017_3_13_ ca017_3_14_ ///
  ca017_3_15_ ca017_3_16_ ca017_3_17_)

egen h5tcamt=rowtotal(ca018_1_1_ ca018_1_2_ ca018_1_3_ ca018_1_4_ ca018_1_5_ ///
  ca018_1_6_ ca018_1_7_ ca018_1_8_ ca018_1_9_ ca018_1_10_ ca018_1_11_ ///
  ca018_1_12_ ca018_1_13_ ca018_1_14_ ca018_1_15_ ca018_1_16_ ca018_1_17_ ///
  ca018_3_1_ ca018_3_2_ ca018_3_3_ ca018_3_4_ ca018_3_5_ ca018_3_6_ ///
  ca018_3_7_ ca018_3_8_ ca018_3_9_ ca018_3_10_ ca018_3_11_ ca018_3_12_ ///
  ca018_3_13_ ca018_3_14_ ca018_3_15_ ca018_3_16_ ca018_3_17_)
  
***其他家户成员的工资收入
forvalues i=1/11 {
  replace gb003_`i'_=0 if gb002_`i'_==2  
  replace gb003_`i'_=.d if gb002_`i'_==997  //不知道,下同
  replace gb003_`i'_=.r if gb002_`i'_==999  //拒绝回答,下同
  recode gb003_`i'_ (-1=.d)
}

foreach i of numlist 1/7 11 {
  replace gb003_`i'_=(gb003_min_`i'_ + gb003_max_`i'_)/2 if mi(gb003_`i'_) & gb003_min_`i'_>=0 & !mi(gb003_min_`i'_) & gb003_max_`i'_>=0 & !mi(gb003_max_`i'_)
}

*其他家户成员的工资收入应扣除的杂费部分
forvalues i=1/11 {
 gen gb004`i'=.  //生成一个变量等于应扣除的杂费部分
 recode gb005_1_`i'_  gb005_1_min_`i'_  gb005_1_max_`i'_  (-1=.d)
 replace gb005_1_`i'_=gb005_1_min_`i'_ if !mi(gb005_1_min_`i'_) & mi(gb005_1_max_`i'_)
 replace gb005_1_`i'_=gb005_1_max_`i'_ if mi(gb005_1_min_`i'_) & !mi(gb005_1_max_`i'_)
 replace gb005_1_`i'_=(gb005_1_min_`i'_ + gb005_1_max_`i'_)/2 if !mi(gb005_1_min_`i'_) & !mi(gb005_1_max_`i'_)
 replace gb004`i'=gb005_1_`i'_*12 if gb005_`i'_==1 & !mi(gb005_1_`i'_)
 replace gb004`i'=0 if gb005_`i'_==4 
}

forvalues i=1/7 {
 replace gb004`i'=gb005_2_`i'_ if gb005_`i'_==2 & !mi(gb005_2_`i'_)
 replace gb004`i'=.d if gb005_`i'_==2 & gb005_2_`i'_==-1
}

forvalues i=1/5 {
 replace gb004`i'=gb003_`i'_*(gb005_3_`i'_/100) if gb005_`i'_==3 & !mi(gb005_3_`i'_)
 replace gb004`i'=.d if gb005_`i'_==3 & gb005_3_`i'_==-1
}

***计算其他家户成员的工资收入 - 应扣除的杂费部分
forvalues i=1/11 {
 replace gb003_`i'_=gb003_`i'_ - gb004`i' if !mi(gb003_`i'_) & !mi(gb004`i') & gb004_`i'_==2
}

egen hh5gz_other=rowtotal(gb003_1_ gb003_2_ gb003_3_ gb003_4_ gb003_5_ ///
  gb003_6_ gb003_7_ gb003_8_ gb003_9_ gb003_10_ gb003_11_) 
replace hh5gz_other=.d if gb003_1_==.d | gb003_2_==.d | gb003_3_==.d | gb003_4_==.d | ///
  gb003_5_==.d | gb003_6_==.d | gb003_7_==.d |gb003_8_==.d | gb003_9_==.d | gb003_10_==.d | gb003_11_==.d 
replace hh5gz_other=.r if gb003_1_==.r | gb003_2_==.r | gb003_3_==.r | gb003_4_==.r | ///
  gb003_5_==.r | gb003_6_==.r | gb003_7_==.r |gb003_8_==.r | gb003_9_==.r | gb003_10_==.r | gb003_11_==.r 
  

***其他家户成员的公共转移支付收入
recode gb006_1_1_ gb006_1_2_ gb006_1_3_ gb006_1_4_ gb006_1_5_ gb006_1_6_ ///
 gb006_1_7_ gb006_2_1_ gb006_2_2_ gb006_2_3_ gb006_2_4_ gb006_3_1_ gb006_3_2_ ///
 gb006_3_3_ gb006_3_4_ gb006_4_1_ gb006_4_2_ gb006_4_3_ gb006_4_4_ gb006_4_5_ ///
 gb006_4_6_ gb006_5_1_ gb006_5_2_ gb006_5_3_ gb006_5_4_ gb006_6_1_ gb006_6_2_ ///
 gb006_6_3_ gb006_6_4_ gb006_7_1_ gb006_7_2_ gb006_7_3_ gb006_7_4_ gb006_7_6_ ///
 gb006_8_1_ gb006_8_2_ gb006_8_3_ gb006_8_4_ gb006_8_5_ gb006_8_6_ gb006_8_8_ ///
 gb006_9_1_ gb006_9_2_ gb006_9_3_ gb006_9_4_ gb008_7_1_ gb008_7_2_ gb008_7_3_ /// 
 gb008_7_4_ gb008_7_5_ gb008_8_1_ gb008_8_2_ gb008_8_3_ gb008_8_4_ gb008_8_5_ /// 
 gb008_8_6_ gb008_8_7_ gb008_9_1_ gb008_9_2_ gb008_9_3_ gb008_9_4_ gb008_9_5_ ///
 gb008_9_6_ (.=0) (-1=.d) 
 
***计算其他家户成员的总收入 = 其他家户成员的公共转移支付收入 + 其他家户成员的工资收入减去杂费
gen hh5iothhh=hh5gz_other + gb006_1_1_ + gb006_1_2_  + gb006_1_3_  + gb006_1_4_ + ///
 gb006_1_5_ + gb006_1_6_ + gb006_1_7_ + gb006_2_1_ + gb006_2_2_ + gb006_2_3_ + ///
 gb006_2_4_ + gb006_3_1_ + gb006_3_2_ + gb006_3_3_ + gb006_3_4_ + gb006_4_1_ + ///
 gb006_4_2_ + gb006_4_3_ + gb006_4_4_ + gb006_4_5_ + gb006_4_6_ + gb006_5_1_ + ///
 gb006_5_2_ + gb006_5_3_ + gb006_5_4_ + gb006_6_1_ + gb006_6_2_ + gb006_6_3_ + ///
 gb006_6_4_ + gb006_7_1_ + gb006_7_2_ + gb006_7_3_ + gb006_7_4_ + gb006_7_6_ + ///
 gb006_8_1_ + gb006_8_2_ + gb006_8_3_ + gb006_8_4_ + gb006_8_5_ + gb006_8_6_ + ///
 gb006_8_8_ + gb006_9_1_ + gb006_9_2_ + gb006_9_3_ + gb006_9_4_ + gb008_7_1_ + ///
 gb008_7_2_ + gb008_7_3_ + gb008_7_4_ + gb008_7_5_ + gb008_8_1_ + gb008_8_2_ + ///
 gb008_8_3_ + gb008_8_4_ + gb008_8_5_ + gb008_8_6_ + gb008_8_7_ + gb008_9_1_ + ///
 gb008_9_2_ + gb008_9_3_ + gb008_9_4_ + gb008_9_5_ + gb008_9_6_ if !mi(hh5gz_other) | ///
 !mi(gb006_1_1_) | !mi(gb006_1_2_) | !mi(gb006_1_3_) | !mi(gb006_1_4_) | !mi(gb006_1_5_) | ///
 !mi(gb006_1_6_) | !mi(gb006_1_7_) | !mi(gb006_2_1_) | !mi(gb006_2_2_) | !mi(gb006_2_3_) | ///
 !mi(gb006_2_4_) | !mi(gb006_3_1_) | !mi(gb006_3_2_) | !mi(gb006_3_3_) | !mi(gb006_3_4_) | ///
 !mi(gb006_4_1_) | !mi(gb006_4_2_) | !mi(gb006_4_3_) | !mi(gb006_4_4_) | !mi(gb006_4_5_) | ///
 !mi(gb006_4_6_) | !mi(gb006_5_1_) | !mi(gb006_5_2_) | !mi(gb006_5_3_) | !mi(gb006_5_4_) | ///
 !mi(gb006_6_1_) | !mi(gb006_6_2_) | !mi(gb006_6_3_) | !mi(gb006_6_4_) | !mi(gb006_7_1_) | ///
 !mi(gb006_7_2_) | !mi(gb006_7_3_) | !mi(gb006_7_4_) | !mi(gb006_7_6_) | !mi(gb006_8_1_) | ///
 !mi(gb006_8_2_) | !mi(gb006_8_3_) | !mi(gb006_8_4_) | !mi(gb006_8_5_) | !mi(gb006_8_6_) | ///
 !mi(gb006_8_8_) | !mi(gb006_9_1_) | !mi(gb006_9_2_) | !mi(gb006_9_3_) | !mi(gb006_9_4_) | ///
 !mi(gb008_7_1_) | !mi(gb008_7_2_) | !mi(gb008_7_3_) | !mi(gb008_7_4_) | !mi(gb008_7_5_) | /// 
 !mi(gb008_8_1_) | !mi(gb008_8_2_) | !mi(gb008_8_3_) | !mi(gb008_8_4_) | !mi(gb008_8_5_) | ///
 !mi(gb008_8_6_) | !mi(gb008_8_7_) | !mi(gb008_9_1_) | !mi(gb008_9_2_) | !mi(gb008_9_3_) | ///
 !mi(gb008_9_4_) | !mi(gb008_9_5_) | !mi(gb008_9_6_) 

replace hh5iothhh=.d if hh5gz_other==.d | gb006_1_1_==.d | ///
 gb006_1_2_==.d | gb006_1_3_==.d | gb006_1_4_==.d | gb006_1_5_==.d | /// 
 gb006_1_6_==.d | gb006_1_7_==.d | gb006_2_1_==.d | gb006_2_2_==.d | /// 
 gb006_2_3_==.d | gb006_2_4_==.d | gb006_3_1_==.d | gb006_3_2_==.d | /// 
 gb006_3_3_==.d | gb006_3_4_==.d | gb006_4_1_==.d | gb006_4_2_==.d | /// 
 gb006_4_3_==.d | gb006_4_4_==.d | gb006_4_5_==.d | gb006_4_6_==.d | /// 
 gb006_5_1_==.d | gb006_5_2_==.d | gb006_5_3_==.d | gb006_5_4_==.d | /// 
 gb006_6_1_==.d | gb006_6_2_==.d | gb006_6_3_==.d | gb006_6_4_==.d | /// 
 gb006_7_1_==.d | gb006_7_2_==.d | gb006_7_3_==.d | gb006_7_4_==.d | /// 
 gb006_7_6_==.d | gb006_8_1_==.d | gb006_8_2_==.d | gb006_8_3_==.d | /// 
 gb006_8_4_==.d | gb006_8_5_==.d | gb006_8_6_==.d | gb006_8_8_==.d | /// 
 gb006_9_1_==.d | gb006_9_2_==.d | gb006_9_3_==.d | gb006_9_4_==.d | ///
 gb008_7_1_==.d | gb008_7_2_==.d | gb008_7_3_==.d | gb008_7_4_==.d | /// 
 gb008_7_5_==.d | gb008_8_1_==.d | gb008_8_2_==.d | gb008_8_3_==.d | ///
 gb008_8_4_==.d | gb008_8_5_==.d | gb008_8_6_==.d | gb008_8_7_==.d | /// 
 gb008_9_1_==.d | gb008_9_2_==.d | gb008_9_3_==.d | gb008_9_4_==.d | /// 
 gb008_9_5_==.d | gb008_9_6_==.d 

replace hh5iothhh=.r if hh5gz_other==.r | gb006_1_1_==.r | ///
 gb006_1_2_==.r | gb006_1_3_==.r | gb006_1_4_==.r | gb006_1_5_==.r | /// 
 gb006_1_6_==.r | gb006_1_7_==.r | gb006_2_1_==.r | gb006_2_2_==.r | /// 
 gb006_2_3_==.r | gb006_2_4_==.r | gb006_3_1_==.r | gb006_3_2_==.r | /// 
 gb006_3_3_==.r | gb006_3_4_==.r | gb006_4_1_==.r | gb006_4_2_==.r | /// 
 gb006_4_3_==.r | gb006_4_4_==.r | gb006_4_5_==.r | gb006_4_6_==.r | /// 
 gb006_5_1_==.r | gb006_5_2_==.r | gb006_5_3_==.r | gb006_5_4_==.r | /// 
 gb006_6_1_==.r | gb006_6_2_==.r | gb006_6_3_==.r | gb006_6_4_==.r | /// 
 gb006_7_1_==.r | gb006_7_2_==.r | gb006_7_3_==.r | gb006_7_4_==.r | /// 
 gb006_7_6_==.r | gb006_8_1_==.r | gb006_8_2_==.r | gb006_8_3_==.r | /// 
 gb006_8_4_==.r | gb006_8_5_==.r | gb006_8_6_==.r | gb006_8_8_==.r | /// 
 gb006_9_1_==.r | gb006_9_2_==.r | gb006_9_3_==.r | gb006_9_4_==.r | ///
 gb008_7_1_==.r | gb008_7_2_==.r | gb008_7_3_==.r | gb008_7_4_==.r | /// 
 gb008_7_5_==.r | gb008_8_1_==.r | gb008_8_2_==.r | gb008_8_3_==.r | ///
 gb008_8_4_==.r | gb008_8_5_==.r | gb008_8_6_==.r | gb008_8_7_==.r | /// 
 gb008_9_1_==.r | gb008_9_2_==.r | gb008_9_3_==.r | gb008_9_4_==.r | /// 
 gb008_9_5_==.r | gb008_9_6_==.r 

***家庭农业收入
recode gc004_1 gc004_2 gc004_1_min gc004_1_max (-1=.d)
replace gc004_1=0 if gc001==2  //非农业家庭
replace gc004_2=0 if gc001==2
replace gc004_1=0 if gc003==2  //没有从事农林生产
replace gc004_2=0 if gc003==2
replace gc004_1=0 if gc004==3  //农林生产不赔不赚
replace gc004_2=0 if gc004==3

replace gc004_1=(gc004_1_min+gc004_1_max)/2 if gc004==1 & mi(gc004_1) & ///
 !mi(gc004_1_min) & !mi(gc004_1_max)  //取中间值
replace gc004_1=gc004_1_max if gc004==1 & mi(gc004_1) & ///
 mi(gc004_1_min) & !mi(gc004_1_max)  
replace gc004_1=gc004_1_min if gc004==1 & mi(gc004_1) & ///
 !mi(gc004_1_min) & mi(gc004_1_max)  
replace gc004_2=(gc004_2_min+gc004_2_max)/2 if gc004==2 & mi(gc004_2) & ///
 !mi(gc004_2_min) & !mi(gc004_2_max)  //取中间值
replace gc004_2=gc004_2_max if gc004==2 & mi(gc004_2) & ///
 mi(gc004_2_min) & !mi(gc004_2_max)  
replace gc004_2=gc004_2_min if gc004==2 & mi(gc004_2) & ///
 !mi(gc004_2_min) & mi(gc004_2_max)  
replace gc004_2=gc004_2*(-1)  //亏损取负值
 
recode gc006_1 gc006_2 gc006_1_min gc006_1_max gc006_2_min gc006_2_max (-1=.d)
replace gc006_1=0 if gc001==2   //非农业家庭
replace gc006_2=0 if gc001==2
replace gc006_1=0 if gc006==3   //牲畜/水产品收入不赔不赚
replace gc006_2=0 if gc006==3
replace gc006_1=0 if gc005==2   //没有牲畜/水产品
replace gc006_2=0 if gc005==2
replace gc006_1=(gc006_1_min+gc006_1_max)/2 if gc006==1 & mi(gc006_1) & ///
 !mi(gc006_1_min) & !mi(gc006_1_max)  //取中间值
replace gc006_1=gc006_1_max if gc006==1 & mi(gc006_1) & ///
 mi(gc006_1_min) & !mi(gc006_1_max)  
replace gc006_1=gc006_1_min if gc006==1 & mi(gc006_1) & ///
 !mi(gc006_1_min) & mi(gc006_1_max)  
replace gc006_2=(gc006_2_min+gc006_2_max)/2 if gc006==2 & mi(gc006_2) & ///
 !mi(gc006_2_min) & !mi(gc006_2_max)  //取中间值
replace gc006_2=gc006_2_max if gc006==2 & mi(gc006_2) & ///
 mi(gc006_2_min) & !mi(gc006_2_max)  
replace gc006_2=gc006_2_min if gc006==2 & mi(gc006_2) & ///
 !mi(gc006_2_min) & mi(gc006_2_max)  
replace gc006_2=gc006_2*(-1)   //亏损取负值

***企业经营收入
recode gd004_1 gd004_2 gd004_1_min gd004_1_max gd004_2_min gd004_2_max (-1=.d)
replace gd004_1=0 if gd001==2   //非私营家庭
replace gd004_2=0 if gd001==2
replace gd004_1=0 if gd004==3   //经营收入不赔不赚
replace gd004_2=0 if gd004==3
replace gd004_1=(gd004_1_min+gd004_1_max)/2 if gd004==1 & mi(gd004_1) & ///
 !mi(gd004_1_min) & !mi(gd004_1_max)  //取中间值
replace gd004_1=gd004_1_max if gd004==1 & mi(gd004_1) & ///
 mi(gd004_1_min) & !mi(gd004_1_max)  
replace gd004_1=gd004_1_min if gd004==1 & mi(gd004_1) & ///
 !mi(gd004_1_min) & mi(gd004_1_max)  
replace gd004_2=(gd004_2_min+gd004_2_max)/2 if gd004==2 & mi(gd004_2) & ///
 !mi(gd004_2_min) & !mi(gd004_2_max)  //取中间值
replace gd004_2=gd004_2_max if gd004==2 & mi(gd004_2) & ///
 mi(gd004_2_min) & !mi(gd004_2_max)  
replace gd004_2=gd004_2_min if gd004==2 & mi(gd004_2) & ///
 !mi(gd004_2_min) & mi(gd004_2_max)  
replace gd004_2=gd004_2*(-1)

*****计算{农业收入+个体经营和私营}之和
egen hh5icap=rowtotal(gc004_1 gc004_2 gc006_1 gc006_2 gd004_1 gd004_2),mi //资本性收入=农业收入+经营收入
replace hh5icap=.m if gc001==.
replace hh5icap=.d if gc004_1==.d | gc004_2==.d | gc006_1==.d | gc006_2==.d | gd004_1==.d | gd004_2==.d 


***家户公共转移支付收入
*低保
recode ge004_1_ ge004_2_ ge004_3_ ge004_4_ ge004_5_ ge004_min_1_ ge004_max_1_ ///
  ge004_min_2_ ge004_max_2_ ge004_min_3_ ge004_max_3_ ge004_min_4_ ge004_max_4_ ///
  ge004_min_5_ ge004_max_5_ (-1=.d)
 
forvalues i=1/5 {
  replace ge004_`i'_=(ge004_min_`i'_ + ge004_max_`i'_)/2 if mi(ge004_`i'_) & !mi(ge004_min_`i'_) & !mi(ge004_max_`i'_) //取中间值
  replace ge004_`i'_=ge004_min_`i'_ if mi(ge004_`i'_) & !mi(ge004_min_`i'_) & mi(ge004_max_`i'_)
  replace ge004_`i'_=ge004_max_`i'_ if mi(ge004_`i'_) & mi(ge004_min_`i'_) & !mi(ge004_max_`i'_)
}  

*政府补助 
recode ge006_1 ge006_2 ge006_3 ge006_4 ge006_5 ge006_6 ge006_7 ge006_8 (-1=.d)

*农业保险赔付
recode ge007 (-1=.d)

*疫情补助
recode ge008_1 ge008_1_min ge008_1_max (-1=.d)
replace ge008_1=0 if ge008==2
replace ge008_1=(ge008_1_min + ge008_1_max)/2 if mi(ge008_1) & !mi(ge008_1_min) & !mi(ge008_1_max) //取中间值
replace ge008_1=ge008_1_min if mi(ge008_1) & !mi(ge008_1_min) & mi(ge008_1_max)
replace ge008_1=ge008_1_max if mi(ge008_1) & mi(ge008_1_min) & !mi(ge008_1_max)  

*光伏发电的收入
recode ge011 (-1=.d)  
replace ge011=0 if ge009==2

*土地出租
recode ge012 ge012_min ge012_max (-1=.d)  
replace ge012=(ge012_min + ge012_max)/2 if mi(ge012) & !mi(ge012_min) & !mi(ge012_max) //取中间值
replace ge012=ge012_min if mi(ge012) & !mi(ge012_min) & mi(ge012_max)
replace ge012=ge012_max if mi(ge012) & mi(ge012_min) & !mi(ge012_max)

*房产出租
recode ge013 ge013_min ge013_max (-1=.d)  
replace ge013=(ge013_min + ge013_max)/2 if mi(ge013) & !mi(ge013_min) & !mi(ge013_max) //取中间值
replace ge013=ge013_min if mi(ge013) & !mi(ge013_min) & mi(ge013_max)
replace ge013=ge013_max if mi(ge013) & mi(ge013_min) & !mi(ge013_max)

*出租其他家庭资产
recode ge014_1 (-1=.d)
replace ge014_1=0 if ge014==2
replace ge014_1=.d if ge014==997
replace ge014_1=.r if ge014==999

*****计算其他家庭成员的公共转移支出收入之和
egen hh5igxfr=rowtotal(ge004_1_ ge004_2_ ge004_3_ ge004_4_ ge004_5_ ge006_1 ///
 ge006_2 ge006_3 ge006_4 ge006_5 ge006_6 ge006_7 ge006_8 ge007 ge008_1 ge011 ///
 ge012 ge013 ge014_1),mi
replace hh5igxfr=.m if ge006_s9==. | ge001_s6==. 
replace hh5igxfr=.d if ge004_1_==.d | ge004_2_==.d | ge004_3_==.d | ge004_4_==.d | ///
 ge004_5_==.d | ge006_1==.d | ge006_2==.d | ge006_3==.d | ge006_4==.d | ge006_5==.d | ///
 ge006_6==.d | ge006_7==.d | ge006_8==.d | ge007==.d | ge008_1==.d | ge011==.d | ///
 ge012==.d | ge013==.d | ge014_1==.d 
replace hh5igxfr=.r if ge014_1==.r
 
***个人工资
recode ga002 ga002_min ga002_max (-1=.d)
replace ga002=0 if ga001==2 
replace ga002=(ga002_min + ga002_max)/2 if mi(ga002) & !mi(ga002_min) & !mi(ga002_max)
replace ga002=ga002_min if mi(ga002) & !mi(ga002_min) & mi(ga002_max)
replace ga002=ga002_max if mi(ga002) & mi(ga002_min) & !mi(ga002_max)

*个人工资应扣除杂费部分
recode ga004_1 ga004_1_min ga004_1_max ga004_2 ga004_3 (-1=.d)
gen r5ibonus=.
replace r5ibonus=(ga004_1_min + ga004_1_max)/2*12 if !mi(ga004_1_min) & !mi(ga004_1_max) & ga004==1
replace r5ibonus=ga004_1_min*12 if !mi(ga004_1_min) & mi(ga004_1_max) & ga004==1
replace r5ibonus=ga004_1_max*12 if mi(ga004_1_min) & !mi(ga004_1_max) & ga004==1
replace r5ibonus=ga004_2 if ga004==2
replace r5ibonus=ga002*(ga004_3/100) if !mi(ga002) & !mi(ga004_3) & ga004==3
replace r5ibonus=0 if ga004==4

gen r5itearn=ga002 
replace r5itearn=ga002-r5ibonus if ga003==2 & !mi(ga002) &!mi(r5ibonus)  //如果工资没有扣除杂费

*****计算受访者(配偶双方)的工资之和
bys householdID: egen h5itearn=total(r5itearn) if !mi(r5itearn)  

*****计算受访者(配偶双方)享受的公司福利
recode fc042_1 fc042_2 fc042_3 fc042_4 fc042_1_min fc042_1_max fc042_2_min ///
 fc042_2_max fc042_3_min fc042_3_max fc042_4_min fc042_4_max (-1=.d) (999=.r)
 
forvalues i=1/4 {
 replace fc042_`i'=(fc042_`i'_min + fc042_`i'_max)/2 if mi(fc042_`i') & !mi(fc042_`i'_min) & !mi(fc042_`i'_max)
 replace fc042_`i'=fc042_`i'_min if mi(fc042_`i') & !mi(fc042_`i'_min) & mi(fc042_`i'_max)
 replace fc042_`i'=fc042_`i'_max if mi(fc042_`i') & mi(fc042_`i'_min) & !mi(fc042_`i'_max)
}
forvalues i=1/4 {
 replace fc042_`i'=fc042_`i'*12 if !mi(fc042_`i')
}
egen r5iothr=rowtotal(fc042_1 fc042_2 fc042_3 fc042_4)
replace r5iothr=.d if fc042_1==.d | fc042_2==.d | fc042_3==.d | fc042_4==.d 
replace r5iothr=.r if fc042_1==.r | fc042_2==.r | fc042_3==.r | fc042_4==.r 
bys householdID: egen h5iothr=total(r5iothr) if !mi(r5iothr)  

***个人转移支付收入
recode ga005_1 ga005_1_min ga005_1_max ga005_2 ga005_3 ga005_4 ga005_5 ///
 ga005_6 ga005_7 ga005_8 ga005_9 (-1=.d)
replace ga005_1=(ga005_1_min + ga005_1_max)/2 if mi(ga005_1) & !mi(ga005_1_min) & !mi(ga005_1_max)
replace ga005_1=ga005_1_min if mi(ga005_1) & !mi(ga005_1_min) & mi(ga005_1_max)
replace ga005_1=ga005_1_max if mi(ga005_1) & mi(ga005_1_min) & !mi(ga005_1_max)
egen r5igxfr=rowtotal(ga005_1 ga005_2 ga005_3 ga005_4 ga005_5 ga005_6 ga005_7 ga005_8 ga005_9)
replace r5igxfr=.d if ga005_1==.d | ga005_2==.d | ga005_3==.d | ga005_4==.d | ///
  ga005_5==.d | ga005_6==.d | ga005_7==.d | ga005_8==.d | ga005_9==.d 
replace r5igxfr=.m if ga005_s10==.

*****计算受访者(配偶双方)的转移支付收入之和
bys householdID: egen h5igxfr=total(r5igxfr) if !mi(r5igxfr)  

* Xiaoai: each of the six income components is included once.
egen hh5itot=rowtotal(hh5iothhh hh5icap hh5igxfr h5itearn h5iothr h5igxfr),mi
replace hh5itot=.m if inw5==0
replace hh5itot=.m if mi(hh5iothhh) | mi(hh5icap) | mi(hh5igxfr) | mi(h5itearn) | mi(h5igxfr) | mi(h5iothr)
replace hh5itot=.d if hh5iothhh==.d | hh5icap==.d | hh5igxfr==.d | h5itearn==.d | h5igxfr==.d | h5iothr==.d
replace hh5itot=.r if hh5iothhh==.r | hh5icap==.r | hh5igxfr==.r | h5itearn==.r | h5igxfr==.r | h5iothr==.r

***是否退休
recode fh001 (2=0)
replace zrretired=fh001 if (zrretired==0 | zrretired==.) & !mi(fh001)
rename zrretired r5fret_c  

***过去一个月门诊
recode da005 (2=0),gen(r5doctor1m)  
rename da006 r5doctim1m   

***过去一年的住院
recode da007 (2=0),gen(r5hosp1y) 
rename da008 r5hsptim1y

***保存所需变量  
keep ID householdID communityID inw5 zrbirthyear r5gender r5educ_c r5mstath r5rural2 ///
  r5shlta r5smokev r5smoken r5drinkl r5total_cognition r5memeory r5executive r5cesd10 ///
  r5hibpe r5dyslipe r5diabe r5cancre r5lunge r5livere r5hearte r5stroke r5kidneye ///
  r5digeste r5psyche r5memrye r5arthre r5asthmae r5vgact_c r5mdact_c r5ltact_c ///
  r5act_1 r5act_2 r5act_3 r5act_4 r5act_5 r5act_6 r5act_7 r5act_8 hh5cperc r5iwy r5iwm ///
  h5rural r5ins r5pension h5child r5ea001s1 r5ea001s2 r5ea001s3 r5ea001s4 r5ea001s5 ///
  r5ea001s11 r5satlife h5hhres r5adlab_c r5iadl h5fcamt h5tcamt hh5itot r5fret_c ///
  r5doctor1m r5doctim1m r5hosp1y r5hsptim1y 
   
***final sort
sort ID

***compress dataset
compress	

***add label
label data "charls2020"

***save output dataset
save "$temp_data/charls2020", replace


* =============================================================================
* 第 6 段 / 共 6 段：五波合并 + Harmonized D + PSU → charls.dta
*   原文件 no.6_数据合并.do
* =============================================================================

****************************************************************************
use "$harmonized/H_CHARLS_D_Data 2.dta", clear     //导入数据 
merge 1:1 ID using "$temp_data/charls11.dta",nogen
merge 1:1 ID using "$temp_data/charls13.dta",nogen
merge 1:1 ID using "$temp_data/charls15.dta",nogen
merge 1:1 ID using "$temp_data/charls18.dta",nogen
merge 1:1 ID using "$temp_data/charls2020",nogen
merge m:1 communityID using "$psu2013",nogen   //已转 UTF-8 的副本

***是否参与本次调查
*inw1 inw2 inw3 inw4 inw5

***年龄 
*r1age r2age r3age r4age r5age
replace rabyear=zrbirthyear if mi(rabyear) & !mi(zrbirthyear)
forvalues i=1/5 {
  gen r`i'age=r`i'iwy-rabyear if !mi(r`i'iwy) & !mi(rabyear) //调查年份减出生年份
}

***性别
*ragender
* 修正：xrgender 是 CHARLS 对跨波性别冲突做过校正的版本，优先于 harmonized
* 的 ragender；ragender 只用来补 2020 未参与者。原写法 if mi(ragender) 会让
* 16 名两处记录冲突者中的 9 人取到未校正值。
replace ragender=r5gender if !mi(r5gender)   //2020 校正值优先
replace ragender=r5gender if mi(ragender)    //新增人群的性别
recode ragender (1=1) (2=0)  //男1 女0

***教育程度
*r1edu r2edu r3edu r4edu r5edu
gen r4educ_c=raeduc_c if inw4==1   
forvalues i=1/5 {
  recode r`i'educ_c (1/3=1) (4=2) (5=3) (6/11=4) (else=.),gen(r`i'edu)  
}  
 

***婚姻状况
*r1mstath r2mstath r3mstath r4mstath r5mstath
forvalues i=1/5 {
  recode r`i'mstath (1/3=1) (4/8=0)   //已婚为1,其他为0
} 

***户籍
*r1rural2 r2rural2 r3rural2 r4rural2 r5rural2  //农村1 城市0

***自评健康
*r1shlta r2shlta r3shlta r4shlta r5shlta
forvalues i=1/5 {
  recode r`i'shlta (1=5) (2=4) (3=3) (4=2) (5=1)   //越大越好
}

***吸烟
*r1smoken r2smoken r3smoken r4smoken r5smoken  //吸烟1不吸烟0

***曾经是否吸烟

***喝酒
*r1drinkl r2drinkl r3drinkl r4drinkl r5drinkl  //饮酒1不饮酒0

***曾经是否饮酒
*r1drinkev  r2drinkev  r3drinkev  r4drinkev  r5drinkev

***曾经是否吸烟
*r1smokev r2smokev r3smokev r4smokev r5smokev

***锻炼
*r1exercise r2exercise r3exercise r4exercise r5exercise
forvalues i=1/5 {
 gen r`i'exercise=. 
 replace r`i'exercise=1 if r`i'vgact_c==1 | r`i'mdact_c==1 | r`i'ltact_c==1
 replace r`i'exercise=0 if r`i'vgact_c==0 & r`i'mdact_c==0 & r`i'ltact_c==0
}

***社交活动
*省略

***认知功能
*r@total_cognation=r@memeory+r@executive
forvalues i=1/4 {
  gen r`i'memeory=r`i'tr20/2 
}

forvalues i=1/4 {
  egen r`i'executive=rowtotal(r`i'date_cognition r`i'ser7 r`i'draw)
  replace r`i'executive=. if mi(r`i'date_cognition) | mi(r`i'ser7) | mi(r`i'draw)
}

forvalues i=1/4 {
  egen r`i'total_cognition=rowtotal(r`i'memeory r`i'executive),mi //认知能力=情景记忆+心智状况
  replace r`i'total_cognition=.m if mi(r`i'executive) | mi(r`i'memeory)
  replace r`i'total_cognition=.d if r`i'executive==.d | r`i'memeory==.d
  replace r`i'total_cognition=.r if r`i'executive==.r | r`i'memeory==.r
  replace r`i'total_cognition=.p if r`i'executive==.p | r`i'memeory==.p   
}

***抑郁
*r1cesd10 r2cesd10 r3cesd10 r4cesd10 r5cesd10  //30分,数值越大越差

***慢性病
*r@hibpe r@diabe r@dyslipe r@cancre r@lunge r@livere r@hearte 
*r@stroke r@kidneye r@digeste r@psyche r@memrye r@arthre r@asthmae
forvalues i=1/5 {
egen r`i'chronic_num=rowtotal(r`i'hibpe  r`i'diabe  r`i'dyslipe  r`i'cancre ///
  r`i'lunge  r`i'livere r`i'hearte  r`i'stroke  r`i'kidneye  r`i'digeste ///
  r`i'psyche  r`i'memrye  r`i'arthre  r`i'asthmae)
replace r`i'chronic_num=. if mi(r`i'hibpe) & mi(r`i'diabe) & mi(r`i'dyslipe) & ///
  mi(r`i'cancre) & mi(r`i'lunge) & mi(r`i'livere) & mi(r`i'hearte) & ///
  mi(r`i'stroke) & mi(r`i'kidneye) & mi(r`i'digeste) & mi(r`i'psyche) & ///
  mi(r`i'memrye) & mi(r`i'arthre) & mi(r`i'asthmae) 
  recode r`i'chronic_num (0=0) (1/14=1) ,gen (r`i'chronic)   //是否有慢性病
}

***家庭人均消费
*hh1cperc hh2cperc hh3cperc hh4cperc hh5cperc  

***民族
*nation

***是否有医疗保险
*r1ins r2ins r3ins r4ins r5ins
forvalues i=1/4 {
  gen r`i'ins=.
  replace r`i'ins=1 if r`i'higov==1 | r`i'hipriv==1 | r`i'hiothp==1
  replace r`i'ins=0 if r`i'higov==0 & r`i'hipriv==0 & r`i'hiothp==0
}

***是否有养老保险
*r1pension r2pension r3pension r4pension r4pension r5pension
forvalues i=1/4 {
  gen r`i'pension=.
  replace r`i'pension=1 if r`i'pubpen==1 | r`i'peninc==1 | r`i'othpen==1 | r`i'jcpen==1 
  replace r`i'pension=0 if r`i'pubpen==0 & r`i'peninc==0 & r`i'othpen==0 & r`i'jcpen==0 
}

***健在子女数
*h1child h2child h3child h4child h5child

***代际支持
*h1fcamt h2fcamt h3fcamt h4fcamt h5fcamt 
*h1tcamt h2tcamt h3tcamt h4tcamt h5tcamt 

***是否残疾
*r1disability r2disability r3disability r4disability   //20年缺失

***ADL
*r1adlab_c r2adlab_c r3adlab_c r4adlab_c r5adlab_c  //参考CHARLS官方报告

***IADL
*r1iadl r2iadl r3iadl r4iadl r5iadl
forvalues i=1/4 {
  egen r`i'iadl=rowtotal(r`i'moneya r`i'medsa r`i'shopa r`i'mealsa r`i'housewka),mi  //参考CHARLS官方报告
}

***生活满意度
*r1satlife r2satlife r3satlife r4satlife r5satlife 

***家庭总收入
*hh1itot hh2itot hh3itot hh4itot hh5itot 

***家庭规模
*h1hhres h2hhres h3hhres h4hhres h5hhres


*****保留所需的变量
keep ID householdID communityID  ///
  inw1 inw2 inw3 inw4 inw5 city province ///
  r1iwy r2iwy r3iwy r4iwy r5iwy ///          /* 访问年份：PART 1 之后的所有筛选都靠它 */
  r1iwm r2iwm r3iwm r4iwm r5iwm ///          /* 访问月份 */
  r1rural2 r2rural2 r3rural2 r4rural2 r5rural2 ///   /* 户籍：13 个控制变量之一 */
  r1age r2age r3age r4age r5age ///
  ragender ///
  r1edu r2edu r3edu r4edu r5edu ///
  r1mstath r2mstath r3mstath r4mstath r5mstath ///
  r1shlta r2shlta r3shlta r4shlta r5shlta ///
  r1smoken r2smoken r3smoken r4smoken r5smoken ///
  r1drinkl r2drinkl r3drinkl r4drinkl r5drinkl ///
  r1drinkev r2drinkev r3drinkev r4drinkev ///
  r1smokev r2smokev r3smokev r4smokev r5smokev ///
  r1exercise r2exercise r3exercise r4exercise r5exercise ///
  r1vgact_c r1mdact_c r1ltact_c  /// 
  r2vgact_c r2mdact_c r2ltact_c  ///
  r3vgact_c r3mdact_c r3ltact_c  ///
  r4vgact_c r4mdact_c r4ltact_c  ///
  r5vgact_c r5mdact_c r5ltact_c  /// 
  r1act_1 r1act_2 r1act_3 r1act_4 r1act_5 r1act_6 r1act_7 r1act_8 ///
  r2act_1 r2act_2 r2act_3 r2act_4 r2act_5 r2act_6 r2act_7 r2act_8 ///
  r3act_1 r3act_2 r3act_3 r3act_4 r3act_5 r3act_6 r3act_7 r3act_8 ///
  r4act_1 r4act_2 r4act_3 r4act_4 r4act_5 r4act_6 r4act_7 r4act_8 ///
  r5act_1 r5act_2 r5act_3 r5act_4 r5act_5 r5act_6 r5act_7 r5act_8 ///
  r1total_cognition r2total_cognition r3total_cognition r4total_cognition r5total_cognition ///
  r1memeory r2memeory r3memeory r4memeory r5memeory ///
  r1executive r2executive r3executive r4executive r5executive ///
  r1cesd10 r2cesd10 r3cesd10 r4cesd10 r5cesd10 ///
  r1hibpe r1diabe r1dyslipe r1cancre r1lunge r1livere r1hearte ///
  r1stroke r1kidneye r1digeste r1psyche r1memrye r1arthre r1asthmae ///
  r2hibpe r2diabe r2dyslipe r2cancre r2lunge r2livere r2hearte ///
  r2stroke r2kidneye r2digeste r2psyche r2memrye r2arthre r2asthmae ///
  r3hibpe r3diabe r3dyslipe r3cancre r3lunge r3livere r3hearte ///
  r3stroke r3kidneye r3digeste r3psyche r3memrye r3arthre r3asthmae ///
  r4hibpe r4diabe r4dyslipe r4cancre r4lunge r4livere r4hearte ///
  r4stroke r4kidneye r4digeste r4psyche r4memrye r4arthre r4asthmae ///
  r5hibpe r5diabe r5dyslipe r5cancre r5lunge r5livere r5hearte ///
  r5stroke r5kidneye r5digeste r5psyche r5memrye r5arthre r5asthmae ///
  hh1cperc hh2cperc hh3cperc hh4cperc hh5cperc ///
  h1rural h2rural h3rural h4rural h5rural ///
  r1chronic r2chronic r3chronic r4chronic r5chronic ///
  nation r1ins r2ins r3ins r4ins r5ins ///
  r1pension r2pension r3pension r4pension r4pension r5pension ///
  h1child h2child h3child h4child h5child ///
  r1ea001s1 r1ea001s3 r1ea001s4 r1ea001s2 r1ea001s5 r1ea001s6 /// 
  r1ea001s7 r1ea001s8 r1ea001s11 r2ea001s1 r2ea001s3 r2ea001s4 /// 
  r2ea001s2 r2ea001s5 r2ea001s6 r2ea001s7 r2ea001s8 r2ea001s9  ///
  r2ea001s11 r3ea001s1 r3ea001s3 r3ea001s4 r3ea001s2 r3ea001s5 ///
  r3ea001s6 r3ea001s7 r3ea001s8 r3ea001s9 r3ea001s11 r4ea001s1 ///
  r4ea001s2 r4ea001s3 r4ea001s4 r4ea001s5 r4ea001s6 r4ea001s7 ///
  r4ea001s8 r4ea001s9 r4ea001s10 r4ea001s11 r5ea001s1 r5ea001s2 ///
  r5ea001s3 r5ea001s4 r5ea001s5 r5ea001s11 ///
  r1disability r2disability r3disability r4disability ///
  r1adlab_c r2adlab_c r3adlab_c r4adlab_c r5adlab_c ///
  r1iadl r2iadl r3iadl r4iadl r5iadl ///
  h1fcamt h2fcamt h3fcamt h4fcamt h5fcamt ///
  h1tcamt h2tcamt h3tcamt h4tcamt h5tcamt ///
  r1satlife r2satlife r3satlife r4satlife r5satlife ///
  hh1itot hh2itot hh3itot hh4itot hh5itot ///
  r1fret_c r2fret_c r3fret_c r4fret_c r5fret_c ///
  r1doctor1m r2doctor1m r3doctor1m r4doctor1m r5doctor1m ///
  r1doctim1m r2doctim1m r3doctim1m r4doctim1m r5doctim1m ///
  r1hosp1y r2hosp1y r3hosp1y r4hosp1y r5hosp1y ///
  r1hsptim1y r2hsptim1y r3hsptim1y r4hsptim1y r5hsptim1y ///
  h1hhres h2hhres h3hhres h4hhres h5hhres ///


*****将其转化为面板数据  
sreshape long inw@ r@iwy r@iwm r@rural2 r@age r@edu r@mstath r@shlta r@smoken r@drinkl r@exercise ///
  r@act_1 r@act_2 r@act_3 r@act_4 r@act_5 r@act_6 r@act_7 r@act_8 r@vgact_c r@mdact_c r@ltact_c ///
  r@total_cognition r@executive r@memeory r@cesd10 r@hibpe r@diabe r@dyslipe ///
  r@cancre r@lunge r@livere r@hearte r@stroke r@kidneye r@digeste r@psyche ///
  r@memrye r@arthre r@asthmae hh@cperc h@rural r@chronic r@ins r@pension h@child ///
  r@ea001s1 r@ea001s2 r@ea001s3 r@ea001s4 r@ea001s5 r@ea001s6 r@ea001s7 r@ea001s8 ///
  r@ea001s9 r@ea001s10 r@ea001s11 h@fcamt h@tcamt r@disability r@adlab_c r@iadl ///
  r@satlife hh@itot r@fret_c r@doctor1m r@doctim1m r@hosp1y r@hsptim1y h@hhres r@drinkev r@smokev,i(ID) j(year) 

  rename (ID year householdID communityID inw riwy riwm rrural2 rage ragender rmstath rshlta ///
  rhibpe rdiabe rcancre rlunge rhearte rstroke rpsyche rarthre rdyslipe ///
  rlivere rkidneye rdigeste rasthmae rmemrye rdrinkl rsmoken hhcperc ///
  rcesd10 ract_1 ract_2 ract_3 ract_4 ract_5 ract_6 ract_7 ract_8 ///
  province city redu rexercise rmemeory rexecutive rtotal_cognition hrural /// 
  rpension rins rchronic rea001s1 rea001s2 rea001s3 rea001s4 rea001s5 rea001s6 rea001s7 /// 
  rea001s8 rea001s9 rea001s10 rea001s11 hfcamt htcamt rdisability radlab_c ///
  riadl rsatlife hhitot rfret_c hhhres rdoctor1m rdoctim1m rhosp1y rhsptim1y ///
  rvgact_c rmdact_c rltact_c rdrinkev rsmokev) /// 
  (ID wave householdID communityID inw iwy iwm rural2 age gender marry srh hibpe /// 
  diabe cancre lunge hearte stroke psyche arthre dyslipe livere /// 
  kidneye digeste asthmae memrye drinkl smoken hhcperc cesd10 /// 
  act_1 act_2 act_3 act_4 act_5 act_6 act_7 act_8 province city edu /// 
  exercise memeory executive total_cognition rural pension ins chronic /// 
  ea001s1 ea001s2 ea001s3 ea001s4 ea001s5 ea001s6 ea001s7 ea001s8 ea001s9 /// 
  ea001s10 ea001s11 fcamt tcamt disability adlab_c iadl satlife income_total /// 
  retire family_size doctor doctor_time hospital hospital_time ///
  vgact_c mdact_c ltact_c drinkev smokev)   
   
*****上标签   
label var ID "受访者编码"  
label var wave "第几波调查"  
label var householdID "家庭编码"   
label var communityID "社区编码"    
label var inw "是否参与本轮调查" 
label var age "年龄" 
label var gender "性别" 
label var marry "婚姻" 
label var srh "自评健康" 
label var hibpe "高血压" 
label var diabe "糖尿病" 
label var cancre "癌症" 
label var lunge "肺病" 
label var hearte "心脏病" 
label var stroke "中风" 
label var psyche "精神疾病" 
label var arthre "关节炎" 
label var dyslipe "血脂异常" 
label var livere "肝脏疾病" 
label var kidneye "肾脏疾病" 
label var digeste "胃病" 
label var asthmae "哮喘病" 
label var memrye "记忆疾病" 
label var drinkl "现在是否饮酒" 
label var smoken "现在是否吸烟" 
label var drinkev "是否饮过酒"
label var smokev "是否吸过烟"
label var hhcperc "家庭人均消费" 
label var cesd10 "心理健康(30分,越大越差)" 
label var act_1 "串门" 
label var act_2 "打麻将" 
label var act_3 "提供帮助" 
label var act_4 "跳舞" 
label var act_5 "社团活动" 
label var act_6 "志愿者活动" 
label var act_7 "上学或培训" 
label var act_8 "其他社交"  
label var province "省份" 
label var city "城市" 
label var edu "教育"  
label var exercise "是否锻炼"  
label var vgact_c "重度锻炼"
label var mdact_c "中度锻炼"
label var ltact_c "轻度锻炼"
label var memeory "情景记忆(0~10分)" 
label var executive "心智状况(0~11分)" 
label var total_cognition "认知能力(0~21分,越大越好)" 
label var rural "居住地"
label var pension "是否有养老保险"
label var ins "是否有医疗保险"
label var chronic "是否有慢性病"
label var hchild "健在子女数"
label var nation "是否汉族"
label var ea001s1 "城镇职工医疗保险" 
label var ea001s2 "城乡居民医疗保险" 
label var ea001s3 "城镇居民医疗保险" 
label var ea001s4 " 新型农村合作医疗保险" 
label var ea001s5 "公费医疗" 
label var ea001s6 "医疗救助" 
label var ea001s7 "商业医疗保险: 单位购买" 
label var ea001s8 "商业医疗保险: 个人购买" 
label var ea001s9 "城镇无业居民大病医疗保险" 
label var ea001s10 "长期护理保险" 
label var ea001s11 "其他医疗保险" 
label var fcamt "子女对父母的经济支持"
label var tcamt "父母对子女的经济支持"
label var disability "是否残疾"
label var adlab_c "ADL"
label var iadl "IADL"
label var satlife  "生活满意度"
label var income_total "家庭总收入"
label var retire "是否退休"
label var family_size "家庭规模"
label var doctor "过去一个月是否门诊"
label var doctor_time "过去一个月门诊次数"
label var hospital "过去一年是否住院"
label var hospital_time "过去一年住院次数"

***只保留参与每一轮调查的样本
keep if inw==1   //只保留参与调查的个体
drop inw
label drop _all  //删除标签

***重新标签赋值
label define wave_ 1 "第1轮" 2 "第2轮" 3 "第3轮" 4 "第4轮" 5 "第5轮"
label value wave wave_ 

label define gender_ 0 "女性" 1 "男性"
label value gender gender_ 

label define edu_ 1 "小学以下" 2 "小学" 3 "中学" 4 "高中及以上" 
label value edu edu_

label define health_ 1 "很差" 2 "较差" 3 "一般" 4 "较好" 5 "很好"
label value srh health_

label define marry_ 0 "其他" 1 "已婚"
label value marry marry_

label define rural_ 0 "城市" 1 "农村"
label value rural rural_ 

label define yesno_ 0 "否" 1 "是"
label value ea001s10 ea001s9 ins pension chronic exercise nation disability ///
  ea001s11 ea001s8 ea001s7 ea001s6 ea001s5 ea001s2 ea001s4 ea001s3 ea001s1 ///
  act_8 act_7 act_6 act_5 act_4 act_3 act_2 act_1 retire doctor hospital ///
  smoken drinkl memrye asthmae digeste kidneye livere dyslipe arthre psyche ///
  stroke hearte lunge cancre diabe hibpe vgact_c mdact_c ltact_c drinkev smokev nation yesno_


save "$working_data/charls.dta",replace  //保存数据


isid ID wave
post `flowpost' ("01 raw-built individual panel") (_N)


* ==================== OUTCOME AND WORK ====================
use "$rawroot/harmonized/H_CHARLS_D_Data 2.dta", clear
keep ID r1goingl r2goingl r3goingl r4goingl
save "$temp_data/自杀proxy变量.dta", replace

use "$rawroot/CHARLS2020r/Health_Status_and_Functioning.dta", clear
keep ID dc025
rename dc025 r5goingl
merge 1:1 ID using "$temp_data/自杀proxy变量.dta"
drop _merge

reshape long r@goingl, i(ID) j(wave)
gen iwy = .
quietly bysort ID (ID): gen seq = _n
replace iwy = 2011 if seq == 1
replace iwy = 2013 if seq == 2
replace iwy = 2015 if seq == 3
replace iwy = 2018 if seq == 4
replace iwy = 2020 if seq == 5
drop wave
drop seq
save "$temp_data/自杀proxy.dta", replace

* -----------------------------------------------------------------------------
* 并入面板，生成 treat / post / did
* -----------------------------------------------------------------------------
use "$working_data/charls.dta", clear
count                                             // 96,628

merge 1:1 ID iwy using "$temp_data/自杀proxy.dta"
drop _merge
count                                             // 129,725

gen byte treat = 0

foreach cc in 西城区 和平区 迁安市 侯马市 包头市 大连市 长春市 大庆市 嘉定区 ///
              苏州市 无锡市 镇江市 杭州市 宁波市 桐乡市 马鞍山市 厦门市 宜春市 ///
              济南市 威海市 烟台市 郑州市 宜昌市 资兴市 珠海市 南宁市 琼海市 ///
              合川区 成都市 泸州市 贵阳市 玉溪市 拉萨市 宝鸡市 金昌市 格尔木市 ///
              银川市 克拉玛依市 {
    replace treat = 1 if city == "`cc'"
}
* 上面 38 个城市与 total do.do 第 32–79 行的 38 条 replace 语句完全一致，
* 只是改写成循环。2016 年国家卫计委首批健康城市试点名单。

gen byte post = iwy >= 2017
gen byte did  = treat * post

save "$temp_data/panel_merged.dta", replace

* -----------------------------------------------------------------------------
* 工作状态变量，再并回去
* -----------------------------------------------------------------------------
use "$rawroot/harmonized/H_CHARLS_D_Data 2.dta", clear
keep ID r1work r2work r3work r4work
save "$temp_data/work1.dta", replace

use "$rawroot/CHARLS2020r/Work_Retirement.dta", clear
keep ID xworking
rename xworking r5work
merge 1:1 ID using "$temp_data/work1.dta"
drop _merge

reshape long r@work, i(ID) j(wave)
gen iwy = .
quietly bysort ID (ID): gen seq = _n
replace iwy = 2011 if seq == 1
replace iwy = 2013 if seq == 2
replace iwy = 2015 if seq == 3
replace iwy = 2018 if seq == 4
replace iwy = 2020 if seq == 5
drop wave
drop seq
save "$temp_data/work.dta", replace

use "$temp_data/panel_merged.dta", clear
merge 1:1 ID iwy using "$temp_data/work.dta"
drop _merge
save "$temp_data/panel_merged.dta", replace

count                                             // 129,745


* ============================================================================

post `flowpost' ("02 merge outcome and work") (_N)


* ==================== CITY AND HOUSEHOLD SOURCE TABLES ====================
version 18.0
set type double
clear
set more off

* Stata cannot reliably open the 27 MB source workbook on this Mac. The helper
* extracts only named source columns to UTF-8 CSV; all cleaning remains here.
foreach f in city_yearbook_extract municipal_extract covid_city_year_extract {
    capture erase "$temp_data/`f'.csv"
}
shell "$python" "$code/prepare_source_workbooks.py" "$citybook" ///
    "$municipal" "$covidbook" "$temp_data"
confirm file "$temp_data/city_yearbook_extract.csv"
confirm file "$temp_data/municipal_extract.csv"
confirm file "$temp_data/covid_city_year_extract.csv"

* Statistical-yearbook city-year variables.
import delimited using "$temp_data/city_yearbook_extract.csv", ///
    varnames(1) encoding(UTF-8) clear
keep if inlist(iwy, 2011, 2013, 2015, 2018, 2020)
drop if missing(city) | missing(iwy)
replace city=strtrim(city)
replace city="北京" if city=="北京市"
replace city="天津" if city=="天津市"
isid city iwy
rename registered_population_10k 户籍人口万人
rename fixed_asset_investment_10k fixed_asset_investment
rename hospitals 医院卫生院数个
rename so2_tons 工业二氧化硫排放量吨
compress
save "$temp_data/city_yearbook_clean.dta", replace

* Municipal road and green-space variables.
import delimited using "$temp_data/municipal_extract.csv", ///
    varnames(1) encoding(UTF-8) clear
rename roadsurareapercap RoadSurAreaPerCap
rename greencoverageratebd GreenCoverageRateBD
keep if inlist(iwy, 2011, 2013, 2015, 2018, 2020)
drop if missing(city) | missing(iwy)
replace city=strtrim(city)
replace city="北京" if city=="北京市"
replace city="天津" if city=="天津市"
isid city iwy
compress
save "$temp_data/municipal_clean.dta", replace

* Annual COVID cumulative cases (thousands); only 2020 is used in the panel.
import delimited using "$temp_data/covid_city_year_extract.csv", ///
    varnames(1) encoding(UTF-8) clear
drop if missing(city) | missing(iwy)
replace city=strtrim(city)
replace city="北京" if city=="北京市"
replace city="天津" if city=="天津市"
isid city iwy
compress
save "$temp_data/covid_city_year.dta", replace

* PM2.5 source is already a city-year file supplied with the project.
use "$pm25", clear
keep iwy PR_ID PR CITY_ID city pm
drop if missing(city) | missing(iwy)
replace city = "北京" if city == "北京市"
replace city = "天津" if city == "天津市"
replace city=strtrim(city)
replace city="北京" if city=="北京市"
replace city="天津" if city=="天津市"
isid city iwy
compress
save "$temp_data/pm25_city_year.dta", replace

* Household medical expenditure. One record per household-year is required.
tempfile medall
local first = 1
forvalues w = 1/5 {
    local yy = cond(`w'==1,2011,cond(`w'==2,2013,cond(`w'==3,2015,cond(`w'==4,2018,2020))))
    local src = cond(`w'==1,"$raw2011/Household_Income.dta", ///
        cond(`w'==2,"$raw2013/Household_Income.dta", ///
        cond(`w'==3,"$raw2015/Household_Income.dta", ///
        cond(`w'==4,"$raw2018/Household_Income.dta", ///
        "$raw2020/Household_Income.dta"))))
    use "`src'", clear
    if `w' < 5 {
        keep householdID ge010_6
        rename ge010_6 medicalexp
    }
    else {
        keep householdID gf013_6
        rename gf013_6 medicalexp
    }
    if `w' == 1 replace householdID = householdID + "0"
    * Negative raw nonresponse codes cannot be monetary expenditure.
    * Original questionnaire values retained here; medical expenditure is not a model control.
    gen int iwy = `yy'
    isid householdID iwy
    if `first' {
        save `medall', replace
        local first = 0
    }
    else {
        append using `medall'
        save `medall', replace
    }
}
use `medall', clear
isid householdID iwy
compress
save "$temp_data/medical_household_year.dta", replace


* ==================== SAVE 0507 ====================

use "$temp_data/panel_merged.dta", clear
replace city=strtrim(city)
* Preserve author calendar-year matching; late interviews are reported losses.
keep if inlist(iwy,2011,2013,2015,2018,2020)
post `flowpost' ("03 nominal interview years retained") (_N)
drop if missing(city)
post `flowpost' ("04 nonempty city") (_N)
merge m:1 city iwy using "$temp_data/city_yearbook_clean.dta", keep(match) nogen
post `flowpost' ("05 author yearbook inner join") (_N)
merge m:1 city iwy using "$temp_data/municipal_clean.dta", keep(master match) nogen
merge m:1 householdID iwy using "$temp_data/medical_household_year.dta", keep(master match) nogen
drop if missing(rwork)
post `flowpost' ("06 nonmissing work status") (_N)
drop if inlist(rgoingl,997,999)
assert inrange(rgoingl,1,4) | missing(rgoingl)
post `flowpost' ("07 valid-or-missing outcome codes") (_N)
merge m:1 city iwy using "$temp_data/pm25_city_year.dta", keep(match using) gen(merge_pm25)
post `flowpost' ("08 author PM25 match and using rows") (_N)
gen byte has_person=!missing(ID) & !missing(wave)
bysort ID wave: assert _N==1 if has_person
merge m:1 city iwy using "$temp_data/covid_city_year.dta", keep(master match) gen(merge_covid)
replace covidnumber=0 if iwy<2020
* Missing 2020 case counts remain unknown; they are not invented zero cases.
gen double cpi_index=.
replace cpi_index=1 if iwy==2011
replace cpi_index=1.053702 if iwy==2013
replace cpi_index=1.091967 if iwy==2015
replace cpi_index=1.157663 if iwy==2018
replace cpi_index=1.217449 if iwy==2020
gen double real_inc_per=(income_total/family_size)/cpi_index if income_total>0 & income_total<. & family_size>0 & family_size<. & cpi_index<.
gen double log_real_inc_per=ln(real_inc_per) if real_inc_per>0 & real_inc_per<.
gen double hosper=医院卫生院数个/户籍人口万人 if 户籍人口万人>0 & 户籍人口万人<.
gen double ln_invest=ln(fixed_asset_investment) if fixed_asset_investment>0 & fixed_asset_investment<.
gen double act_12=act_1+act_2
gen double total_act=act_1+act_2+act_3+act_4+act_5+act_6+act_7+act_8
label var act_12 "Two-item social interaction score; both items required"
sort ID iwy
save "$analysisfile", replace
post `flowpost' ("09 saved newly built dataset 0507") (_N)
postclose `flowpost'
preserve
use `sampleflow', clear
export delimited using "$outpath/build_sample_flow.csv", replace
restore
display as result "RAW_TO_0507_COMPLETED"
}
if "`mode'"=="build" {
    log close
    exit
}
confirm file "$analysisfile"


* ==================== MAIN DID EVENT STUDY HETEROGENEITY ====================
version 18.0
set type double
clear
set more off
set seed 2025

foreach cmd in reghdfe esttab estpost {
    capture which `cmd'
    if _rc {
        di as error "Required Stata command is not installed: `cmd'"
        exit 199
    }
}

use "$analysisfile", clear
drop if missing(ID) | missing(wave)
isid ID wave

foreach vv in rgoingl_clean rgoingl_bin avg_log_inc inc_group city_num {
    capture drop `vv'
}
gen double rgoingl_clean = rgoingl
gen byte rgoingl_bin = rgoingl_clean > 1 if !missing(rgoingl_clean)
bysort ID: egen double avg_log_inc = mean(log_real_inc_per)
xtile inc_group = avg_log_inc, nq(3)
egen long city_num = group(city)

global ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire ///
    adlab_c smoken drinkl srh age
global ctrl_nonlinear $ctrl
global sample age >= 45 & age < . & rural == 0
* Main DID specifications; city-clustered inference is primary throughout.
reg rgoingl_clean did treat post $ctrl if $sample, vce(cluster city)
estimates store did_pooled
reghdfe rgoingl_clean did treat post $ctrl if $sample, ///
    absorb(city) vce(cluster city)
estimates store did_cityfe
reghdfe rgoingl_clean did treat post $ctrl if $sample, ///
    absorb(iwy) vce(cluster city)
estimates store did_yearfe
reghdfe rgoingl_clean did $ctrl if $sample, ///
    absorb(city iwy) vce(cluster city)
estimates store did_primary
gen byte baseline_sample = e(sample)
preserve
keep if baseline_sample
save "$outpath/primary_estimation_sample.dta", replace
restore

local main_b = _b[did]
local main_se = _se[did]
local main_p = 2*ttail(e(df_r),abs(_b[did]/_se[did]))
local main_ll = _b[did]-invttail(e(df_r),.025)*_se[did]
local main_ul = _b[did]+invttail(e(df_r),.025)*_se[did]
local main_n = e(N)
local main_g = e(N_clust)

egen byte city_tag = tag(city) if baseline_sample
quietly count if city_tag
local total_cities = r(N)
quietly count if city_tag & treat==1
local treated_cities = r(N)
local control_cities = `total_cities' - `treated_cities'

preserve
    clear
    set obs 1
    gen double DID = `main_b'
    gen double City_cluster_SE = `main_se'
    gen double P = `main_p'
    gen double CI_L = `main_ll'
    gen double CI_U = `main_ul'
    gen long Observations = `main_n'
    gen int Cities = `total_cities'
    gen int Treated_cities = `treated_cities'
    gen int Control_cities = `control_cities'
    export excel using "$outpath/main_DID_city_cluster.xlsx", ///
        firstrow(variables) replace
restore

esttab did_pooled did_cityfe did_yearfe did_primary ///
    using "$outpath/main_DID_models.rtf", replace keep(did) b(4) se(4) ///
    star(* .10 ** .05 *** .01) stats(N, fmt(0) labels("Observations")) ///
    mtitle("Pooled" "City FE" "Wave FE" "City and wave FE") ///
    title("HCPP and the outcome: city-clustered inference")

estpost summarize rgoingl_clean did treat post gender age marry ///
    log_real_inc_per rwork rural2 edu hchild retire adlab_c smoken drinkl srh ///
    GreenCoverageRateBD RoadSurAreaPerCap 工业二氧化硫排放量吨 hosper pm act_12 ///
    if baseline_sample
esttab using "$outpath/descriptive_analysis_sample.rtf", replace ///
    cells("count(fmt(0)) mean(fmt(3)) sd(fmt(3)) min(fmt(3)) max(fmt(3))") ///
    nonumber noobs title("Descriptive statistics: primary analytical sample")

* Event study: 2015 is the omitted last pre-policy survey wave.
foreach yy in 2011 2013 2018 2020 {
    capture drop evt_`yy'
    gen double evt_`yy' = treat*(iwy==`yy')
}
reghdfe rgoingl_clean evt_2011 evt_2013 evt_2018 evt_2020 $ctrl ///
    if $sample, absorb(city iwy) vce(cluster city)
estimates store event_study
test evt_2011 evt_2013
local pre_F = r(F)
local pre_p = r(p)

tempname evpost
tempfile evdata
postfile `evpost' int Wave double Estimate SE CI_L CI_U using `evdata', replace
foreach yy in 2011 2013 {
    quietly lincom evt_`yy'
    post `evpost' (`yy') (r(estimate)) (r(se)) (r(lb)) (r(ub))
}
post `evpost' (2015) (0) (0) (0) (0)
foreach yy in 2018 2020 {
    quietly lincom evt_`yy'
    post `evpost' (`yy') (r(estimate)) (r(se)) (r(lb)) (r(ub))
}
postclose `evpost'
preserve
    use `evdata', clear
    gen double Joint_pretrend_F = `pre_F'
    gen double Joint_pretrend_P = `pre_p'
    export excel using "$outpath/event_study_city_cluster.xlsx", ///
        firstrow(variables) replace
    twoway (rcap CI_L CI_U Wave if Wave!=2015, lcolor(navy)) ///
        (scatter Estimate Wave, mcolor(navy)), ///
        yline(0, lpattern(dash) lcolor(gs8)) ///
        xline(2016.5, lpattern(dash) lcolor(cranberry)) ///
        xlabel(2011 2013 2015 2018 2020) legend(off) ///
        xtitle("Survey wave") ytitle("Treatment × wave coefficient") ///
        title("Event-study estimates") subtitle("2015 reference wave") ///
        note("City and wave fixed effects; 95% CIs use city-clustered SEs.") ///
        graphregion(color(white))
    graph export "$outpath/event_study_city_cluster.png", replace width(2800)
restore

* Heterogeneity: subgroup estimates and formal DID interaction tests.
gen byte low_edu = edu==1 if !missing(edu)
gen byte working = rwork==1 if !missing(rwork)
gen byte male = gender==1 if !missing(gender)
tempname hethold
tempfile hetresults
postfile `hethold' str18 Dimension str18 Group double Coef SE P N Cities ///
    using `hetresults', replace

foreach gg in 1 2 3 {
    quietly reghdfe rgoingl_clean did $ctrl if $sample & inc_group==`gg', ///
        absorb(city iwy) vce(cluster city)
    post `hethold' ("Income") ("Tercile `gg'") (_b[did]) (_se[did]) ///
        (2*ttail(e(df_r),abs(_b[did]/_se[did]))) (e(N)) (e(N_clust))
}
foreach spec in "Education low_edu" "Work working" "Gender male" {
    tokenize `"`spec'"'
    local dim "`1'"
    local gvar "`2'"
    local subctrl "$ctrl"
    if "`dim'" == "Education" local subctrl : subinstr local subctrl "edu" "", word all
    if "`dim'" == "Work" local subctrl : subinstr local subctrl "rwork" "", word all
    if "`dim'" == "Gender" local subctrl : subinstr local subctrl "gender" "", word all
    foreach gg in 0 1 {
        quietly reghdfe rgoingl_clean did `subctrl' if $sample & `gvar'==`gg', ///
            absorb(city iwy) vce(cluster city)
        post `hethold' ("`dim'") ("`gvar'=`gg'") (_b[did]) (_se[did]) ///
            (2*ttail(e(df_r),abs(_b[did]/_se[did]))) (e(N)) (e(N_clust))
    }
}
postclose `hethold'
preserve
    use `hetresults', clear
    export excel using "$outpath/heterogeneity_subgroups_city_cluster.xlsx", ///
        firstrow(variables) replace
restore

foreach vv in low_income mid_income high_income low_edu working male ///
    did_lowinc did_midinc did_highinc did_lowedu did_working did_male ///
    treat_lowinc post_lowinc treat_midinc post_midinc ///
    treat_highinc post_highinc treat_lowedu post_lowedu ///
    treat_working post_working treat_male post_male {
    capture drop `vv'
}

gen byte low_income  = (inc_group == 1) if !missing(inc_group)
gen byte mid_income  = (inc_group == 2) if !missing(inc_group)
gen byte high_income = (inc_group == 3) if !missing(inc_group)
gen byte low_edu     = (edu == 1) if !missing(edu)
gen byte working     = (rwork == 1) if !missing(rwork)
gen byte male        = (gender == 1) if !missing(gender)

foreach gg in lowinc midinc highinc lowedu working male {
    local gv = cond("`gg'"=="lowinc", "low_income", ///
        cond("`gg'"=="midinc", "mid_income", ///
        cond("`gg'"=="highinc", "high_income", ///
        cond("`gg'"=="lowedu", "low_edu", ///
        cond("`gg'"=="working", "working", "male")))))
    gen double did_`gg'   = did   * `gv'
    gen double treat_`gg' = treat * `gv'
    gen double post_`gg'  = post  * `gv'
}

tempname hethold
tempfile heterogeneity_results
postfile `hethold' str30 Test double Coef SE P CI_L CI_U N ///
    using `heterogeneity_results', replace

reghdfe rgoingl_clean did low_income treat_lowinc post_lowinc did_lowinc ///
    $ctrl if $sample, absorb(city iwy) vce(cluster city)
quietly lincom did_lowinc
post `hethold' ("Low income x DID") (r(estimate)) (r(se)) (r(p)) ///
    (r(lb)) (r(ub)) (e(N))

reghdfe rgoingl_clean did mid_income treat_midinc post_midinc did_midinc ///
    $ctrl if $sample, absorb(city iwy) vce(cluster city)
quietly lincom did_midinc
post `hethold' ("Middle income x DID") (r(estimate)) (r(se)) (r(p)) ///
    (r(lb)) (r(ub)) (e(N))

reghdfe rgoingl_clean did high_income treat_highinc post_highinc did_highinc ///
    $ctrl if $sample, absorb(city iwy) vce(cluster city)
quietly lincom did_highinc
post `hethold' ("High income x DID") (r(estimate)) (r(se)) (r(p)) ///
    (r(lb)) (r(ub)) (e(N))

reghdfe rgoingl_clean did low_edu treat_lowedu post_lowedu did_lowedu ///
    gender marry log_real_inc_per rwork rural2 hchild retire adlab_c ///
    smoken drinkl srh age if $sample, absorb(city iwy) vce(cluster city)
quietly lincom did_lowedu
post `hethold' ("Low education x DID") (r(estimate)) (r(se)) (r(p)) ///
    (r(lb)) (r(ub)) (e(N))

reghdfe rgoingl_clean did working treat_working post_working did_working ///
    gender marry log_real_inc_per rural2 edu hchild retire adlab_c ///
    smoken drinkl srh age if $sample, absorb(city iwy) vce(cluster city)
quietly lincom did_working
post `hethold' ("Working x DID") (r(estimate)) (r(se)) (r(p)) ///
    (r(lb)) (r(ub)) (e(N))

reghdfe rgoingl_clean did male treat_male post_male did_male ///
    marry log_real_inc_per rwork rural2 edu hchild retire adlab_c ///
    smoken drinkl srh age if $sample, absorb(city iwy) vce(cluster city)
quietly lincom did_male
post `hethold' ("Male x DID") (r(estimate)) (r(se)) (r(p)) ///
    (r(lb)) (r(ub)) (e(N))
postclose `hethold'

preserve
    use `heterogeneity_results', clear
    format Coef SE CI_L CI_U P %10.4f
    export excel using "$outpath/heterogeneity_interactions_city_cluster.xlsx", ///
        firstrow(variables) replace
restore

* ============================================================================
* PART 4C. JOINT GROUP INTERCEPT/SLOPE TESTS WITH COMMON CITY/WAVE FE
* H0: group intercept differences and every group-specific slope difference
*     (DID, Treat, Post, and all applicable controls) are jointly zero.
* This does not allow group-specific city/wave fixed effects.
* Income strata use all-wave person means and are exploratory, post-treatment strata.
* ============================================================================

local x_income did treat post gender marry log_real_inc_per rwork rural2 ///
    edu hchild retire adlab_c smoken drinkl srh age
local x_edu did treat post gender marry log_real_inc_per rwork rural2 ///
    hchild retire adlab_c smoken drinkl srh age
local x_work did treat post gender marry log_real_inc_per rural2 edu ///
    hchild retire adlab_c smoken drinkl srh age
local x_gender did treat post marry log_real_inc_per rwork rural2 edu ///
    hchild retire adlab_c smoken drinkl srh age

tempname chowhold
tempfile chow_results
postfile `chowhold' str24 Grouping double F_stat df1 df2 P_value N ///
    City_clusters using `chow_results', replace

fvset base 1 inc_group
reghdfe rgoingl_clean i.inc_group##c.(`x_income') if $sample, ///
    absorb(city iwy) vce(cluster city)
estimates store chow_income
local model_N = e(N)
local model_G = e(N_clust)
testparm i.inc_group i.inc_group#c.(`x_income')
post `chowhold' ("Income tertile") ///
    (r(F)) (r(df)) (r(df_r)) (r(p)) (`model_N') (`model_G')

fvset base 0 low_edu
reghdfe rgoingl_clean i.low_edu##c.(`x_edu') if $sample, ///
    absorb(city iwy) vce(cluster city)
estimates store chow_education
local model_N = e(N)
local model_G = e(N_clust)
testparm i.low_edu i.low_edu#c.(`x_edu')
post `chowhold' ("Education") ///
    (r(F)) (r(df)) (r(df_r)) (r(p)) (`model_N') (`model_G')

fvset base 0 working
reghdfe rgoingl_clean i.working##c.(`x_work') if $sample, ///
    absorb(city iwy) vce(cluster city)
estimates store chow_employment
local model_N = e(N)
local model_G = e(N_clust)
testparm i.working i.working#c.(`x_work')
post `chowhold' ("Employment") ///
    (r(F)) (r(df)) (r(df_r)) (r(p)) (`model_N') (`model_G')

fvset base 0 male
reghdfe rgoingl_clean i.male##c.(`x_gender') if $sample, ///
    absorb(city iwy) vce(cluster city)
estimates store chow_gender
local model_N = e(N)
local model_G = e(N_clust)
testparm i.male i.male#c.(`x_gender')
post `chowhold' ("Gender") ///
    (r(F)) (r(df)) (r(df_r)) (r(p)) (`model_N') (`model_G')

postclose `chowhold'

preserve
    use `chow_results', clear
    format F_stat %10.3f
    format df1 df2 N City_clusters %10.0f
    format P_value %10.6f
    export excel using "$outpath/full_chow_tests_city_cluster.xlsx", ///
        firstrow(variables) replace
    list Grouping F_stat df1 df2 P_value N City_clusters, noobs
restore


* Mechanism Panel A (DID -> mediator) and Panel B (mediator -> outcome).
tempname mechpost
tempfile mechresults
postfile `mechpost' str8 Panel str20 Mediator double Coef SE P N Cities ///
    using `mechresults', replace
foreach item in "Green GreenCoverageRateBD" "Road RoadSurAreaPerCap" ///
    "SO2 工业二氧化硫排放量吨" "Medical hosper" "PM25 pm" "Social act_12" {
    tokenize `"`item'"'
    local lab "`1'"
    local med "`2'"
    tempvar medsample
    gen byte `medsample' = baseline_sample & !missing(`med')
    quietly reghdfe `med' did $ctrl if `medsample', ///
        absorb(city iwy) vce(cluster city)
    post `mechpost' ("Panel A") ("`lab'") (_b[did]) (_se[did]) ///
        (2*ttail(e(df_r),abs(_b[did]/_se[did]))) (e(N)) (e(N_clust))
    quietly reghdfe rgoingl_clean `med' did $ctrl if `medsample', ///
        absorb(city iwy) vce(cluster city)
    post `mechpost' ("Panel B") ("`lab'") (_b[`med']) (_se[`med']) ///
        (2*ttail(e(df_r),abs(_b[`med']/_se[`med']))) (e(N)) (e(N_clust))
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
    export excel using "$outpath/mechanism_panelAB_city_cluster.xlsx", ///
        firstrow(variables) replace
restore


* Binary LPM and legacy individual-clustered inference, once each.
reghdfe rgoingl_bin did $ctrl if $sample, absorb(city iwy) vce(cluster city)
estimates store robust_lpm
reghdfe rgoingl_clean did $ctrl if $sample, absorb(city iwy) vce(cluster ID)
estimates store legacy_individual_cluster
esttab robust_lpm legacy_individual_cluster using "$outpath/appendix_LPM_individual_cluster.rtf", replace keep(did) b(6) se(6) stats(N)


* ==================== PREPOLICY PSM ONLY ====================
version 18.0
set type double
clear
set more off
set rng mt64
set seed 2025
set sortseed 2025

use "$analysisfile", clear
drop if missing(ID) | missing(wave)
isid ID wave

foreach vv in cpi_index real_inc_per log_real_inc_per rgoingl_str rgoingl_clean {
    capture drop `vv'
}
gen double cpi_index = .
replace cpi_index = 1.000000 if iwy == 2011
replace cpi_index = 1.053702 if iwy == 2013
replace cpi_index = 1.091967 if iwy == 2015
replace cpi_index = 1.157663 if iwy == 2018
replace cpi_index = 1.217449 if iwy == 2020
gen double real_inc_per = (income_total / family_size) / cpi_index ///
    if income_total > 0 & family_size > 0 & !missing(cpi_index)
gen double log_real_inc_per = log(real_inc_per) if real_inc_per > 0
gen double rgoingl_clean = rgoingl

global psmvars gender marry log_real_inc_per rwork rural2 edu hchild retire ///
    adlab_c smoken drinkl srh
global ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire ///
    adlab_c smoken drinkl srh age
global sample age >= 45 & age < . & rural == 0
tempfile panel preweights balances
save `panel', replace

* One pre-policy covariate vector per respondent, using 2011-2015 means only.
keep if inlist(iwy, 2011, 2013, 2015) & $sample
assert !missing(age) & age >=45
keep ID city treat $psmvars
bysort ID: assert treat == treat[1]
bysort ID: assert city == city[1]
collapse (mean) treat $psmvars (firstnm) city, by(ID)
drop if missing(treat, city)
egen byte complete_pre = rownonmiss($psmvars)
keep if complete_pre == 12
drop complete_pre

logit treat $psmvars
local ps_N = e(N)
local ps_r2 = e(r2_p)
local ps_chi2 = e(chi2)
local ps_lr_p = e(p)
lroc, nograph
local ps_auc = r(area)
predict double pscore_pre, pr

gen double random_order = runiform()
sort random_order
psmatch2 treat, pscore(pscore_pre) kernel kerneltype(epan) ///
    bwidth(0.06) common ties

count if treat == 1
local treated_total = r(N)
count if treat == 1 & _support == 1
local treated_support = r(N)
count if treat == 0
local control_total = r(N)
count if treat == 0 & _support == 1
local control_support = r(N)
* Common support and strictly positive donor weight are distinct counts.
count if treat==0 & _support==1 & _weight>0 & _weight<.
local control_positive = r(N)

* Construct a complete machine-readable covariate balance table.
tempname balhold
tempfile balance_results
postfile `balhold' str25 Variable ///
    double Mean_T_U Mean_C_U Bias_U P_U VarRatio_U ///
           Mean_T_M Mean_C_M Bias_M BiasReduction P_M VarRatio_M ///
    using `balance_results', replace

foreach vv of global psmvars {
    quietly summarize `vv' if treat == 1, detail
    local mtu = r(mean)
    local vtu = r(Var)
    quietly summarize `vv' if treat == 0, detail
    local mcu = r(mean)
    local vcu = r(Var)
    local bu = 100 * (`mtu' - `mcu') / sqrt((`vtu' + `vcu') / 2)
    local vru = `vtu' / `vcu'
    quietly regress `vv' treat , vce(cluster city)
    local pu = 2 * ttail(e(df_r),abs(_b[treat] / _se[treat]))

    quietly summarize `vv' [aw=_weight] ///
        if treat == 1 & _support == 1, detail
    local mtm = r(mean)
    local vtm = r(Var)
    quietly summarize `vv' [aw=_weight] ///
        if treat == 0 & _support == 1, detail
    local mcm = r(mean)
    local vcm = r(Var)
    local bm = 100 * (`mtm' - `mcm') / sqrt((`vtu' + `vcu') / 2)
    local vrm = `vtm' / `vcm'
    local reduction = cond(abs(`bu') > 1e-12, ///
        100 * (abs(`bu') - abs(`bm')) / abs(`bu'), .)
    quietly regress `vv' treat [aw=_weight] ///
        if _support == 1, vce(cluster city)
    local pm = 2 * ttail(e(df_r),abs(_b[treat] / _se[treat]))

    post `balhold' ("`vv'") (`mtu') (`mcu') (`bu') (`pu') (`vru') ///
        (`mtm') (`mcm') (`bm') (`reduction') (`pm') (`vrm')
}
postclose `balhold'

preserve
    use `balance_results', clear
    format Mean_T_U Mean_C_U Mean_T_M Mean_C_M %10.4f
    format Bias_U Bias_M BiasReduction %10.2f
    format P_U P_M VarRatio_U VarRatio_M %10.4f
    export excel using "$outpath/prepolicy_psm_balance.xlsx", ///
        firstrow(variables) replace
restore


pstest $psmvars, both graph
graph export "$outpath/prepolicy_psm_balance.png", replace width(2800)
twoway (kdensity pscore_pre if treat==1, lcolor(navy)) ///
    (kdensity pscore_pre if treat==0, lcolor(maroon) lpattern(dash)), ///
    legend(order(1 "Treated" 2 "Controls")) name(ps_before, replace) ///
    title("Before matching") xtitle("Propensity score") graphregion(color(white))
twoway (kdensity pscore_pre [aw=_weight] if treat==1 & _support==1 & _weight>0 & _weight<., lcolor(navy)) ///
    (kdensity pscore_pre [aw=_weight] if treat==0 & _support==1 & _weight>0 & _weight<., lcolor(maroon) lpattern(dash)), ///
    legend(order(1 "Treated" 2 "Weighted controls")) name(ps_after, replace) ///
    title("After kernel matching") xtitle("Propensity score") graphregion(color(white))
graph combine ps_before ps_after, cols(2) graphregion(color(white))
graph export "$outpath/prepolicy_psm_overlap.png", replace width(3200)
count if _weight>0 & _weight<. & _support==1
local positive_weight_people = r(N)
save "$outpath/prepolicy_psm_diagnostics.dta", replace

keep ID pscore_pre _weight _support
save `preweights', replace

use `panel', clear
merge m:1 ID using `preweights', keep(match) nogen

reghdfe rgoingl_clean did $ctrl [pweight=_weight] ///
    if _support == 1 & $sample, absorb(city iwy) vce(cluster city)

local did_b = _b[did]
local did_se = _se[did]
local did_p = 2 * ttail(e(df_r), abs(_b[did] / _se[did]))
local did_ll = _b[did] - invttail(e(df_r), .025) * _se[did]
local did_ul = _b[did] + invttail(e(df_r), .025) * _se[did]
local did_N = e(N)
local city_clusters = e(N_clust)
egen byte person_tag = tag(ID) if e(sample)
quietly count if person_tag
local analysis_people = r(N)

preserve
clear
set obs 1
gen str50 specification = "2011-2015 pre-policy respondent means"
gen double coefficient = `did_b'
gen double city_cluster_se = `did_se'
gen double p_value = `did_p'
gen double ci_lower = `did_ll'
gen double ci_upper = `did_ul'
gen long observations = `did_N'
gen int city_clusters = `city_clusters'
gen long propensity_individuals = `ps_N'
gen double propensity_pseudo_r2 = `ps_r2'
gen double propensity_LR_chi2 = `ps_chi2'
gen double propensity_LR_p = `ps_lr_p'
gen double propensity_AUC = `ps_auc'
gen long positive_weight_people = `positive_weight_people'
gen long analysis_people = `analysis_people'
gen long treated_total = `treated_total'
gen long treated_on_support = `treated_support'
gen long control_total = `control_total'
gen long control_on_support = `control_support'
gen long control_positive_weight = `control_positive'
export excel using "$outpath/prepolicy_means_psmdid_summary.xlsx", ///
    firstrow(variables) replace
list, noobs abbreviate(32)
restore


* ==================== NONLINEAR INDIVIDUAL FE INCOME MISSINGNESS CITY MEDIATION ====================
version 18.0
clear
set more off
set type double
set seed 2025
set rmsg off

use "$analysisfile", clear
drop if missing(ID) | missing(wave)
isid ID wave

foreach vv in cpi_index real_inc_per log_real_inc_per avg_log_inc inc_group act_12 rgoingl_str rgoingl_clean rgoingl_bin city_num {
    capture drop `vv'
}
gen double cpi_index = .
replace cpi_index = 1.000000 if iwy == 2011
replace cpi_index = 1.053702 if iwy == 2013
replace cpi_index = 1.091967 if iwy == 2015
replace cpi_index = 1.157663 if iwy == 2018
replace cpi_index = 1.217449 if iwy == 2020
gen double real_inc_per = (income_total / family_size) / cpi_index ///
    if income_total > 0 & family_size > 0 & !missing(cpi_index)
gen double log_real_inc_per = log(real_inc_per) if real_inc_per > 0
bysort ID: egen double avg_log_inc = mean(log_real_inc_per)
xtile inc_group = avg_log_inc, nq(3)
gen double act_12 = act_1 + act_2
gen double rgoingl_clean = rgoingl
gen byte rgoingl_bin = (rgoingl_clean > 1) if !missing(rgoingl_clean)
egen long city_num = group(city)

global ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire ///
    adlab_c smoken drinkl srh age
global sample age >= 45 & age < . & rural == 0


quietly reghdfe rgoingl_clean did $ctrl if $sample, ///
    absorb(city iwy) vce(cluster city)
gen byte baseline_sample = e(sample)

* Nonlinear diagnostics: identical 13 controls and primary starting sample.
* Ordered and binary logit use explicit city and survey-year indicators.
quietly count if baseline_sample
local base_n = r(N)
quietly tabulate city_num if baseline_sample, generate(nlc_)
quietly tabulate iwy if baseline_sample, generate(nly_)
drop nlc_1 nly_1
unab indicators : nlc_* nly_*

* ---------------------------------------------------------------------------
* Xiaoai 2026-09-16 correction.
* The earlier version counted "certain" predictions only when the fitted
* probability of the observed category exceeded 1 - 1e-10.  That cut-off is
* far stricter than the condition behind Stata's own note
*     "Note: N observations completely determined. Standard errors questionable."
* so the summary table recorded 0 while the log recorded 23, and the table
* therefore described the ordered logit as an unqualified converged model.
*
* The structural cause is checked directly and exactly instead of guessing a
* probability cut-off: an indicator level whose outcome never varies inside the
* estimation sample is not identified.  ologit keeps those rows and lets the
* indicator diverge (hence "completely determined"); logit drops the indicator
* and the rows.  This scan is deterministic and does not depend on a tolerance.
* ---------------------------------------------------------------------------
tempvar ymin ymax sepflag septag wymin wymax wsepflag
bysort city_num: egen double `ymin' = min(cond(baseline_sample, rgoingl_clean, .))
bysort city_num: egen double `ymax' = max(cond(baseline_sample, rgoingl_clean, .))
gen byte `sepflag' = (baseline_sample == 1 & `ymin' == `ymax' & !missing(`ymin'))
bysort iwy: egen double `wymin' = min(cond(baseline_sample, rgoingl_clean, .))
bysort iwy: egen double `wymax' = max(cond(baseline_sample, rgoingl_clean, .))
gen byte `wsepflag' = (baseline_sample == 1 & `wymin' == `wymax' & !missing(`wymin'))
quietly count if `sepflag' | `wsepflag'
local sep_obs = r(N)
egen byte `septag' = tag(city_num) if `sepflag'
quietly count if `septag' == 1
local sep_cities = r(N)
display "SEPARATION_SCAN: degenerate-outcome cities=" `sep_cities' ///
    "; affected observations=" `sep_obs'
preserve
    keep if `sepflag' | `wsepflag'
    quietly count
    if r(N)>0 {
        collapse (count) Observations = wave (min) Outcome_min = rgoingl_clean ///
            (max) Outcome_max = rgoingl_clean (mean) Treated = treat, by(city iwy)
        export delimited using "$outpath/nonlinear_separation_cells.csv", replace
        list, clean noobs
    }
restore

tempname nlpost
tempfile nlresults
postfile `nlpost' str46 Model double Coef double SE double P long N long Base_N ///
    int Clusters int Parameters byte Params_exceed_clusters byte Wald_unavailable ///
    int Return_code byte Converged ///
    long Separated_obs int Separated_cities ///
    long Certain_1e10 long Certain_1e6 double Max_obs_prob ///
    double Max_abs_indicator_coef long Negative_fitted_prob ///
    str512 Status using `nlresults', replace

foreach model in ologit logit {
    local b=.
    local se=.
    local p=.
    local n=.
    local g=.
    local cv=.
    local c10=.
    local c6=.
    local maxpr=.
    local maxind=.
    local negprob=.
    local npar=.
    local pexc=.
    local waldna=.
    local sepo=`sep_obs'
    local sepc=`sep_cities'
    local status "Not estimated"
    ereturn clear
    if "`model'"=="ologit" {
        capture noisily ologit rgoingl_clean did $ctrl `indicators' if baseline_sample, vce(cluster city_num) iterate(100)
        local rc = _rc
    }
    else if "`model'"=="logit" {
        capture noisily logit rgoingl_bin did $ctrl `indicators' if baseline_sample, vce(cluster city_num) iterate(100)
        local rc = _rc
    }
    if `rc'==0 | `rc'==430 {
        capture local cv = e(converged)
        capture local n = e(N)
        capture local g = e(N_clust)
        capture local b = _b[did]
        capture local se = _se[did]
        if `se'>0 & `se'<. local p = 2*normal(-abs(`b'/`se'))
        local maxind = 0
        foreach vv of local indicators {
            capture local cc = abs(_b[`vv'])
            if !missing(`cc') & `cc' > `maxind' local maxind = `cc'
        }
        * Record parameter counts and any unavailable overall Wald test.
        * The actual cluster count is derived from each estimation sample.
        capture local npar = colsof(e(b))
        capture local waldna = missing(e(chi2))
        if `npar'<. & `g'<. local pexc = (`npar' > `g')
        local status "Converged; diagnostic specification"
        if `cv'!=1 local status "Not converged; not robustness evidence"
        if "`model'"=="ologit" & `cv'==1 {
            tempvar p1 p2 p3 p4 obsprob
            quietly predict double `p1' `p2' `p3' `p4' if e(sample), pr
            gen double `obsprob' = cond(rgoingl_clean==1,`p1',cond(rgoingl_clean==2,`p2',cond(rgoingl_clean==3,`p3',`p4'))) if e(sample)
            quietly count if `obsprob' > 1-1e-10 & `obsprob' < .
            local c10 = r(N)
            quietly count if `obsprob' > 1-1e-6 & `obsprob' < .
            local c6 = r(N)
            quietly summarize `obsprob' if e(sample)
            local maxpr = r(max)
            drop `p1' `p2' `p3' `p4' `obsprob'
        }
        if "`model'"=="logit" & `cv'==1 & `n'<`base_n' {
            local status "Converged; `=`base_n'-`n'' observations dropped by perfect prediction; clusters `g'; diagnostic only"
        }
        * Separation must override any plain "converged" wording.
        if `sepo' > 0 & `cv'==1 & "`model'"!="logit" {
            local status "Converged, but `sepc' city/wave cell(s) with an invariant outcome leave `sepo' observations completely determined; Stata reports questionable standard errors for the affected indicator; not unrestricted robustness evidence"
        }
        if `pexc'==1 {
            local status "`status'; parameters (`npar') exceed clusters (`g'), cluster-robust covariance is rank deficient and the overall Wald test is unavailable"
        }
    }
    else local status "Estimation error; not robustness evidence"
    local mlabel "`model' + city and wave indicators"
    post `nlpost' ("`mlabel'") (`b') (`se') (`p') (`n') (`base_n') (`g') ///
        (`npar') (`pexc') (`waldna') (`rc') (`cv') ///
        (`sepo') (`sepc') (`c10') (`c6') (`maxpr') (`maxind') (`negprob') ("`status'")
}
postclose `nlpost'
preserve
use `nlresults', clear
label variable Separated_obs "Observations in city/wave cells with an invariant outcome"
label variable Certain_1e10 "Fitted probability of observed category > 1-1e-10"
label variable Certain_1e6 "Fitted probability of observed category > 1-1e-6"
label variable Negative_fitted_prob "Not applicable to ordered/binary logit"
label variable Params_exceed_clusters "Estimated parameters exceed city clusters"
label variable Wald_unavailable "Stata could not report the overall Wald test"
export excel using "$outpath/nonlinear_cityFE_citycluster.xlsx", firstrow(variables) replace
export delimited using "$outpath/nonlinear_cityFE_citycluster.csv", replace
list, clean noobs
restore

* --------------------------------------------------------------------------
* B. Individual fixed-effects sensitivity model; time-invariant and perfectly
*    collinear controls are automatically omitted. Inference clusters by city.
* --------------------------------------------------------------------------
reghdfe rgoingl_clean did $ctrl if $sample, absorb(ID iwy) vce(cluster city)
local ife_b = _b[did]
local ife_se = _se[did]
local ife_p = 2 * ttail(e(df_r), abs(_b[did] / _se[did]))
local ife_ll = _b[did] - invttail(e(df_r), .025) * _se[did]
local ife_ul = _b[did] + invttail(e(df_r), .025) * _se[did]
local ife_n = e(N)
local ife_g = e(N_clust)

preserve
clear
set obs 1
gen double Coef = `ife_b'
gen double CityCluster_SE = `ife_se'
gen double P = `ife_p'
gen double CI_L = `ife_ll'
gen double CI_U = `ife_ul'
gen long N = `ife_n'
gen int City_clusters = `ife_g'
export excel using "$outpath/individual_FE_citycluster.xlsx", firstrow(variables) replace
list, clean noobs
restore

* --------------------------------------------------------------------------
* C. Income missingness rates by wave and treatment status.
* --------------------------------------------------------------------------
gen byte eligible_urban = age >= 45 & rural == 0 if !missing(age, rural)
gen byte income_missing = missing(log_real_inc_per) if eligible_urban == 1

preserve
keep if eligible_urban == 1
collapse (count) Eligible_N=income_missing (sum) Income_Missing_N=income_missing, ///
    by(iwy treat)
gen double Income_Missing_Rate = Income_Missing_N / Eligible_N
sort iwy treat
export excel using "$outpath/income_missingness_by_wave_treatment.xlsx", ///
    firstrow(variables) replace
list, clean noobs
restore

* --------------------------------------------------------------------------
* D. Retained complete-case observations versus income-missing observations.
* --------------------------------------------------------------------------
gen byte selection_group = .
replace selection_group = 0 if baseline_sample == 1
replace selection_group = 1 if eligible_urban == 1 & income_missing == 1
label define selection_group 0 "Retained" 1 "Income missing", replace
label values selection_group selection_group

tempname selhold
tempfile selection_results
postfile `selhold' str28 Variable double Retained_Mean double Missing_Mean double Difference double SE double P ///
    long Retained_N long Missing_N using `selection_results', replace

foreach vv in rgoingl_clean gender age marry rwork rural2 edu hchild retire adlab_c smoken drinkl srh {
    quietly summarize `vv' if selection_group == 0
    local mean0 = r(mean)
    local n0 = r(N)
    quietly summarize `vv' if selection_group == 1
    local mean1 = r(mean)
    local n1 = r(N)
    quietly regress `vv' i.selection_group if inlist(selection_group,0,1), vce(cluster city_num)
    local diff = _b[1.selection_group]
    local se = _se[1.selection_group]
    local p = 2 * ttail(e(df_r), abs(`diff'/`se'))
    post `selhold' ("`vv'") (`mean0') (`mean1') (`diff') (`se') (`p') (`n0') (`n1')
}
postclose `selhold'
preserve
use `selection_results', clear
export excel using "$outpath/retained_vs_income_missing.xlsx", firstrow(variables) replace
list, clean noobs
restore

* City-resampled product indirect effects, 2,000 draws, seed 2025.
* Xiaoai: independently save all observed Stata paths on the exact common
* complete-case samples. The Python implementation must reproduce these.
tempname medreference
tempfile medstata
postfile `medreference' str12 Mediator double Path_A double Path_B double Total double Direct ///
    long N int Cities using `medstata', replace
local medvars GreenCoverageRateBD RoadSurAreaPerCap 工业二氧化硫排放量吨 hosper pm act_12
local medlabels Green Road SO2 Medical PM25 Social
forvalues j=1/6 {
    local med : word `j' of `medvars'
    local lab : word `j' of `medlabels'
    quietly reghdfe `med' did $ctrl if baseline_sample & !missing(`med'), absorb(city iwy) vce(cluster city)
    local path_a=_b[did]
    tempvar common_med
    gen byte `common_med'=e(sample)
    quietly reghdfe rgoingl_clean `med' did $ctrl if `common_med', absorb(city iwy) vce(cluster city)
    local path_b=_b[`med']
    local direct=_b[did]
    local med_n=e(N)
    local med_g=e(N_clust)
    assert e(sample)==`common_med'
    quietly reghdfe rgoingl_clean did $ctrl if `common_med', absorb(city iwy) vce(cluster city)
    assert e(N)==`med_n'
    assert abs(_b[did]-(`direct'+`path_a'*`path_b'))<1e-7
    post `medreference' ("`lab'") (`path_a') (`path_b') (_b[did]) (`direct') (`med_n') (`med_g')
    drop `common_med'
}
postclose `medreference'
preserve
use `medstata', clear
export delimited using "$outpath/mediation_observed_stata.csv", replace
restore
* Remove stale summaries before the helper; it must create fresh output.
capture erase "$outpath/city_bootstrap_indirect_FDR.csv"
capture erase "$outpath/city_bootstrap_indirect_FDR.xlsx"
capture erase "$outpath/city_bootstrap_indirect_FDR.dta"
shell "$python" "$code/mediation_cluster_bootstrap.py" "$analysisfile" "$outpath/city_bootstrap_indirect_FDR.csv" 2000 2025
confirm file "$outpath/city_bootstrap_indirect_FDR.csv"
import delimited using "$outpath/city_bootstrap_indirect_FDR.csv", varnames(1) encoding(UTF-8) asdouble clear
export excel using "$outpath/city_bootstrap_indirect_FDR.xlsx", firstrow(variables) replace
save "$outpath/city_bootstrap_indirect_FDR.dta", replace
list, clean noobs


* ==================== CITY PLACEBO 5000 ====================
version 18.0
clear
set more off
set rng mt64
set seed 2025
set sortseed 2025
* Xiaoai: 5,000 city assignments; accelerated statistics require independent
* Stata agreement on at least 20 draws, including high-leverage assignments.
use "$analysisfile", clear
drop if missing(ID) | missing(wave)
isid ID wave
foreach vv in cpi_index real_inc_per log_real_inc_per rgoingl_str rgoingl_clean {
    capture drop `vv'
}
gen double cpi_index = .
replace cpi_index = 1.000000 if iwy == 2011
replace cpi_index = 1.053702 if iwy == 2013
replace cpi_index = 1.091967 if iwy == 2015
replace cpi_index = 1.157663 if iwy == 2018
replace cpi_index = 1.217449 if iwy == 2020
gen double real_inc_per = (income_total/family_size)/cpi_index ///
    if income_total>0 & income_total<. & family_size>0 & family_size<. & cpi_index<.
gen double log_real_inc_per = log(real_inc_per) if real_inc_per>0 & real_inc_per<.
gen double rgoingl_clean = rgoingl
global ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire adlab_c smoken drinkl srh age
global sample age>=45 & age<. & rural==0
isid ID iwy
sort city ID iwy
quietly reghdfe rgoingl_clean did $ctrl if $sample, absorb(city iwy) vce(cluster city)
local actual_beta = _b[did]
local actual_se = _se[did]
local actual_p = 2*ttail(e(df_r),abs(_b[did]/_se[did]))
local df_model = e(df_m)
local df_absorbed = e(df_a)
keep if e(sample)
assert !missing(city) & !missing(did, treat, post)
egen long placebo_city_id = group(city)
egen byte city_tag = tag(placebo_city_id)
quietly count if city_tag
local total_cities = r(N)
quietly count if city_tag & treat==1
local n_treated = r(N)
assert `n_treated'>0 & `n_treated'<`total_cities'
bysort city: assert treat==treat[1]
assert did==treat*post
keep ID iwy city placebo_city_id city_tag rgoingl_clean did treat post rural $ctrl
save "$outpath/city_placebo_analysis_sample.dta", replace

* The RNG consumes exactly one number per canonical city per assignment.
* All random assignments are persisted, so statistics can be reproduced
* without depending on the input observation order or subsequent RNG state.
keep if city_tag
keep city placebo_city_id treat
isid placebo_city_id
save "$outpath/city_placebo_city_key.dta", replace
expand 5000
bysort placebo_city_id: gen int draw=_n
sort draw placebo_city_id
set seed 2025
gen double random_number=runiform()
bysort draw (random_number placebo_city_id): gen byte fake_treat=(_n<=`n_treated')
bysort draw: egen int treated_cities=total(fake_treat)
assert treated_cities==`n_treated'
keep draw placebo_city_id fake_treat
sort draw placebo_city_id
isid draw placebo_city_id
save "$outpath/city_placebo_assignments.dta", replace
export delimited using "$outpath/city_placebo_assignments.csv", replace

capture erase "$outpath/city_placebo_fast_candidate.csv"
capture erase "$outpath/city_placebo_fast_verified.ok"
shell "$python" "$code/city_placebo_fast.py" compute ///
    --sample "$outpath/city_placebo_analysis_sample.dta" ///
    --assignments "$outpath/city_placebo_assignments.csv" --output-dir "$outpath" ///
    --actual-beta `actual_beta' --actual-se `actual_se' --actual-p `actual_p' ///
    --df-model `df_model' --df-absorbed `df_absorbed'
local fast_ok=0
capture confirm file "$outpath/city_placebo_fast_candidate.csv"
if !_rc {
    import delimited using "$outpath/city_placebo_fast_candidate.csv", clear asdouble
    levelsof draw if verify_draw==1, local(check_draws)
    tempfile verification
    tempname verifyhold
    postfile `verifyhold' int draw double beta double se double t long N int G using `verification', replace
    foreach rr of local check_draws {
        use "$outpath/city_placebo_assignments.dta" if draw==`rr', clear
        keep placebo_city_id fake_treat
        tempfile one_assignment
        save `one_assignment', replace
        use "$outpath/city_placebo_analysis_sample.dta", clear
        merge m:1 placebo_city_id using `one_assignment', assert(match) nogen
        gen double fake_did=fake_treat*post
        quietly reghdfe rgoingl_clean fake_did $ctrl, absorb(city iwy) vce(cluster city)
        post `verifyhold' (`rr') (_b[fake_did]) (_se[fake_did]) ///
            (_b[fake_did]/_se[fake_did]) (e(N)) (e(N_clust))
    }
    postclose `verifyhold'
    use `verification', clear
    export delimited using "$outpath/city_placebo_stata_verification.csv", replace
    shell "$python" "$code/city_placebo_fast.py" verify --output-dir "$outpath"
    capture confirm file "$outpath/city_placebo_fast_verified.ok"
    if !_rc local fast_ok=1
}

if `fast_ok' {
    import delimited using "$outpath/city_placebo_fast_candidate.csv", clear asdouble
    display as result "Fast placebo passed independent Stata coefficient/SE/t validation."
}
else {
    display as text "Fast verification unavailable or failed; using all 5,000 Stata regressions."
    tempfile fallback_results
    tempname ph
    postfile `ph' int draw double beta double se double t int treated_cities byte valid_draw long N int G ///
        using `fallback_results', replace
    forvalues rr=1/5000 {
        use "$outpath/city_placebo_assignments.dta" if draw==`rr', clear
        keep placebo_city_id fake_treat
        tempfile one_assignment
        save `one_assignment', replace
        use "$outpath/city_placebo_analysis_sample.dta", clear
        merge m:1 placebo_city_id using `one_assignment', assert(match) nogen
        gen double fake_did=fake_treat*post
        capture quietly reghdfe rgoingl_clean fake_did $ctrl, absorb(city iwy) vce(cluster city)
        if !_rc {
            local valid=(_se[fake_did]>0 & _se[fake_did]<. & _b[fake_did]<.)
            post `ph' (`rr') (_b[fake_did]) (_se[fake_did]) ///
                (_b[fake_did]/_se[fake_did]) (`n_treated') (`valid') (e(N)) (e(N_clust))
        }
        else post `ph' (`rr') (.) (.) (.) (`n_treated') (0) (.) (.)
    }
    postclose `ph'
    use `fallback_results', clear
}
assert _N==5000
assert treated_cities==`n_treated'
assert valid_draw==!missing(beta,se,t) if valid_draw==1
quietly count if valid_draw==1 & !missing(beta,se,t) & se>0
local valid_reps=r(N)
local failed_reps=5000-`valid_reps'
* Failed regressions must never be counted as extreme. The full requested
* 5,000 must be valid before the primary placebo p value is released.
if `failed_reps'>0 {
    export delimited using "$outpath/city_placebo_failed_draw_diagnostics.csv", replace
    display as error "Invalid placebo draws: `failed_reps'. Inspect diagnostic output; no p value released."
    exit 459
}
gen double actual_beta=`actual_beta'
gen double actual_se=`actual_se'
gen double actual_p=`actual_p'
gen double actual_t=`actual_beta'/`actual_se'
gen byte as_or_more_extreme=abs(beta)>=abs(actual_beta) if valid_draw==1
quietly count if as_or_more_extreme==1
local extreme=r(N)
gen double empirical_p=(`extreme'+1)/(`valid_reps'+1)
gen byte t_as_or_more_extreme=abs(t)>=abs(actual_t) if valid_draw==1
quietly count if t_as_or_more_extreme==1
local t_extreme=r(N)
gen double t_empirical_p=(`t_extreme'+1)/(`valid_reps'+1)
gen int reps=5000
gen int valid_reps=`valid_reps'
gen int failed_reps=`failed_reps'
gen int seed=2025
gen int total_cities=`total_cities'
gen int assigned_treated_cities=`n_treated'
gen byte verified_acceleration=`fast_ok'
save "$outpath/city_level_placebo_5000.dta", replace
export delimited using "$outpath/city_level_placebo_5000.csv", replace
export excel using "$outpath/city_level_placebo_5000.xlsx", firstrow(variables) replace
local empirical_p=empirical_p[1]
local t_empirical_p=t_empirical_p[1]
twoway (kdensity beta, lcolor(navy) lwidth(medthick)), ///
    xline(`actual_beta', lcolor(cranberry) lpattern(dash) lwidth(medthick)) ///
    xline(0, lcolor(gs8) lpattern(shortdash)) ///
    xtitle("Placebo DID coefficient") ytitle("Density") ///
    title("City-level placebo assignment test") ///
    subtitle("5,000 valid draws; `n_treated' placebo-treated cities per draw") ///
    note("Actual DID = `actual_beta'; coefficient placebo p = `empirical_p'.") ///
    legend(off) graphregion(color(white))
graph export "$outpath/city_level_placebo_5000.png", replace width(2800)
display "ACTUAL_BETA=" %12.8f `actual_beta'
display "ACTUAL_SE=" %12.8f `actual_se'
display "ACTUAL_P=" %12.8f `actual_p'
display "EXTREME_DRAWS=" `extreme'
display "EMPIRICAL_P=" %12.8f `empirical_p'
display "T_EXTREME_DRAWS=" `t_extreme'
display "T_EMPIRICAL_P=" %12.8f `t_empirical_p'
display "VALID_REPS=" `valid_reps' " FAILED_REPS=" `failed_reps'


* ==================== PREPOLICY TIMING PLACEBO ====================
version 18.0
clear
set more off

use "$analysisfile", clear
drop if missing(ID) | missing(wave)
isid ID wave

foreach vv in cpi_index real_inc_per log_real_inc_per rgoingl_str rgoingl_clean {
    capture drop `vv'
}
gen double cpi_index = .
replace cpi_index = 1.000000 if iwy == 2011
replace cpi_index = 1.053702 if iwy == 2013
replace cpi_index = 1.091967 if iwy == 2015
replace cpi_index = 1.157663 if iwy == 2018
replace cpi_index = 1.217449 if iwy == 2020
gen double real_inc_per = (income_total / family_size) / cpi_index ///
    if income_total > 0 & income_total < . & family_size > 0 & family_size < . & !missing(cpi_index)
gen double log_real_inc_per = log(real_inc_per) if real_inc_per > 0 & real_inc_per < .
gen double rgoingl_clean = rgoingl

global ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire ///
    adlab_c smoken drinkl srh age
global sample age >= 45 & age < . & rural == 0
* Use pre-policy waves only, so true post-policy effects cannot contaminate tests.
keep if inlist(iwy, 2011, 2013, 2015)

generate byte fake_post_2013 = iwy >= 2013
generate byte fake_post_2015 = iwy >= 2015
generate double fake_did_2013 = treat * fake_post_2013
generate double fake_did_2015 = treat * fake_post_2015

tempname timinghold
tempfile timing_results
postfile `timinghold' str40 Placebo_timing double Coefficient double SE double P double CI_L double CI_U ///
    long N int City_clusters int Treated_cities using `timing_results', replace

foreach yy in 2013 2015 {
    reghdfe rgoingl_clean fake_did_`yy' $ctrl if $sample, ///
        absorb(city iwy) vce(cluster city)
    local b = _b[fake_did_`yy']
    local se = _se[fake_did_`yy']
    local p = 2 * ttail(e(df_r), abs(`b' / `se'))
    local ll = `b' - invttail(e(df_r), .025) * `se'
    local ul = `b' + invttail(e(df_r), .025) * `se'
    local n = e(N)
    local g = e(N_clust)
    preserve
        keep if e(sample)
        egen byte city_tag = tag(city)
        quietly count if city_tag & treat == 1
        local treated_g = r(N)
    restore
    post `timinghold' ("`yy' first placebo-post wave") ///
        (`b') (`se') (`p') (`ll') (`ul') (`n') (`g') (`treated_g')
}
postclose `timinghold'

use `timing_results', clear
format Coefficient SE CI_L CI_U %10.5f
format P %10.6f
export excel using "$outpath/placebo_policy_timing_results.xlsx", ///
    firstrow(variables) replace
export delimited using "$outpath/placebo_policy_timing_results.csv", replace
list, noobs abbreviate(32)


* ==================== CENTERED COVID ONLY ====================
version 18.0
clear
set more off

use "$analysisfile", clear
drop if missing(ID) | missing(wave)
isid ID wave

foreach vv in cpi_index real_inc_per log_real_inc_per rgoingl_str rgoingl_clean {
    capture drop `vv'
}
gen double cpi_index = .
replace cpi_index = 1.000000 if iwy == 2011
replace cpi_index = 1.053702 if iwy == 2013
replace cpi_index = 1.091967 if iwy == 2015
replace cpi_index = 1.157663 if iwy == 2018
replace cpi_index = 1.217449 if iwy == 2020
gen double real_inc_per = (income_total / family_size) / cpi_index ///
    if income_total > 0 & income_total < . & family_size > 0 & family_size < . & !missing(cpi_index)
gen double log_real_inc_per = log(real_inc_per) if real_inc_per > 0 & real_inc_per < .
gen double rgoingl_clean = rgoingl

global ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire ///
    adlab_c smoken drinkl srh age
global sample age >= 45 & age < . & rural == 0
replace covidnumber = 0 if iwy != 2020
* Xiaoai: missing 2020 city case intensity remains missing.
assert iwy <= 2020 & !missing(iwy)
quietly reghdfe rgoingl_clean did $ctrl if $sample, absorb(city iwy) vce(cluster city)
gen byte baseline_sample=e(sample)
quietly count if baseline_sample
local baseline_n=r(N)
quietly count if baseline_sample & iwy==2020 & missing(covidnumber)
local unknown_covid_n=r(N)
preserve
    keep if baseline_sample & iwy==2020 & missing(covidnumber)
    keep city ID iwy treat
    export delimited using "$outpath/covid_unknown_case_observations.csv", replace
restore

* Freeze the exact complete-case interaction-model sample.
gen double did_covidnumber = did * covidnumber
quietly reghdfe rgoingl_clean did covidnumber did_covidnumber $ctrl if $sample, ///
    absorb(city iwy) vce(cluster city)
gen byte analysis_sample = e(sample)
local interaction_n=e(N)
local interaction_g=e(N_clust)
local uncentered_did=_b[did]
local uncentered_interaction=_b[did_covidnumber]
assert !missing(covidnumber) if analysis_sample
bysort city iwy: assert covidnumber==covidnumber[1] if analysis_sample

* City-level rather than person-weighted distribution in 2020.
egen byte city2020_tag = tag(city) if iwy == 2020 & analysis_sample
quietly summarize covidnumber if city2020_tag & treat == 1, detail
local tr_p25 = r(p25)
local tr_p50 = r(p50)
local tr_mean = r(mean)
local tr_p75 = r(p75)
local n_tr_city = r(N)
assert `n_tr_city'>0

quietly summarize covidnumber if city2020_tag, detail
local all_p25 = r(p25)
local all_p50 = r(p50)
local all_mean = r(mean)
local all_p75 = r(p75)
local n_all_city = r(N)

* Xiaoai: retain the uncentered linear combination to verify centering.
quietly lincom did + `tr_mean' * did_covidnumber
local reference_centered_did=r(estimate)
local reference_centered_se=r(se)

* Center at the unique treated-city mean. This is an algebraic reparameterization.
gen double covid_centered = covidnumber - `tr_mean'
gen double did_covid_centered = did * covid_centered
reghdfe rgoingl_clean did covid_centered did_covid_centered $ctrl ///
    if analysis_sample, absorb(city iwy) vce(cluster city)
assert e(sample)==analysis_sample
assert abs(_b[did]-`reference_centered_did')<1e-8
assert abs(_se[did]-`reference_centered_se')<1e-8
assert abs(_b[did_covid_centered]-`uncentered_interaction')<1e-8

quietly lincom covid_centered
local covid_slope_control = r(estimate)
local covid_slope_control_se = r(se)
local covid_slope_control_p = r(p)
local covid_slope_control_lb = r(lb)
local covid_slope_control_ub = r(ub)
quietly lincom covid_centered + did_covid_centered
local covid_slope_treated = r(estimate)
local covid_slope_treated_se = r(se)
local covid_slope_treated_p = r(p)
local covid_slope_treated_lb = r(lb)
local covid_slope_treated_ub = r(ub)

tempname results
tempfile margins
postfile `results' str20 Distribution str12 Level double COVID_000 ///
    double Estimate double SE double P double CI_L double CI_U using `margins', replace

foreach ll in p25 p50 mean p75 {
    local x = `tr_`ll''
    local xc = `x' - `tr_mean'
    quietly lincom did + `xc' * did_covid_centered
    post `results' ("Treated cities") ("`ll'") (`x') ///
        (r(estimate)) (r(se)) (r(p)) (r(lb)) (r(ub))
}

foreach ll in p25 p50 mean p75 {
    local x = `all_`ll''
    local xc = `x' - `tr_mean'
    quietly lincom did + `xc' * did_covid_centered
    post `results' ("All cities") ("`ll'") (`x') ///
        (r(estimate)) (r(se)) (r(p)) (r(lb)) (r(ub))
}
postclose `results'

* Xiaoai: retain model coefficients and sample accounting alongside margins.
local centered_did=_b[did]
local centered_did_se=_se[did]
local centered_case=_b[covid_centered]
local centered_case_se=_se[covid_centered]
local interaction_b=_b[did_covid_centered]
local interaction_se=_se[did_covid_centered]
local did_col=colnumb(e(V),"did")
local interaction_col=colnumb(e(V),"did_covid_centered")
local did_interaction_cov=el(e(V),`did_col',`interaction_col')
preserve
    clear
    set obs 1
    gen long Baseline_N=`baseline_n'
    gen long Interaction_N=`interaction_n'
    gen int Interaction_Cities=`interaction_g'
    gen long Unknown_2020_COVID_N=`unknown_covid_n'
    gen int Treated_2020_Cities=`n_tr_city'
    gen int All_2020_Cities=`n_all_city'
    gen double Treated_City_Mean=`tr_mean'
    gen double Centered_DID=`centered_did'
    gen double Centered_DID_SE=`centered_did_se'
    gen double COVID_Centered=`centered_case'
    gen double COVID_Centered_SE=`centered_case_se'
    gen double Interaction=`interaction_b'
    gen double Interaction_SE=`interaction_se'
    gen double DID_Interaction_Cov=`did_interaction_cov'
    gen double Uncentered_DID=`uncentered_did'
    gen double Uncentered_Mean_Effect=`reference_centered_did'
    gen double Uncentered_Mean_SE=`reference_centered_se'
    export delimited using "$outpath/covid_centered_model_summary.csv", replace
    export excel using "$outpath/covid_centered_model_summary.xlsx", firstrow(variables) replace
restore

* Changes in the conditional HCPP effect across treated-city quartiles.
quietly lincom (`tr_p50' - `tr_p25') * did_covid_centered
local d25_50 = r(estimate)
local d25_50_se = r(se)
local d25_50_p = r(p)
quietly lincom (`tr_p75' - `tr_p50') * did_covid_centered
local d50_75 = r(estimate)
local d50_75_se = r(se)
local d50_75_p = r(p)

display "TREATED_CITY_N=" `n_tr_city'
display "ALL_CITY_N=" `n_all_city'
display "TREATED_P25=" %12.6f `tr_p25'
display "TREATED_P50=" %12.6f `tr_p50'
display "TREATED_MEAN=" %12.6f `tr_mean'
display "TREATED_P75=" %12.6f `tr_p75'
display "INTERACTION_SLOPE=" %12.6f _b[did_covid_centered]
display "INTERACTION_SE=" %12.6f _se[did_covid_centered]
display "COVID_SLOPE_CONTROL=" %12.6f `covid_slope_control' " SE=" %12.6f `covid_slope_control_se' " P=" %12.6f `covid_slope_control_p' " CI=[" %12.6f `covid_slope_control_lb' "," %12.6f `covid_slope_control_ub' "]"
display "COVID_SLOPE_TREATED=" %12.6f `covid_slope_treated' " SE=" %12.6f `covid_slope_treated_se' " P=" %12.6f `covid_slope_treated_p' " CI=[" %12.6f `covid_slope_treated_lb' "," %12.6f `covid_slope_treated_ub' "]"
display "DELTA_P25_P50=" %12.6f `d25_50' " SE=" %12.6f `d25_50_se' " P=" %12.6f `d25_50_p'
display "DELTA_P50_P75=" %12.6f `d50_75' " SE=" %12.6f `d50_75_se' " P=" %12.6f `d50_75_p'

preserve
    use `margins', clear
    gen long N=`interaction_n'
    gen int City_clusters=`interaction_g'
    gen long Baseline_N=`baseline_n'
    gen long Unknown_2020_COVID_N=`unknown_covid_n'
    format COVID_000 Estimate SE P CI_L CI_U %12.6f
    export excel using "$outpath/covid_centered_marginal_effects.xlsx", ///
        firstrow(variables) replace
    export delimited using "$outpath/covid_centered_marginal_effects.csv", replace
    list, clean noobs
restore


* ==================== WILD CLUSTER 9999 WEBB ====================
version 18.0
clear
set more off
set rng mt64
set seed 2025
set sortseed 2025

capture which reghdfe
if _rc {
    di as error "Required command reghdfe is not installed."
    exit 199
}
use "$analysisfile", clear
drop if missing(ID) | missing(wave)
isid ID wave

foreach vv in cpi_index real_inc_per log_real_inc_per rgoingl_str rgoingl_clean {
    capture drop `vv'
}
gen double cpi_index = .
replace cpi_index = 1.000000 if iwy == 2011
replace cpi_index = 1.053702 if iwy == 2013
replace cpi_index = 1.091967 if iwy == 2015
replace cpi_index = 1.157663 if iwy == 2018
replace cpi_index = 1.217449 if iwy == 2020
gen double real_inc_per = (income_total / family_size) / cpi_index ///
    if income_total > 0 & income_total < . & family_size > 0 & family_size < . & !missing(cpi_index)
gen double log_real_inc_per = log(real_inc_per) if real_inc_per > 0 & real_inc_per < .
gen double rgoingl_clean = rgoingl

global ctrl gender marry log_real_inc_per rwork rural2 edu hchild retire ///
    adlab_c smoken drinkl srh age
global sample age >= 45 & age < . & rural == 0
encode city, gen(city_id_wb)

reghdfe rgoingl_clean did $ctrl if $sample, ///
    absorb(city iwy) vce(cluster city)

local beta = _b[did]
local city_se = _se[did]
local city_p = 2 * ttail(e(df_r), abs(_b[did] / _se[did]))
local n = e(N)
local clusters = e(N_clust)
gen byte frozen_wild_sample=e(sample)

* areg with year indicators is algebraically equivalent to city and year FE.
areg rgoingl_clean did $ctrl i.iwy if frozen_wild_sample, ///
    absorb(city_id_wb) vce(cluster city_id_wb)
assert e(sample)==frozen_wild_sample
assert e(N)==`n'
assert e(N_clust)==`clusters'
assert abs(_b[did]-`beta')<1e-8

* Load a current, Stata-18-compatible boottest build from the project folder.
* The system installation is an obsolete read-only 2018 build.
sysdir set PLUS "$package_root/vendor/stata_plus_wildboot/"
run "$package_root/vendor/boottest_v4_4_8/boottest.mata"
do "$package_root/vendor/boottest_v4_4_8/boottest.ado"

* Restricted wild cluster bootstrap (null imposed by default).
boottest did, cluster(city_id_wb) bootcluster(city_id_wb) reps(9999) ///
    seed(2025) weight(webb) nograph
local webb_p = r(p)
assert `webb_p'>=0 & `webb_p'<=1

* Sensitivity to conventional Rademacher weights.
boottest did, cluster(city_id_wb) bootcluster(city_id_wb) reps(9999) ///
    seed(2025) weight(rademacher) nograph
local rademacher_p = r(p)
assert `rademacher_p'>=0 & `rademacher_p'<=1

egen byte city_tag = tag(city) if e(sample)
quietly count if city_tag
local total_cities = r(N)
quietly count if city_tag & treat == 1
local treated_cities = r(N)
assert `treated_cities'>0 & `treated_cities'<`total_cities'
assert `total_cities'==`clusters'
local control_cities = `total_cities' - `treated_cities'

clear
set obs 1
gen double DID_Estimate = `beta'
gen double CityCluster_SE = `city_se'
gen double Conventional_P = `city_p'
gen double Wild_Webb_P = `webb_p'
gen double Wild_Rademacher_P = `rademacher_p'
gen long Observations = `n'
gen int Total_Cities = `total_cities'
gen int Treated_Cities = `treated_cities'
gen int Control_Cities = `control_cities'
gen int Bootstrap_Reps = 9999
gen int Seed = 2025

export excel using "$outpath/main_did_wild_cluster_results.xlsx", ///
    firstrow(variables) replace
export delimited using "$outpath/main_did_wild_cluster_results.csv", replace

list, clean noobs

display as result "HCPP_RAW_0507_ALL_FINAL_MODELS_COMPLETED"
log close
