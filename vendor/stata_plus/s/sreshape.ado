* sreshape program by Kenneth L. Simons, 2015.
* Subcommands of reshape other than reshape long and reshape wide are used to handle advanced-format settings, clear, query, and error.
* If sreshape long or sreshape wide exits with an error, it would ideally display the same picture and explanation as reshape displays, but I have not put these in since they are copyrighted.  See sreshape_long section 2D2, and sreshape_wide section 2G3.

program define sreshape
	version 13
	* The following provides StataCorp an option to turn off sreshape, requesting users to use reshape instead, in case of future changes in Stata that make this outmoded.
	*   To do so, "reshape isSreshapeOff" must return r(sreshapeOff)="1" when run under version 13.
	capture reshape isSreshapeOff
	if (_rc==0 & "`=r(sreshapeOff)'"=="1") {
		di as error "A newer version of reshape has superseded sreshape.  Please use reshape instead."
		exit 999
	}
	else if (_rc==1) error 1
	* Ensure version is okay.
	if c(stata_version)<13.0 giveErrorWithErrnum 198 "sreshape requires Stata 13 or newer"  // Small problems seem to work okay in Stata 12, but memory usage is excessively high for some reason, and this could cause a problem.  sreshape works with Stata 13 and 14.
	if _caller() <= 10 giveErrorWithErrnum 198 "sreshape requires Stata 11 or newer"  // This emulates reshape, and keeps the reshape options from being called when reshape will not function.
	local cver : char _dta[ReS_ver]
	if !inlist("`cver'","v.2","") giveErrorWithErrnum 198 "sreshape is programmed to work with the reshape (v.2) command active as of Stata 11 through 13, but another version of reshape is in use.  Check for an update of sreshape, or use both reshape and sreshape under version control."
	* Only sreshape long requires different treatment from Stata's reshape; other sreshape subcommands simply use the equivalent built-in Stata commands.
	gettoken first 0 : 0 , parse(" ,")
	if (`"`first'"'=="long") runAndEndStoreVarsIfBreak sreshape_long `0'
	else if (`"`first'"'=="wide") runAndEndStoreVarsIfBreak sreshape_wide `0'  //reshape wide `0'
	else if (`"`first'"'=="error") reshape error `0'
	else if (`"`first'"'=="i") reshape i `0'
	else if (`"`first'"'=="j") reshape j `0'
	else if (`"`first'"'=="xij") reshape xij `0'
	else if (`"`first'"'=="xi") giveErrorWithErrnum 198 "Use of sreshape xi is disallowed, and use of reshape xi is denigrated.  Instead, please explicitly drop Xi variables you do not wish to keep." //reshape xi `0'
	else if (substr("query",1,length(`"`first'"'))==`"`first'"') reshape query  // The query argument may be abbreviated, or no argument may be given.
	else if (`"`first'"'=="clear") reshape clear
	else error 198
end

* Sparse reshape to long form.
program define sreshape_long, rclass
	version 13
	* 1. Get some initial data.
	* 1A. Get reshaping requirements previously stored as characteristics, into the local variables ci, cj, etc.
	local ci : char _dta[ReS_i]  // i variable names
	local cj : char _dta[ReS_j]  // j variable name
	local cjv : char _dta[ReS_jv]  // j values, if specified.  This may consist of integers, or of nonnumeric ends of variable names if string has been specified.
	local cXij : char _dta[ReS_Xij]  // Xij variable names
	local cXiWas : char _dta[Res_Xi]  // Xi variable names, if specified.  Note the lowercase s in this characteristic; this is how Stata keeps this.
	local cXi = ""  // Carrying over the setting of cXi is too dangerous, and is disallowed.
	local catwl : char _dta[ReS_atwl]  // atwl() value, if specified
	local cstr : char _dta[ReS_str]  // 1 if option string specified; 0 otherwise
	local initXiLen : length local cXi
	* 1B. Get initial numbers of observations and variables.
	local initk = c(k)
	local initN = _N
	local haveSomeObs = _N>0
	* 2. Check the syntax, preserve, and read in arguments.  Where arguments should replace values stored in characteristics, they will be put in the local variables ci, cj, etc.
	* I have not verified whether the j-values are dropped or used by Stata's reshape if "reshape long" is called with the same j but without values.  I drop.
	* I have not verified whether Stata uses the saved j name, versus makes _j, if a new i is specified and j is not specified.  I use the saved j name if any, otherwise use _j.
	gettoken stubnamelist 0: 0, parse(",")  // Do not just use [anything] in the syntax command to get the stubnamelist, because "in@" would confuse the syntax command.
	syntax , [i(varlist) NEWI(string) j(string) String atwl(string) keeponlyxi(string) Widevars(string) MIssing(string) noRECastasdouble NOCOMpress NOPRESERVE Favorspace(integer 0)]
	local needtopreserve = "`nopreserve'"==""
	local preserved = 0
	local ilen : length local i
	local newilen : length local newi
	local jlen : length local j
	local jvlen = 0  // Assume no j-values were given until we find out otherwise.
	local stubnamelistlen : length local stubnamelist
	local widevarslen: length local widevars
	if `widevarslen' {
		if !inlist(`"`widevars'"',"all","nonmissing") giveError 198 `"The widevars option must be "all" (the default) or "nonmissing".  This is not used for reshape long anyway."'
	}
	else local widevars = "all"
	local missing = trim(itrim(`"`missing'"'))
	local drop = inlist(`"`missing'"', "drop", "drop all")  // drop = 1 if missing is drop OR drop all, 0 if missing is keep.
	local dropall = `"`missing'"'=="drop all"  // If dropall = 1, then also drop = 1.
	if ( (!`drop') & (!inlist(`"`missing'"', "keep", "")) ) giveError 198 `"The missing option must be "keep" (the default), "drop", or "drop all"."'
	if (`favorspace'<0) | (`favorspace'>4) giveError 198 "The favorspace option must be 0, 1, 2, 3, or 4 (higher numbers may reduce memory usage, if so at the cost of slower processing unless there is insufficient memory)."
	local atwllen : length local atwl
	local keeponlyxilen : length local keeponlyxi
	local newReshapeInfo = (`ilen' | `newilen' | `jlen' | `stubnamelistlen' | `atwllen' | `keeponlyxilen')
	if `newReshapeInfo' {
		* Since new i, j, or Xij info has been given here, clear old values for i, j, jv, Xij, and str.  Retain Xi.
		local ci = ""
		local cj = ""
		local cjv = ""
		local cXij = ""
		local cstr = 0
		//local catwl = ""   // To maintain compatability with Stata's reshape approach, which takes atwl info from prior advanced reshapes, the value of atwl is NOT replaced with null if not specified.  It may be replaced with null by specifying option atwl(.)
		local cXi = ""   // To maintain compatability with Stata's reshape approach, which takes Xi info from prior advanced reshapes, the value of Xi ought not to be replaced with null if not specified.  It may be replaced with null by specifying undocumented option keeponlyxi(.)  However, this advanced-option usage of reshape is dangerous, particularly if prior settings are carried over to future usage.  Therefore prior setting are NOT carried over in sreshape.
	}
	if `atwllen' {
		if (`"`atwl'"'==".") local catwl = ""
		else local catwl = `"`atwl'"'
	}
	if `keeponlyxilen' {
		if (`"`keeponlyxi'"'==".") local cXi = ""
		else {
			//capture confirm variable `keeponlyxi'
			unab cXi : `keeponlyxi'
		}
	}
	else {
		local cXiWasLen : length local cXiWas
		if `cXiWasLen' giveError 198 "sreshape does not support reshape's advanced-format Xi setting, because of danger of unintentionally dropping data.  Please drop undesired Xi variables explicitly."
	}
	* 2A. Get the i varlist (or make a new i variable if requested using the newi() option).
	*       When checking that it uniquely identifies each observation, if there is an error, flag the error and wait until later to give the error, because the right information needs to be built up to load into data characteristics that allow use of "reshape error".
	if ("`i'"!="") {
		local ci `i'
		if (`newilen') giveError 198 "Use only one of i(varlist) or newi(newvarname) options."
		* Confirm that the i variable list identifies each observation uniquely.
		iVarsValid_WideToLong `i'
		local iuniqerror = r(iuniqerror)  // If this returns non-null, the error message with code 459 must be issued after figuring out and setting all data characteristics.  This is done below if necessary.
	}
	else if `newilen' {
		capture confirm new variable `newi'
		if (_rc>1) giveError `=_rc' "The newi() option must specify a valid new variable, but does not."
		else if (_rc==1) error 1
		if `needtopreserve' {
			preserve  // Preserve before creating new variable.
			local needtopreserve = 0
			local preserved = 1
		}
		local ivarnameType = cond(_N<=100, "byte", cond(_N<=32740, "int", cond(_N<=2147483620, "long", "double")))
		gen `ivarnameType' i = _n
		local ci = "`newi'"
		// Note, the only case in which sreshape long exits due to an error and the user should be able to use "reshape error" afterwards is when the i variables do not uniquely identify the observations, but this will never happen if the i variable is created.
	}
	else if `newReshapeInfo' {  // If a new j or Xij is specified then i must be specified at the same time, or if i has not been declared from previous use of reshape then i must be declared.
		giveError 198 "option i() required"
	}
	else {
		iVarsValid_WideToLong `ci'  // Confirm that the previously set i variable list identifies each observation uniquely.
		local iuniqerror = r(iuniqerror)  // If this returns non-null, the error message with code 459 must be issued after figuring out and setting all data characteristics.  This is done below if necessary.
	}
	* 2B. Get the Xij varnames.
	if (`stubnamelistlen') local cXij `"`stubnamelist'"'
	else if (`newReshapeInfo') giveError 198 "invalid syntax: specify the Xij variable names."
	else {
		local cxijlen : length local cXij
		if (!`cxijlen') giveError 198 "specify the Xij variable names."
	}
	local cXijSubstituted : subinstr local cXij "@" `"`catwl'"', all count(local nSubs)  // Unicode-compatible in Stata 14.
	if (`nSubs'>1) {  // Check that there are never 2 or more @ symbols in one variable name.
		foreach Xijvar of local cXij {
			local Xijvar : subinstr local Xijvar "@" "", all count(local nSubs)
			if (`nSubs'>1) giveError 198 "variable names may not be specified with more than one @ symbol."
		}
	}
	* 2C. Get the j varname, and its values and string option if needed.
	if ("`string'"=="string") local cstr = 1  // This must be done BEFORE processing j.
	else if (`newReshapeInfo') local cstr = 0  // If the characteristics of the reshape are being reset, assume not string unless string is specified, regardless whether string was used in previous reshape settings or in advanced settings.
	if (`jlen') {
		gettoken j jv : j
		capture confirm new variable `j'
		if _rc {  // _rc==110 occurs if the variable already exists.  _rc==0 occurs if the variable name is valid and represents a new variable. 
			if _rc==110 {
				di as error "variable `j' already exists"
				di as error "    Data may already be long."
				exit 110
			}
			else if (_rc==1) error 1
			else giveError 198 "invalid j variable name"
		}
		local cj `j'
		local jvlen : length local jv
		if (`jvlen') {  // Parse j-values to get a string of space-separated integers.  While I at first wrote my own extraction code here, it avoids duplication to use Stata's code.  Stata does not check string j-values for seeming validity, an advantage in my version (see file "sreshape bak11Apr2015.ado").
			reshape j `j' `jv', `string'
			local cjv : char _dta[ReS_jv]
		}
	}
	else {
		* No j variable was declared.
		if ("`cj'"=="" | `newReshapeInfo') local cj = "_j"
		capture confirm new variable `cj'
		if _rc {  // _rc==110 occurs if the variable already exists.  _rc==0 occurs if the variable name is valid and represents a new variable. 
			if _rc==110 {
				di as error "variable `j' already exists"
				di as error "    Data may already be long."
				exit 110
			}
			else if (_rc==1) error 1
			else giveError 198 "invalid j variable name"
		}
	}
	if "`cjv'"=="" {
		* No j values were given.  Compute them from variable names.
		local cjv = ""
		foreach Xijvar of local cXij {
			local Xijvar_Poss : subinstr local Xijvar "@" "*", count(local nSubs)  // Unicode-compatible in Stata 14.
			if (`nSubs'==0) local Xijvar_Poss = "`Xijvar'*"
			quietly ds `Xijvar_Poss'
			local vars `"`r(varlist)'"'
			local stataver = c(stata_version)
			if (`cstr') {
				if (`stataver'>=14) local regex : subinstr local Xijvar_Poss "*" "([\S]+)"  // In a regex, \S indicates any non-whitespace character.  This allows any characters allowed in variable names, including unicode characters.
				else local regex : subinstr local Xijvar_Poss "*" "([a-zA-Z0-9_]+)"
			}
			else local regex : subinstr local Xijvar_Poss "*" "([0-9]+)"
			foreach v of local vars {
				if (c(stata_version)<14.0) {
					local regexmres = regexm("`v'","^`regex'$")
					if (`regexmres') {
						local thisjv = regexs(1)
						local alreadyfound : list thisjv in cjv
						if (!`alreadyfound') local cjv `cjv' `thisjv'
					}
				}
				else {
					local regexmres = ustrregexm("`v'",`"^`regex'$"')  // In Stata 14+, ustrregexm allows Unicode letters in variable names.
					if (`regexmres') {
						local thisjv = ustrregexs(1)
						local alreadyfound : list thisjv in cjv
						if (!`alreadyfound') local cjv `cjv' `thisjv'
					}
				}
			}
		}
		* Sort the j values.
		if (`cstr') local cjv : list sort cjv
		else {
			numlist "`cjv'", sort
			local cjv = r(numlist)
		}
	}
	else {
		* j values are available.
		local zzjunk : subinstr local cjv `"""' "", count(local quoteFound)  // Unicode-compatible in Stata 14.
		if `quoteFound' giveError "j values contain a quote, which is not allowed"
	}
	di as text `"(note: j = `cjv')"'  // It is still possible that the j values list `cjv' has illegal characters for variable names.  If so, this will be discovered while reshaping.
	* 2D. If there was an error flagged that the i variables do not uniquely identify the observations, then load the characteristics into the data now and give the error message with code 459.
	*       Note, if this happens, the data have not yet been preserved, because they only get preserved earlier than this if a new i variable is generated, and that variable always uniquely identifies the observations.
	if ("`iuniqerror'"==".") local iuniqerror = ""  // A period gets returned instead of null when there is no i uniqueness error, so doing this keeps the code robust to either null or period.
	local iuniqerrorlen : length local iuniqerror
	if `iuniqerrorlen' {
		* 2D1. Save the characteristics and return results.  The code here is redundant with code at the end of program sreshape_long, but it is best to just write it again here to keep the program simple.
		//if (`newReshapeInfo' & `initXiLen') char _dta[Res_Xi]  // Overwrite previous Xi variables list with null.  Note the lowercase s in this characteristic; this is how Stata keeps this.
		char _dta[Res_Xi]
		char _dta[ReS_Xij] `cXij'
		if (`jvlen') char _dta[ReS_jv] `cjv'
		char _dta[ReS_str] `cstr'
		char _dta[ReS_j] `cj'
		char _dta[ReS_ver] v.2
		char _dta[ReS_i] `ci'
		char _dta[ReS_atwl] `catwl'
		return scalar N = _N
		return scalar k = c(k)
		return scalar width = c(width)
		return scalar changed = 0  // This differs from the redundant code at the end of this program.
		* 2D2. Give the error message and exit.  Do not use the giveError subprogram, because it would clear returned results.
		di as error `"`iuniqerror'"'
		// HERE, THE SAME WIDE-TO-LONG PICTURE AND TEXT USED BY RESHAPE SHOULD IDEALLY BE DISPLAYED.  I do not display it since it is copyrighted by StataCorp.
		di as error "Type reshape error (or sreshape error) for a list of the problem observations."
		exit 459
	}
	* 2E. Preserve, if not yet done.
	if `needtopreserve' {
		preserve
		local needtopreserve = 0
		local preserved = 1
	}
	* 3. Determine the Xij wide variable names, and store them in two different ways: by Xij var., and by j-value.  Use periods for Xij-jval combinations for which there is no variable.
	*      These are stored in local variables xijvars_byx_# and xijvars_byj_#.  The term "byx" is an abbreviation meaning "by Xijvar", and the term "byj" is an abbreviation meaning "by j-value".
	*      Counter x points to the x-th Xij var., and counter j points to the j-th j-value.
	local x = 0
	foreach Xijvar of local cXij {
		local ++x
		local j = 0
		foreach jval of local cjv {
			local ++j
			* Get from variable name, and check whether the variable actually exists.
			local Xijvar_fromVarname : subinstr local Xijvar "@" `"`jval'"', count(local nSubs)  // Unicode-compatible in Stata 14.
			if (`nSubs'==0) local Xijvar_fromVarname `Xijvar'`jval'
			capture confirm variable `Xijvar_fromVarname', exact
			if (_rc>1) {
				di as text "(note: `Xijvar_fromVarname' not found)"
				local Xijvar_fromVarname = "."  // The period means this x-j combination does not have a wide variable.
			}
			else if (_rc==1) error 1
			* Store the variable name, or . if the x-j combination does not have a wide variable.
			local xijvars_byx_`x' `xijvars_byx_`x'' `Xijvar_fromVarname'
			local xijvars_byj_`j' `xijvars_byj_`j'' `Xijvar_fromVarname'
		}
	}
	local maxJvalnum = `j'
	local maxXijvarnum = `x'
	* 4. If requested, drop Xi variables not specified in an Xi list.
	local cXi_len : length local cXi
	if `cXi_len' {
		local cXijWideVars = ""
		forvalues x = 1/`maxXijvarnum' {
			local cXijWideVars `cXijWideVars' `xijvars_byx_`x''
		}
		local cXijWideVars : subinstr local cXijWideVars "." "", all word  // Remove periods, which denoted the lack of a variable, from the Xij wide variables list.  Unicode-compatible in Stata 14.
		keep `ci' `cXi' `cXijWideVars'
	}
	* 5. Determine the datatype needed for each Xij variable.  Also, determine any number format, value labels, and variable labels that apply.
	forvalues x = 1/`maxXijvarnum' {
		local xijformat = "!"
		local xijvallabel = "!"
		local xijvarlabel = "!"
		local xijtype = "!"  // "!" means no variables have been assessed yet.
		local xijCheckedForLargeLongs = 0
		foreach varname of local xijvars_byx_`x' {
			if ("`varname'"==".") continue  // Ignore nonexistent variables.
			* Get and process format.
			local thisformat : format `varname'
			if ("`xijformat'"=="!") local xijformat `thisformat'
			else if ("`thisformat'"!="`xijformat'") local xijformat = ""
			* Get and process value label.
			local thisvallabel : value label `varname'
			if (`"`xijvallabel'"'=="!") local xijvallabel `thisvallabel'
			else if (`"`thisvallabel'"'!=`"`xijvallabel'"') local xijvallabel = ""
			* Get and process variable label.
			local thisvarlabel : variable label `varname'
			if (`"`xijvarlabel'"'=="!") local xijvarlabel `thisvarlabel'
			else if (`"`thisvarlabel'"'!=`"`xijvarlabel'"') local xijvarlabel = ""
			* Get and process type.
			local thistype : type `varname'
			getDatatypeNum `thistype'
			local thistypestr = r(str)  // 0 or 1, 1 if string
			local thistypenum = r(tnum)  // max. string length (. for strL), or 1=byte, 2=int, 3=long, 4=float, 5=double
			if ("`xijtype'"=="!") {
				local xijtype `thistype'
				local xijtypestr `thistypestr'  // 0 or 1, 1 if string
				local xijtypenum `thistypenum'  // max. string length (. for strL), or 1=byte, 2=int, 3=long, 4=float, 5=double
				local xijtyperefvar `varname'  // This stores the name of the variable that has the specified type, in case it is needed for an error message.
			}
			else {
				if (`thistypestr'!=`xijtypestr') giveError 108 "Variables `xijtyperefvar' and `varname' have incompatible datatypes; one is numeric and the other is string."
				if `thistypestr' {  // String variables.
					if (`thistypenum'>`xijtypenum') {
						local xijtype `thistype'
						local xijtypenum `thistypenum'
						local xijtyperefvar `varname'
					}
				}
				else {  // Numeric variables.
					if ((`thistypenum'==3 & `xijtypenum'==4) & ("`recastasdouble'"=="")) {  // `recastasdouble' is either null or "norecastasdouble".
						* This variable is long, and the type determined so far is float, so precision could be lost if the long numbers are high enough.  The options request to correct for this.
						su `varname', meanonly
						if (max(abs(r(min)),abs(r(max)))>16777216) {
							local xijtype double
							local xijtypenum 5
							// Leave local xijtyperefvar as-is.  It only gets used for a numeric-vs.-string error message anyway.
						}
					}
					else if (`thistypenum'==4 & `xijtypenum'==3) {
						* This variable is float, and the type determined so far is long, so promote to float.
						local xijtype float
						local xijtypenum 4
						local xijtyperefvar `varname'
						* Precision could be lost if long numbers converted to float are high enough, and the options request to correct for this.
						if ("`recastasdouble'"=="") {
							* Go through the j-values that have already been analyzed, to check whether their Xij wide variables are of type long, and if so whether they require storage in a double instead of a float variable.
							*   The loop below is similar to a main loop above, with varname renamed to varname2.
							local v2 = 0
							foreach varname2 of local xijvars_byx_`x' {
								local ++v2
								if ("`varname2'"=="`varname'") continue, break  // Only go through j-values that have already been analyzed, stopping at the j-value currently being analyzed.
								if ("`varname2'"==".") continue  // Ignore nonexistent variables.
								if (`xijCheckedForLargeLongs'>=`v2') continue  // Already checked this variable.
								local thistype : type `varname2'
								if ("`thistype'"=="long") {
									capture assert abs(`varname2')<=16777216, fast
									if _rc>1 {
										local xijtype double
										local xijtypenum 5
										// Leave local xijtyperefvar as-is.  It only gets used for a numeric-vs.-string error message anyway.
										continue, break
									}
									else if (_rc==1) error 1
								}
							}  // end of: foreach varname2 of local xijvars_byx_`x' {
							local xijCheckedForLargeLongs = `v2'  // This many of these Xij wide variables, for this x, have already been checked.  There is no need to check them again, if another long variable turns out to need checking.
						}
					}
					else if (`thistypenum'>`xijtypenum') {
						local xijtype `thistype'
						local xijtypenum `thistypenum'
						local xijtyperefvar `varname'
					}
				}
			}
		}
		* Save the resulting information for this X.
		local xijformat_`x' `xijformat'
		local xijvallabel_`x' `"`xijvallabel'"'
		local xijvarlabel_`x' `"`xijvarlabel'"'
		local xijtype_`x' `xijtype'
		local xijtypestr_`x' `xijtypestr'
	}
	* 6. I used to develop an optimal order of processing among the variables, but in the current version of the program, that would make little difference.
	*      Therefore, I now just use my prior "left shifted" case.
	*    The results of this section are a base index # and an ordering list.  The jvalnums are: 1 2 3 ... Nj.  The ordering chooses one jvalnum to be the base, and permutes the remaining numbers
	*      to say which should come first in the reshaping.
	* The newly created variable will be based on the leftmost variable in the list, and observations will be added starting from the right side of the list.
	local basej = 1
	if (`maxJvalnum'==1) local otherjordered = ""
	else {
		numlist "`maxJvalnum'/2"
		local otherjordered = r(numlist)
	}
	* 7. For each Xij, check whether an Xij wide variable exists for the base value of j.  If so, rename it and promote its datatype if needed, and if not create a variable of the right datatype.  Set its format and value label.
	local x = 0
	foreach varname_long of local cXijSubstituted {
		local ++x
		* Get the new variable name and check it is valid.
		capture confirm new variable `varname_long'
		if (_rc==110) giveError 110 "Xij variable already exists: `varname_long' (are the data already in long form?)"
		else if (_rc>1) giveError 198 "Xij variable name is invalid: `varname_long'"
		else if (_rc==1) error 1
		* Rename and promote if needed, or create the variable, and set the format and value label.
		local varname_wide : word `basej' of `xijvars_byx_`x''
		if ("`varname_wide'"==".") {
			* The Xij long variable must be created, because for the base j, there is no preexisting variable.
			local isstr = `xijtypestr_`x''
			if `isstr' quietly gen `xijtype_`x'' `varname_long' = ""
			else quietly gen `xijtype_`x'' `varname_long' = .
			if ("`xijformat_`x''"!="") format `varname_long' `xijformat_`x''
			if (`"`xijvallabel_`x''"'!="") label values `varname_long' `xijvallabel_`x''
			if (`"`xijvarlabel_`x''"'!="") label variable `varname_long' `"`xijvarlabel_`x''"'
		}
		else {
			* This Xij wide variable can be renamed to become the Xij long variable.
			rename `varname_wide' `varname_long'
			local type_long `xijtype_`x''
			local typenow : type `varname_long'
			if ("`typenow'"!="`type_long'") recast `type_long' `varname_long'
			if ("`xijformat_`x''"=="") {  // If the format is not null, then it is already correct, because all the wide variables had to have the same format for the long Xij format to be non-null.
				* Clear the format.  Actually in Stata, there is no way to clear a format; one just sets the format to the default for a specific datatype.
				if (inlist("`type_long'","byte","int")) format `varname_long' %8.0g
				else if "`type_long'"=="long" format `varname_long' %12.0g
				else if "`type_long'"=="float" format `varname_long' %9.0g
				else if "`type_long'"=="double" format `varname_long' %10.0g
				else if "`type_long'"=="strL" format `varname_long' %9s
				else if substr("`type_long'",1,3)=="str" {
					local n = substr("`type_long'",4,.)
					format `varname_long' %`n's
				}
			}
			if ((`"`xijvallabel_`x''"'=="") & (!`xijtypestr_`x'')) label values `varname_long' .  // If the value label is not null, then it is already correct, because all the wide variables had to have the same value label for the long Xij format to have a non-null value label.  If it is null, clear the value label if the variable is not a string (strings have no value labels).
			if (`"`xijvarlabel_`x''"'=="") label variable `varname_long' ""  // If the variable label is not null, then it is already correct, because all the wide variables had to have the same variable label for the long Xij format to have a non-null variable label.  If it is null, clear the variable label.
			* Clear any notes associated with this variable.
			quietly notes drop `varname_long' _all
		}
	}
	* 8. Create j and set it equal to the first value.  Create a string to check whether j equals its base value.
	local basejv : word `basej' of `cjv'  // `basej' is just a number, telling us that a specific word in the list `cjv' is the j-value to use as the base j-value (base means, the corresponding Xij wide variable has been turned into the Xij long variable).
	if `cstr' {
		* Determine the length needed for the string variable.
		local jstrMaxLen = 1
		foreach jval of local cjv {
			local thisLen = length("`jval'")
			if (`thisLen'>`jstrMaxLen') local jstrMaxLen = `thisLen'
		}
		if (`jstrMaxLen'>90) local jstrMaxLen = "L"  // If the j-value variable has to hold over 90 characters, it is made a strL to limit memory usage.
		* Create the variable.
		gen str`jstrMaxLen' `cj' = "`basejv'"
		local varjIsBase = `"`cj'=="`basejv'""'  // Create a string for use in the next step, to determine in which observations the new j variable equals the base value.  (If the next step is done in mata, then this is not needed.)
	}
	else {
		local jvarnameType = cond(`basejv'<=100, "byte", cond(`basejv'<=32740, "int", cond(`basejv'<=2147483620, "long", "double")))
		gen `jvarnameType' `cj' = `basejv'
		local varjIsBase = "`cj'==`basejv'"  // Create a string for use in the next step, to determine in which observations the new j variable equals the base value.  (If the next step is done in mata, then this is not needed.)
	}
	* 8A. Order the i and j variables as they eventually need to be ordered.  Putting them first now avoids having to change their variable indices in Mata code for step 9.
	order `ci' `cj'
	* 9. Step through the j's, other than the base j, in the order chosen earlier.  At each step, move information from a wide variable to long and delete the wide variable.
	* 9A. Initialize the storage system used to store data outside the Stata dataset.
	local njvals : word count `cjv'
	local futuremanyobs = cond(_N*`njvals' > 2147483647, "futuremanyobs", "")  // If necessary, indicate the possible number of observations exceeds 2147483647.
	local maxNumStores = (`maxXijvarnum'+1)*`njvals'  // This allows 1 storage space for each Xij wide variable, plus 1 for an if-variable for each j-value.
	local mataonly = cond(`favorspace'==0, "mataonly", "")  // If not favoring space, use mata only instead of attempting to store via C or java.  This is faster but takes more memory for byte/int/long/float variables.
	initStoreVarUsingPlugin , maxstores(`maxNumStores') `futuremanyobs' `mataonly'
	* 9B. Sort now so final data will be in sorted order.
	sort `ci'
	* 9C. Save variables to plugins' RAM, in relevant observations, and drop original variables.
	tempvar saveThisObs
	foreach j of local otherjordered {
		* 9C1. Determine which observations to save in the plugins' RAM, and save, for this j.
		if `haveSomeObs' {
			if (!`drop') {
				local saveAllObs_`j' = 1  // All observations will be saved.
				local saveNoObs_`j' = 0
			}
			else {
				local saveIfExpr "!("
				local didFirstVar 0
				foreach varname of local xijvars_byj_`j' {
					local andForExpr = cond(`didFirstVar',"&","")
					local saveIfExpr "`saveIfExpr'`andForExpr'missing(`varname')"
					local didFirstVar 1
				}
				local saveIfExpr "`saveIfExpr')"
				gen byte `saveThisObs' = `saveIfExpr'
				quietly count if `saveThisObs'
				local saveAllObs_`j' = r(N)==_N
				local saveNoObs_`j' = r(N)==0
				local nSaved_`j' `=r(N)'
//if (!`saveAllObs_`j'') {
//di `"storeVarUsingPlugin `saveThisObs', vartypenum(-1) favorspace(`favorspace')"'
//more
//}
				if (!(`saveAllObs_`j''|`saveNoObs_`j'')) {
					storeVarUsingPlugin `saveThisObs', vartypenum(-1) favorspace(`favorspace')  // This saves variable `saveThisObs' in all observations., yielding a memory access code stored below in `ramS_`j''.  The -1 indicates a byte variable -- this is stored in 1 byte per datum.  The RAM needs to be released later to prevent a memory leak.
					local ramS_`j' = r(savedDataAccessInfo)
				}
			}
		}
		else local saveNoObs_`j' = 1
		* 9C2 and 9C3. Store data, drop `saveThisObs' if not needed.
		* 9C2. Save data in plugins' RAM and drop variables.
		local x = 0
		foreach varname of local xijvars_byj_`j' {
			local ++x
			if ("`varname'"==".") continue  // A period indicates the wide variable does not exist.
			if (`haveSomeObs' & (!`saveNoObs_`j'')) {
				local vartype : type `varname'
				getDatatypeNumForMemVar "`vartype'"
				local varTypeNum = r(memVarTNum)
				local strlout = ""
				if (`varTypeNum'>0) {
					* If the long type will be strL, prevent saving using C plugin, because data retrieval would not be allowed (due to potential problems writing strL's reliably using Stata's C plugin interface).
					*   If the current type is already strL, the C plugin will not be used anyway.
					local Xijvar : word `x' of `cXijSubstituted'  // CORRECTED 16Jan2016: This needs to say cXijSubstituted not cXij.
					local longVarType : type `Xijvar'
					if ("`longVarType'"=="strL") local strlout = "strlout"  // Ensure data can be retrieved for Xij variables that are becoming strL.
				}
				if (`saveAllObs_`j'') storeVarUsingPlugin `varname', vartypenum(`varTypeNum') `strlout' favorspace(`favorspace')  // This saves variable `xijvars_byj_`j'' in all observations, yielding a memory access code to be stored in `ramS_`j'_`x''.  This is, where practical, saved in a datatype consistent with the Stata datatype to save space.  The RAM needs to be released later to prevent a memory leak.
				else storeVarUsingPlugin `varname' if `saveThisObs', vartypenum(`varTypeNum') nobssaved(`nSaved_`j'') `strlout' favorspace(`favorspace')  // This saves variable `xijvars_byj_`j'' in relevant observations only, yielding a memory access code to be stored in `ramS_`j'_`x''.  This is, where practical, saved in a datatype consistent with the Stata datatype to save space.  The RAM needs to be released later to prevent a memory leak.
				local ramS_`j'_`x' = r(savedDataAccessInfo)
			}
			drop `varname'
		}
		* 9C3. Drop the `saveThisObs' variable, if it was created.
		if (`haveSomeObs'&`drop') drop `saveThisObs'
	}
	* 9D. Add observations and fill them in.
	*     This loops across j, expanding the number of observations each time and filling in data.  A more streamlined approach might be to expand for more than one j at a time, when free RAM allows.
	if `haveSomeObs' {
		if (`drop') quietly gen byte `saveThisObs' = .
		foreach j of local otherjordered {
			if (`saveNoObs_`j'') continue  // If saving no observations, skip this step.
//di "9D j=`j'; otherjordered=`otherjordered'"  // DEBUG
			* 9D1. Expand observations for this j.  Expand adds observations to the END of the dataset, so values of j need be filled in only in the latter rows.  This assumes that the added observations are in the original sort order, which is not promised in the Stata documentation, but seems always to be true.
			local nBeforeExpand = _N
			if ((!`drop') | `saveAllObs_`j'') {
				if (`haveSomeObs') quietly expand 2 in 1/`initN'
			}
			else {  // Need to use the variable `saveAllObs_`j'', which tells which observations to expand in.  This has been stored and is retrieved, then used for the expansion.
//di `"retrieveVarUsingPlugin `saveThisObs' in 1/`initN', vartypenum(-1) accessinfo("`ramS_`j''") freeram"'
//more
				retrieveVarUsingPlugin `saveThisObs' in 1/`initN', vartypenum(-1) accessinfo("`ramS_`j''") freeram  // This frees the RAM from this saved variable.
				quietly expand 2 if `saveThisObs' in 1/`initN'  // This copies the j and Xij data too, but these really need to be filled in with the correct values.  Expanding without that copying would be faster.
			}
			* 9D2. Fill in values of the j variable in the new observations.
			local firstExpandedObsNum = `nBeforeExpand' + 1
			local lastExpandedObsNum = _N
			local jval : word `j' of `cjv'
			if (!`cstr') quietly replace `cj' = `jval' in `firstExpandedObsNum'/`lastExpandedObsNum'
			else quietly replace `cj' = "`jval'" in `firstExpandedObsNum'/`lastExpandedObsNum'
			* 9D3. Copy values to each Xijvar from each RAM-saved Xij wide variable, then free the saved variable RAM.
			local x = 0
			foreach varname of local xijvars_byj_`j' {
				local ++x
				local Xijvar : word `x' of `cXijSubstituted'
				if ("`varname'"==".") {
					if (`xijtypestr_`x'') quietly replace `Xijvar' = "" in `firstExpandedObsNum'/`lastExpandedObsNum'
					else quietly replace `Xijvar' = . in `firstExpandedObsNum'/`lastExpandedObsNum'
				}
				else {
					local vartype : type `Xijvar'
					getDatatypeNumForMemVar "`vartype'"
					local varTypeNum = r(memVarTNum)
//list
//di `"retrieveVarUsingPlugin `Xijvar' in `firstExpandedObsNum'/`lastExpandedObsNum', vartypenum(`varTypeNum') accessinfo("`ramS_`j'_`x''") freeram"'
//more
					retrieveVarUsingPlugin `Xijvar' in `firstExpandedObsNum'/`lastExpandedObsNum', vartypenum(`varTypeNum') accessinfo("`ramS_`j'_`x''") freeram  // This frees the RAM from this saved variable.
//list
				}
			}
		}
		if (`drop') drop `saveThisObs'
		//more
	}
	* 9E. Finish using storage spaces, ensuring all spaces are freed.
	endStoreVarsUsingPlugin
	* 10. Drop observations not needed from among the original observations.
	if (`drop') {
		* 10A. Determine which observations had only missing values for the base value of j.  The variable `todrop' used here could have been computed earlier, but it is most memory-efficient (and possibly faster) to compute it now.
		tempvar todrop
		gen byte `todrop' = `varjIsBase'  // Assume that an observation needs to be dropped until proven otherwise.
		foreach Xijvar of local cXijSubstituted {
			quietly replace `todrop' = 0 if !missing(`Xijvar')
		}
		if (!`dropall') qbys `ci' (`cj'): replace `todrop' = 0 if _N==1  // Otherwise, i.e., when `dropall'==1, observations with missing values are dropped even if that leaves no observations for a given combination of the i-variables.
		* 6B. Drop the observations, and drop the temporary variable used.
		quietly drop if `todrop'
		drop `todrop'
	}
	* 11. Sort observations, and order variables.
	sort `ci' `cj'
	//order `ci' `cj'  // This is now done at the end of step 8, to simplify mata coding for step 9.
	* 12. Save characteristics.  cXi and catwl are kept from the prior use of reshape, and are not replaced.  cjv is saved only if it was given as an option.
	//if (`newReshapeInfo' & `initXiLen') char _dta[Res_Xi]  // Overwrite previous Xi variables list with null.  Note the lowercase s in this characteristic; this is how Stata keeps this.
	char _dta[Res_Xi]
	char _dta[ReS_Xij] `cXij'
	if (`jvlen') char _dta[ReS_jv] `cjv'
	char _dta[ReS_str] `cstr'
	char _dta[ReS_j] `cj'
	char _dta[ReS_ver] v.2
	char _dta[ReS_i] `ci'
	char _dta[ReS_atwl] `catwl'
	* 13. Return results.
	return scalar N = _N
	return scalar k = c(k)
	return scalar width = c(width)
	return scalar changed = 1
	* 14. Display report about results.
	local njvals : word count `cjv'
	di
	di as text "Data                               wide   ->   long"
	di "-----------------------------------------------------------------------------"
	di "Number of obs." _col(32) as result %8.0g `initN' _col(43) as text "->" as result %8.0g _N
	di as text "Number of variables" _col(32) as result %8.0g `initk' _col(43) as text "->" as result %8.0g c(k)
	di as text "j variable (`njvals' values)" _col(43) "->   " as result "`cj'"
	di as text "xij variables:"
	local x = 0
	foreach Xijvar of local cXijSubstituted {
		local ++x
		local xijwidevarLast = ""
		local j = 0
		foreach xijwidevar of local xijvars_byx_`x' {
			if ("`xijwidevar'"==".") continue  // Ignore Xij wide variable names if the variables do not exist.  Unlike Stata's built-in command as of 14.0, this does not list nonexistent variables when showing the transformation made.
			local ++j
			if (`j'==1) local xijwideThisX `xijwidevar'
			else if (`j'==2) local xijwideThisX `xijwideThisX' `xijwidevar'
			else local xijwidevarLast `xijwidevar'
		}
		if (`j'==3) local xijwideThisX `xijwideThisX' `xijwidevarLast'
		else local xijwideThisX `xijwideThisX' ... `xijwidevarLast'
		local xijwideThisXLen : length local xijwideThisX
		if (`xijwideThisXLen'<=39) {
			local startAtCol = 40 - `xijwideThisXLen'
			di _col(`startAtCol') as result "`xijwideThisX'" _col(43) as text "->" _continue
			local extraSpaceTakenAtLeft = 0
		}
		else if (`xijwideThisXLen'<42) {
			di as result "`xijwideThisX'" _col(43) as text "->" _continue
			local extraSpaceTakenAtLeft = 0
		}
		else {
			di as result "`xijwideThisX'" as text "->" _continue
			local extraSpaceTakenAtLeft = `xijwideThisXLen' - 42  // This is the amount of less space than usual to the right of the arrow.
		}
		local Xijvarlen : length local Xijvar  // Length of the Xij long variable name.
		local maxspacesok = 33 - `Xijvarlen' - `extraSpaceTakenAtLeft'  // 33 is the number of chars of space to the right of the arrow, allowing 77 total.
		if (`maxspacesok'>0) {
			local colToGoTo = 45 + min(`maxspacesok',3)  // Display up to 3 spaces if there is room without exceeding 77 chars.
			di _col(`colToGoTo') as result "`Xijvar'"
		}
		else di as result "`Xijvar'"
	}
	di as text "-----------------------------------------------------------------------------"
	* 15. Cancel the previous data preservation.
	if (`preserved') restore, not
end

* Reshape to wide form.
program define sreshape_wide, rclass
	version 13
	* 1. Get some initial data.
	* 1A. Get reshaping requirements previously stored as characteristics, into the local variables ci, cj, etc.
	local ci : char _dta[ReS_i]  // i variable names
	local cj : char _dta[ReS_j]  // j variable name
	local cjv : char _dta[ReS_jv]  // j values, if specified.  This may consist of integers, or of nonnumeric ends of variable names if string has been specified.
	local cXij : char _dta[ReS_Xij]  // Xij variable names
	local cXiWas : char _dta[Res_Xi]  // Xi variable names, if specified.  Note the lowercase s in this characteristic; this is how Stata keeps this.
	local cXi = ""  // Carrying over the setting of cXi is too dangerous, and is disallowed.
	local catwl : char _dta[ReS_atwl]  // atwl() value, if specified
	local cstr : char _dta[ReS_str]  // 1 if option string specified; 0 otherwise
	local initXiLen : length local cXi
	* 1B. Get initial numbers of observations and variables.
	local initk = c(k)
	local initN = _N
	if `initN'==0 giveError 2000 "no observations"  // This error code is not ideal since it refers to a statistical calculation, but there is no pre-established code for nonstatistical calculations with no data.
	* 2. Check the syntax, preserve, and read in arguments.  Where arguments should replace values stored in characteristics, they will be put in the local variables ci, cj, etc.
	*    I have not verified whether Stata uses the saved j name, versus makes _j, if a new i is specified and j is not specified.  I use the saved j name if any, otherwise use _j.
	gettoken stubnamelist 0: 0, parse(",")  // Do not just use [anything] in the syntax command to get the stubnamelist, because "in@" would confuse the syntax command.
	syntax , [i(varlist) NEWI(string) j(string) String atwl(string) keeponlyxi(string) Widevars(string) MIssing(string) noRECastasdouble NOCOMpress NOPRESERVE Favorspace(integer 0)]  // atwl(string) is available only in reshape's advanced syntax nd hence not allowed in reshape long, so for comparability of behavior atwl(string) is not supported in sreshape long.
	local needtopreserve = "`nopreserve'"==""
	local preserved = 0
	local ilen : length local i
	local newilen : length local newi
	if (`newilen') giveError 198 "The newi() option may not be used for sreshape wide; you must specify an i variable."
	local jlen : length local j
	local jvlen = 0  // Assume no j-values were given until we find out otherwise.
	local stubnamelistlen : length local stubnamelist
	local widevarslen: length local widevars
	if `widevarslen' {
		if !inlist(`"`widevars'"',"all","nonmissing") giveError 198 `"The widevars option must be "all" (the default) or "nonmissing"."'
	}
	else local widevars = "all"
	local widevarsNonmissingOnly = "`widevars'"=="nonmissing"  // . and .a through .z count as missing.  If only missing values would be in a wide variable, it is not created if the user specifies "nonmissing".
	local missing = trim(itrim(`"`missing'"'))
	local drop = inlist(`"`missing'"', "drop", "drop all")  // drop = 1 if missing is drop OR drop all, 0 if missing is keep.
	local dropall = `"`missing'"'=="drop all"  // If dropall = 1, then also drop = 1.
	if ( (!`drop') & (!inlist(`"`missing'"', "keep", "")) ) giveError 198 `"The missing option must be "keep" (the default), "drop", or "drop all".  This is not used for reshape wide anyway."'
	if (`favorspace'<0) | (`favorspace'>4) giveError 198 "The favorspace option must be 0, 1, 2, 3, or 4 (higher numbers may reduce memory usage, if so at the cost of slower processing unless there is insufficient memory)."
	local atwllen : length local atwl
	local keeponlyxilen : length local keeponlyxi
	local newReshapeInfo = (`ilen' | `jlen' | `stubnamelistlen' | `atwllen' | `keeponlyxilen')
	if `newReshapeInfo' {
		* Since new i, j, or Xij info has been given here, clear old values for i, j, jv, Xij, and str.  Retain Xi and atwl.
		local ci = ""
		local cj = ""
		local cjv = ""
		local cXij = ""
		local cstr = 0
		//local catwl = ""   // To maintain compatability with Stata's reshape approach, which takes atwl info from prior advanced reshapes, the value of atwl is NOT replaced with null if not specified.  It may be replaced with null by specifying option atwl(.)
		local cXi = ""   // To maintain compatability with Stata's reshape approach, which takes Xi info from prior advanced reshapes, the value of Xi ought not to be replaced with null if not specified.  It may be replaced with null by specifying undocumented option keeponlyxi(.)  However, this advanced-option usage of reshape is dangerous, particularly if prior settings are carried over to future usage.  Therefore prior setting are NOT carried over in sreshape.
	}
	if `atwllen' {
		if (`"`atwl'"'==".") local catwl = ""
		else local catwl = `"`atwl'"'
	}
	if `keeponlyxilen' {
		if (`"`keeponlyxi'"'==".") local cXi = ""
		else {
			//capture confirm variable `keeponlyxi'
			unab cXi : `keeponlyxi'
		}
	}
	else {
		local cXiWasLen : length local cXiWas
		if `cXiWasLen' giveError 198 "sreshape does not support reshape's advanced-format Xi setting, because of danger of unintentionally dropping data.  Please drop undesired Xi variables explicitly."
	}
	local doCompression = "`nocompress'"==""
	* 2A. Get the i varlist.
	*       When checking that it uniquely identifies each observation, if there is an error, flag the error and wait until later to give the error, because the right information needs to be built up to load into data characteristics that allow use of "reshape error".
	if ("`i'"!="") {
		local ci `i'
	}
	else if `newReshapeInfo' {  // If a new j or Xij is specified then i must be specified at the same time, or if i has not been declared from previous use of reshape then i must be declared.
		giveError 198 "option i() required"
	}
	else {
		local cilen : length local ci
		if (!`cilen') giveError 198 "specify the i variable name(s)."
	}
	* 2B. Get the Xij varnames.
	* 2B1. Get the names.
	if (`stubnamelistlen') local cXij `"`stubnamelist'"'
	else if (`newReshapeInfo') giveError 198 "invalid syntax: specify the Xij variable names."
	else {
		local cxijlen : length local cXij
		if (!`cxijlen') giveError 198 "specify the Xij variable names."
	}
	* 2B2. Get the long versions of the names, and check the variables exist.
	local cXijSubstituted : subinstr local cXij "@" `"`catwl'"', all count(local nSubs)  // Unicode-compatible in Stata 14.
	if (`nSubs'>1) {  // Check that there are never 2 or more @ symbols in one variable name.
		foreach Xijvar of local cXij {
			local Xijvar : subinstr local Xijvar "@" "", all count(local nSubs)
			if (`nSubs'>1) giveError 198 "variable names may not be specified with more than one @ symbol."
		}
	}
	capture confirm variable `cXijSubstituted', exact
	if (_rc>1) giveError `=_rc' "the Xij variable list is invalid (is the dataset already in wide form?)."
	else if (_rc==1) error 1
	* 2B3. Get the long names in the order they appear in the dataset.  This is to make the final ordering of the variables the same as in long form, and the same as Stata uses.
	quietly ds
	local allvars = r(varlist)
	local cXijSubstitutedOrdered = ""
	foreach v of local allvars {
		local islongvar: list v in cXijSubstituted
		if `islongvar' local cXijSubstitutedOrdered `cXijSubstitutedOrdered' `v'
	}
	local nCXij : word count `cXij'
	local cXijNew = ""
	tokenize `cXijSubstituted'
	foreach v of local cXijSubstitutedOrdered {  // Loop through in the correct order of the Xij long variables.
		forvalues wordnum = 1/`nCXij' {  // Loop through numbers of the words in cXijSubstituted, and see if the current Xij long variable is the wordnum-th word in cXijSubstituted.
			if ("`v'"=="``wordnum''") {
				* Word `wordnum' of cXijSubstituted is the same as this word in cXijSubstitutedOrdered.  So, word `wordnum' of cXij is the correct one to use to put cXij in order too.
				local wordFromCXij : word `wordnum' of `cXij'
				local cXijNew `cXijNew' `wordFromCXij'
				continue, break
			}
		}
	}
	local cXij `cXijNew'
	local cXijSubstituted `cXijSubstitutedOrdered'
	* 2B4. For each word in the (now possibly reordered) cXij stubnamelist, save information on whether it contains an "@" symbol.  This information will be used for variable labelling.
	local x = 0
	foreach Xijvar of local cXij {
		local ++x
		local Xijvar : subinstr local Xijvar "@" "", count(local nSubs)
		if `nSubs' local cXijAt`x' = "1"  // A "1", instead of null, indicates this stubname contains an "@" symbol.  This is not 0-1; it is ""-"1".
	}
	* 2C. Get the j varname, and its values and string option if needed.
	* 2C1. String option.
	if ("`string'"=="string") local cstr = 1  // This must be done BEFORE processing j.
	else if (`newReshapeInfo') local cstr = 0  // If the characteristics of the reshape are being reset, assume not string unless string is specified, regardless whether string was used in previous reshape settings or in advanced settings.
	* 2C2. j varname (and grab values if stated).
	if (`jlen') {
		gettoken j jv : j
		local 0 `j'  // Get ready to get exact name of the j-variable, allowing for abbreviations.
		capture syntax varname  // This gets the exact name of the j-variable, allowing for abbreviations.
		//capture confirm variable `j', exact  // Don't do this, because it leaves the variable name for the j-variable in a possibly abbreviated form.
		if _rc {  // _rc==111 occurs if the variable does not exist, or 198 for an invalid variable name.  _rc==0 occurs if the variable name is valid.
			if (_rc==111) giveError 111 "variable `j' does not exist"
			else if (_rc==198) giveError 198 `"invalid variable name `j'"'
			else if (_rc==1) error 1
			else giveError `=_rc' "invalid j variable name"
		}
		local j `varlist'
		local cj `j'
		local jvlen : length local jv
		if (`jvlen') {  // Parse j-values to get a string of space-separated values (integers, or strings of characters allowed in variable names).  While I at first wrote my own extraction code here, it avoids duplication to use Stata's code.  Stata does not check string j-values for seeming validity, an advantage in my version (see file "sreshape bak11Apr2015.ado").
			reshape j `j' `jv', `string'
			local cjv : char _dta[ReS_jv]
		}
	}
	else {
		* No j variable was declared.
		if ("`cj'"=="" | `newReshapeInfo') local cj = "_j"
		capture confirm variable `cj', exact
		if _rc {  // _rc==111 occurs if the variable does not exist, or 198 for an invalid variable name.  _rc==0 occurs if the variable name is valid.
			if (_rc==111) giveError 111 "j variable `j' does not exist"
			else if (_rc==198) giveError 198 `"invalid j variable name `j'"'
			else if (_rc==1) error 1
			else giveError `=_rc' "invalid j variable name"
		}
	}
	* 2C3. Confirm string or numeric type of j variable coincides with string option.  If the j-variable is numeric and stored in a float or double, ensure its values are integers.
	local vartype: type `cj'
	if (substr("`vartype'",1,3)=="str") {
		if (!`cstr') giveError 109 "variable `cj' is string; specify string option"
	}
	else {
		if (`cstr') giveError 109 "variable `cj' is numeric"
		if `needtopreserve' {
			preserve
			local needtopreserve = 0
			local preserved = 1
		}
		if (`doCompression') quietly compress `cj'
		if inlist("`jtype'","float","double") {
			capture assert `cj'==trunc(`cj'), fast
			if (_rc>1) giveError 459 "j values must be integer or string, but non-integer numbers are in `cj'"
			else if (_rc==1) error 1
		}
	}
	* 2C4. Determine the lowest j-value, and ensure there are no missing j-values.
	if (`cstr') {
		mata: minValOfStringVar("`cj'")
		local basejval = r(minStr)
		if "`basejval'"=="" giveError 498 "variable `cj' contains missing values"
	}
	else {
		su `cj', meanonly
		local basejval = r(min)
		if (r(N)<_N) giveError 498 "variable `cj' contains missing values"
	}
	* 2D. Determine whether any of the cXij begin with @.  (If so, j-values are not allowed to begin with a numeric digit.)
	local anXijBeginsWithAtSign = 0
	foreach v of local cXij {
		if substr("`v'",1,1)=="@" {
			local anXijBeginsWithAtSign = 1
			continue, break
		}
	}
	if (`anXijBeginsWithAtSign' & (!`cstr')) giveError 198 "cannot use @ at the start of an Xij variable name with numeric j values"
	* 2E. Get the Xi variable list, if not specified.  In either case, the Xi variable list goes in `cXi'.
	local cXilen : length local cXi
	if (`cXilen'==0) {
		local ijandxijvars `ci' `cj' `cXijSubstituted'
		local cXi : list allvars - ijandxijvars  // Local macro allvars was created above.
		local cXilen : length local cXi  // This is used below.
	}
	* 2F. Check that values of j are unique within i.
	* 2F1. If the data are not already sorted by i, then preserve and sort.
	local cilen : length local ci
	local sortedby : sortedby
	if (("`ci'"!=substr("`sortedby'",1,`cilen')) | (!inlist(substr("`sortedby'",`cilen'+1,1),""," "))) {
		if `needtopreserve' {
			preserve
			local needtopreserve = 0
			local preserved = 1
		}
		sort `ci' `cj'  // Just sorting by i would be sufficient here, but sorting by j too gets the data to the order needed soon.
	}
	* 2F2. Confirm unique j within i.
	capture qby `ci': assert `cj'!=`cj'[_n-1], fast  // Could alternatively write assert `cj'!=`cj'[_n-1] if _n>1  , but this is not necessary since `cj'[0] is missing and `cj'[1] has already been shown to be nonmissing (in fact all the j values are nonissing).
	if (_rc>1) {
		local nIVars : word count `ci'
		if (`nIVars'==1) local juniqerror "values of variable `cj' not unique within `ci'"
		else local juniqerror "values of variables `cj' not unique within `ci'"
	}
	else if (_rc==1) error 1
	* 2G. Check that the Xi are constant within i.
	if `cXilen' {
		local errorvars = ""
		foreach v of local cXi {
			capture qby `ci': assert `v'==`v'[1], fast
			if (_rc>1) local errorvars `errorvars' `v'
			else if (_rc==1) error 1
		}
		local nErrorVars : word count `errorvars'
		if (`nErrorVars'==1) local xiconsterror "values of Xi variable `errorvars' not constant within `ci'"
		else if (`nErrorVars'>1) local xiconsterror "values of Xi variables not constant within i variable(s); this occurs for Xi variables: `errorvars'"
	}
	* 2H. If there was an error flagged that the j variables are not unique within i, or that the Xi are not constant within i, then load the characteristics into the data now and give the error message.
	*       If the data were preserved, they must first be restored so that these changes will stick, allowing "reshape error" to be used afterward.
	local juniqerrorlen : length local juniqerror
	local xiconsterrorlen : length local xiconsterror
	if (`juniqerrorlen'|`xiconsterrorlen') {
		* 2H1. Restore if necessary (i.e., if already preserved).
		if (`preserved') restore
		* 2H2. Save the characteristics and return results.  The code here is redundant with code at the end of program sreshape_long, but it is best to just write it again here to keep the program simple.
		//if (`newReshapeInfo' & `initXiLen') char _dta[Res_Xi]  // Overwrite previous Xi variables list with null.  Note the lowercase s in this characteristic; this is how Stata keeps this.
		char _dta[Res_Xi]  // Replace the Xi characteristic with null.  Local macro cXi has the list of Xi variables, but these are not meant to mean drop all Xi vars. not in the list.
		char _dta[ReS_Xij] `cXij'
		if (`jvlen') char _dta[ReS_jv] `cjv'
		char _dta[ReS_str] `cstr'
		char _dta[ReS_j] `cj'
		char _dta[ReS_ver] v.2
		char _dta[ReS_i] `ci'
		char _dta[ReS_atwl] `catwl'
		return scalar N = _N
		return scalar k = c(k)
		return scalar width = c(width)
		return scalar changed = 0  // This differs from the redundant code at the end of this program.
		* 2G3. Give the error message(s) and exit.  Do not use the giveError subprogram, because it would clear returned results.
		if `juniqerrorlen' di as error `"`juniqerror'"'
		if `xiconsterrorlen' di as error `"`xiconsterror'"'
		// HERE, THE SAME LONG-TO-WIDE PICTURE AND/OR EXPLANATORY TEXT USED BY RESHAPE SHOULD IDEALLY BE DISPLAYED.  I do not display it since it is copyrighted by StataCorp.
		di as error "Type reshape error (or sreshape error) for a list of the problem observations."
		exit 9
	}
	* 2I. Preserve, if not yet done.
	if `needtopreserve' {
		preserve
		local needtopreserve = 0
		local preserved = 1
	}
	* 3. If requested, drop Xi variables not specified in an Xi list.
	local cXi_len : length local cXi
	if `cXi_len' keep `ci' `cj' `cXijSubstituted' `cXi'
	* 4. If compression is requested, compress Xij long variables if possible (compression will also be carried out on individual wide variables where possible).
	if (`doCompression') quietly compress `cXijSubstitutedOrdered'
	* 5. Get a numbering, in order by `ci', of the i-value-combinations.  This will reveal, within each j, the corresponding observation number in the wide data.
	*      The numbering of the i-value-combinations is in variable `inum'.
	*        If `ci' is 1 varname AND (for all obs) `inum'==`ci', this just drops `inum' and sets local inum = "`ci'".
	*    Also determine the number of i-value-combinations.
	tempvar firstInI inum
	qbys `ci' (`cj'): gen byte `firstInI' = _n==1
	local vartype = cond(_N<=100, "byte", cond(_N<=32740, "int", cond(_N<=2147483620, "long", "double")))
	gen `vartype' `inum' = sum(`firstInI')
	local needToDropInum = 1
	local nIVars : word count `ci'
	if `nIVars'==1 {
		capture assert `inum'==`ci', fast
		if (_rc==0) {
			drop `inum'
			local inum `ci'
			local needToDropInum = 0
		}
		else if (_rc==1) error 1
	}
	if `needToDropInum' quietly compress `inum'  // This temporary variable can be compressed regardless whether the user has requested compression -- as long as it's still the temporary variable, not `ci'.
	drop `firstInI'
	local nIValCombinations = `inum'[_N]
	* 6. Reshape to wide form.	
	* 6A. Constraints on plugin types that can be used.  This initialization is specific to the method used here to store data outside of the Stata dataset.
	local maxVarsBeingStored = min((_N+1)*`nCXij',2*32767)  // If every observation has a separate j-value and an if-var must be created, this gives an upper bound of (_N+1)*`nCXij' variables that would need to be stored.  Another upper bound is that only 32767 variables can exist in Stata (given limits as of version 14.0), so at most that many Xij wide variables would be stored plus at most one if-variable would be kept for each.
	local mataonly = cond(`favorspace'==0, "mataonly", "")  // If not favoring space, use mata only instead of attempting to store via C or java.  This is faster but takes more memory for byte/int/long/float variables.
	initStoreVarUsingPlugin , maxstores(`maxVarsBeingStored') `mataonly'
	* 6B. Ensure all i-combinations exist for the first j, creating new observations as needed.  These will become the observations in the wide data.
	tempvar expandNum newobs
	local nObsBeforeExpandPlus1 = _N+1
	if `cstr' qby `ci' (`cj'): gen byte `expandNum' = cond( _n>1 | `cj'==`"`basejval'"', 1, 2 )
	else qby `ci' (`cj'): gen byte `expandNum' = cond( _n>1 | `cj'==`basejval', 1, 2 )
	quietly expand `expandNum'
	local nObsAfterExpand = _N
	if (`nObsAfterExpand' >= `nObsBeforeExpandPlus1') {
		if `cstr' quietly replace `cj' = `"`basejval'"' in `nObsBeforeExpandPlus1'/`nObsAfterExpand'
		else quietly replace `cj' = `basejval' in `nObsBeforeExpandPlus1'/`nObsAfterExpand'
		foreach Xijvar_longVarname of local cXijSubstituted {  // Fill the Xij variables with missing in the new observations from the expand.
			local vartype : type `Xijvar_longVarname'
			if (substr("`Xijvar_longVarname'",1,3)=="str") quietly replace `Xijvar_longVarname' = "" in `nObsBeforeExpandPlus1'/`nObsAfterExpand'
			else quietly replace `Xijvar_longVarname' = . in `nObsBeforeExpandPlus1'/`nObsAfterExpand'
		}
	}
	drop `expandNum'
	* 6C. Sort by `cj' `ci', to be ready store data in sorted order within each j, and to have the data in the right order within the first j.
	quietly sort `cj' `ci'
	* 6D. Store the data using plugins (or mata), and delete observations, starting with the last value of j.
	*       In the process, this determines the Xij wide variable names, and stores them in two different ways: by Xij var., and by j-value.
	*         Periods indicate Xij-jval combinations for which there will be no variable.
	*         These are stored in local variables xijvars_byx_# and xijvars_byj_#.  The term "byx" is an abbreviation meaning "by Xijvar", and the term "byj" is an abbreviation meaning "by j-value".
	*         Counter x points to the x-th Xij var., and counter j points to the j-th j-value.
	*       For each j-value, an if-variable is stored if needed, indicating which observations to load information into in wide form.  The storage location is placed in local ramS_`j'.
	*         If no if-variable is stored, then local ramS_`j' is null.
	*       For each Xij wide variable, the wide-format data are stored in relevant observations, with the storage location placed in local ramS_`j'_`x'.
	local jvalsFound = ""
	local j = 0
	while (`cj'[_N]!=`cj'[1]) {
		local ++j
		* Get j-value.
		local jval = `cj'[_N]
		* Confirm the j-value is valid for use in names.
		local xForStartOfName = cond(`anXijBeginsWithAtSign',"","x")
		capture confirm names `xForStartOfName'`jval'
		if (_rc>1) {
			endStoreVarsUsingPlugin
			if (`anXijBeginsWithAtSign') giveError 198 "invalid j-value `jval' (strings must consist of letters, numeric digits, and underscore; they may not begin with a numeric digit, since you specified with @ that one of the wide variable names will begin with the string)"
			else giveError 198 "invalid j-value `jval' (numbers must be positive integers, strings must consist of letters, numeric digits, and underscore)"
		}
		else if (_rc==1) error 1
		* Compile a list of j-values found, putting it in ascending order.
		local jvalsFound `jval' `jvalsFound'
		* Determine which observations pertain to this j-value, and count relevant observations.  If only some i-variable combinations exist for this j-value, then store a dummy variable to indicate which i-variable combinations have Xij data for this j.
		mata: findFirstObsWithLastValIfSorted("`cj'")
		local obs1 = r(firstObsWithLastVal)
		local nObsWithLastVal = _N - `obs1' + 1
		local obs2 = _N
		local useIf = `nIValCombinations'!=`nObsWithLastVal'  // If this is 0, the observations for this j-value include all i-variable combinations.
		if (`useIf') {
			storeVarUsingPlugin `inum' in `obs1'/`obs2', vartypenum(-10) nobssaved(`nIValCombinations') favorspace(`favorspace') 
			local ramS_`j' = r(savedDataAccessInfo)
		}
		else local ramS_`j' = ""
		* Loop through different Xij long variables.
		local noXijVarsSavedForThisJ = `widevarsNonmissingOnly'  // This will be replaced with 0 if any Xij data were saved for this j-value.
		local x = 0
		foreach Xijvar of local cXij {
			local ++x
			* Get Xij wide variable name, and check it is okay.
			local Xijvar_wideVarname : subinstr local Xijvar "@" `"`jval'"', count(local nSubs)  // Unicode-compatible in Stata 14.
			if (`nSubs'==0) local Xijvar_wideVarname `Xijvar'`jval'
			capture confirm new variable `Xijvar_wideVarname'
			if (_rc) {  // An error code of 110 means the variable already exists, or 198 indicates an invalid variable name (that has illegal characters or begins with a number).
				endStoreVarsUsingPlugin
				if (_rc==110) giveError 110 "Variable `Xijvar_wideVarname' already exists.  (Are the data already wide?)"
				else if (_rc==1) error 1
				else giveError 198 "invalid wide Xij variable name: `Xijvar_wideVarname'"
			}
			* Get the long variable name and type.
			local Xijvar_longVarname : subinstr local Xijvar "@" `"`catwl'"'  // Unicode-compatible in Stata 14.
			local vartype : type `Xijvar_longVarname'
			getDatatypeNumForMemVar "`vartype'"
			local varTypeNum = r(memVarTNum)
			* If creating only those wide variables that would have at least some nonmissing values, check whether this is ever nonmissing.
			*   Note, using >=. instead of ==. below means that special missing value codes .a through .z count the same as ordinary missing in terms of whether no wide variable is created, if the user specified "widevars(nonmissing)".
			if `widevarsNonmissingOnly' {
				if (`varTypeNum'<0) capture assert `Xijvar_longVarname'>=. in `obs1'/`obs2', fast
				else capture assert `Xijvar_longVarname'=="" in `obs1'/`obs2', fast
				if (_rc==0) local Xijvar_wideVarname = "."  // Use a wide name of . to mean there is no need to create the variable because it would contain only missing values.
				else if (_rc==1) error 1
				else local noXijVarsSavedForThisJ = 0
			}
			* Store the data and save the storage info.  No if-condition is used in storing data; all observations for this j-value are stored.  The if-condition is used when retrieving data.
			if ("`Xijvar_wideVarname'"!=".") {
				storeVarUsingPlugin `Xijvar_longVarname' in `obs1'/`obs2', vartypenum(`varTypeNum') favorspace(`favorspace')
				local ramS_`j'_`x' = r(savedDataAccessInfo)
			}
			* Store the variable name.
			local xijvars_byx_`x'  `Xijvar_wideVarname' `xijvars_byx_`x''  // This gets ordered with later variables first, so that lower j-values come earlier.
			local xijvars_byj_`j' `xijvars_byj_`j'' `Xijvar_wideVarname'  // This gets ordered with later Xij variables later.
			if ("`Xijvar_wideVarname'"!=".") local xijvars_bnj_`j' `xijvars_bnj_`j'' `Xijvar_wideVarname'  // Build a variable like xijvars_byj_`j', but excluding periods that indicate Xij wide variables that don't exist.
		}
		* If no Xij data were stored for this variable, then no if-variable is needed, so if it was stored the stored information can be freed.
		*   In fact, it then MUST be freed if we are to make absolutely sure that the number of java storage slots allocated is not exceeded.
		if (`noXijVarsSavedForThisJ' & ("`ramS_`j''"!="")) {
			freeVarUsingPlugin , accessinfo("`ramS_`j''")
			local ramS_`j' = ""
		}
		* Drop the observations for this j-value.
		quietly drop in `obs1'/`obs2'
	}
	local nJValsFound `j'  // Excluding the base-j-value, so the actual number of j-values is 1 more than this.
	if `needToDropInum' drop `inum'
	* 6E. Finalize the list of j-values found, and note it to the user.  If the user provided a list of j-values and some were not found, indicate this.
	*     Also drop the j-variable, which is no longer needed.
	local jvalsFound `basejval' `jvalsFound'
	di as text `"(note: j = `jvalsFound')"'   // It is still possible that the j values list `cjv' has illegal characters for variable names.  If so, this will be discovered while reshaping.
	local cjvNotFound : list cjv - jvalsFound
	local cjvNotFoundLen : length local cjvNotFound
	if (`cjvNotFoundLen') {
		di as text `"(note: some j-values are not in the data: `cjvNotFound')"'
		local cjv : list cjv - cjvNotFound  // Remove any not-found j-values from the list stored after this routine finishes.
	}
	local cjvlen : length local cjv
	if `cjvlen' {
		local cjvExtrasFound : list jvalsFound - cjv
		local cjvExtrasFoundLen : length local cjvExtrasFound
		if (`cjvExtrasFoundLen') {
			di as text `"(note: unanticipated j-values are in the data: `cjvExtrasFound')"'
			local cjv `cjv' `cjvExtrasFound'  // Record the extra j-values so they are considered if, after this reshape to wide finishes, the user reshapes to long. 
		}
	}
//if (`cstr') assert `cj'=="`basejval'", fast  // DEBUG
//else assert `cj'==`basejval', fast  // DEBUG
	drop `cj'
	* 6F. Create wide variables and restore the data into them.
	tempvar ifvar
	forvalues j = `nJValsFound'(-1)1 {
		* Create a dummy variable indicating which observations to restore, if needed.
		local useif = "`ramS_`j''"!=""
		if `useif' {
			quietly gen byte `ifvar' = .
			retrieveVarUsingPlugin `ifvar', vartypenum(1) accessinfo("`ramS_`j''") freeram
		}
		* Loop through Xij's and create and restore.
		local x = 0
		foreach Xijvar_wideVarname of local xijvars_byj_`j' {
			local ++x
			* If the wide variable was marked as not-to-be-created because it contains only missing values, skip this wide variable.
			if ("`Xijvar_wideVarname'"==".") continue
			* Create the wide variable.
			local Xijvar_longVarname : word `x' of `cXijSubstituted'
			local vartype : type `Xijvar_longVarname'
			local vartypestr = substr("`vartype'",1,3)=="str"
			if (`vartypestr') quietly gen `vartype' `Xijvar_wideVarname' = ""
			else quietly gen `vartype' `Xijvar_wideVarname' = .
			* Store data into it.
			getDatatypeNumForMemVar "`vartype'"
			local varTypeNum = r(memVarTNum)
			if (`useif') retrieveVarUsingPlugin `Xijvar_wideVarname' if `ifvar', vartypenum(`varTypeNum') accessinfo("`ramS_`j'_`x''") freeram
			else retrieveVarUsingPlugin `Xijvar_wideVarname', vartypenum(`varTypeNum') accessinfo("`ramS_`j'_`x''") freeram
			* Compress if requested.
			if (`doCompression') quietly compress `Xijvar_wideVarname'
			* Set format.
			local thisformat : format `Xijvar_longVarname'
			format `thisformat' `Xijvar_wideVarname'
			* Set value label.
			local thisvallabel : value label `Xijvar_longVarname'
			if (`"`thisvallabel'"'!="") label values `Xijvar_wideVarname' `thisvallabel'
			* Set variable label.
			if ("`cXijAt`x''"=="1") {
				local wordnum = 2 + `nJValsFound' - `j'
				local jval : word `wordnum' of `jvalsFound'
				label variable `Xijvar_wideVarname' "`jval' `Xijvar_longVarname'"  // If an @ sign was in the stubname, label variable as "<j-value> <longvarname>"
			}
			else {
				local thisvarlabel : variable label `Xijvar_longVarname'
				if (`"`thisvarlabel'"'!="") label variable `Xijvar_wideVarname' `"`thisvarlabel'"'
			}
		}
		if `useif' drop `ifvar'
	}
	* 6G. Finish using storage spaces, ensuring all spaces are freed.
	endStoreVarsUsingPlugin
	* 7. Rename the Xij long variables to the base-j values of the Xij variables (or drop if all missing and requested not to have wide variables that are all missing).
	local nJValues = `nJValsFound'+1
	local x = 0
	foreach Xijvar of local cXij {
		local ++x
		* Get Xij wide variable name, and check it is okay.
		local Xijvar_wideVarname : subinstr local Xijvar "@" `"`basejval'"', count(local nSubs)  // Unicode-compatible in Stata 14.
		if (`nSubs'==0) local Xijvar_wideVarname `Xijvar'`basejval'
		capture confirm new variable `Xijvar_wideVarname'
		if (_rc) {  // An error code of 110 means the variable already exists, or 198 indicates an invalid variable name (that has illegal characters or begins with a number).
			if (_rc==110) giveError 110 "Variable `Xijvar_wideVarname' already exists.  (Are the data already wide?)"
			else if (_rc==1) error 1
			else giveError 198 "invalid wide Xij variable name: `Xijvar_wideVarname'"
		}
		* Get the long variable name and type.
		local Xijvar_longVarname : subinstr local Xijvar "@" `"`catwl'"'  // Unicode-compatible in Stata 14.
		* If creating only those wide variables that would have at least some nonmissing values, check whether this is ever nonmissing.
		if `widevarsNonmissingOnly' {
			local vartype : type `Xijvar_longVarname'
			if (substr("`vartype'",1,3)!="str") capture assert `Xijvar_longVarname'>=., fast
			else capture assert `Xijvar_longVarname'=="", fast
			if (_rc==0) local Xijvar_wideVarname = "."  // Use a wide name of . to mean there is no need to create the variable because it would contain only missing values.
			else if (_rc==1) error 1
		}
		* Rename, or drop if all missing and requested not to create variables that are all missing.
		if ("`Xijvar_wideVarname'"!=".") rename `Xijvar_longVarname' `Xijvar_wideVarname'
		else {
			drop `Xijvar_longVarname'
			continue  // Do not store the variable name below.
		}
		* If this variable was specified using a stubname with @, change the variable label.
		if ("`cXijAt`x''"=="1") label variable `Xijvar_wideVarname' "`basejval' `Xijvar_longVarname'"  // If an @ sign was in the stubname, label variable as "<j-value> <longvarname>"
		* Store the variable name.
		local xijvars_byx_`x' `Xijvar_wideVarname' `xijvars_byx_`x''  // The first j-value's variable goes at the beginning of the list.
		local xijvars_byj_`nJValues' `xijvars_byj_`nJValues'' `Xijvar_wideVarname'  // This gets ordered with later Xij variables later.  Actually this variable is never used, but this line is included for programming clarity.
		if ("`Xijvar_wideVarname'"!=".") local xijvars_bnj_`nJValues' `xijvars_bnj_`nJValues'' `Xijvar_wideVarname'  // Local xijvars_bnj_`nJValues' is similar to xijvars_byj_`nJValues', but excludes periods indicating variables not created.  Actually there should never be any with "." for the base-j, but the if-statement here is for programming clarity.		
	}
	* 8. Store a list of all Xij wide variable names.  Exclude periods that would indicate nonexistent Xij wide variables.
	local allXijWideVarNames = ""
	forvalues j=`nJValues'(-1)1 {  // The j-values were stored with reverse-order numbering, so lower j-values have higher numbers.
		local allXijWideVarNames `allXijWideVarNames' `xijvars_bnj_`j''  // Note use of xijvars_bnj_`j' , not xijvars_byj_`j' , to exclude periods that indicate nonexistent Xij wide variables.
	}
	* 9. Sort observations, and order variables.
	*      Stata's ordering of the Xij variables seems to be to keep the j's in the order the user specified them, and within that to keep the stubnames in the order the long variables appeared in the data.
	sort `ci'
	order `ci' `allXijWideVarNames'
	* 10. Save characteristics.  cXi and catwl are kept from the prior use of reshape, and are not replaced.  cjv is saved only if it was given as an option.
	//if (`newReshapeInfo' & `initXiLen') char _dta[Res_Xi]  // Overwrite previous Xi variables list with null.  Note the lowercase s in this characteristic; this is how Stata keeps this.
	char _dta[Res_Xi]
	char _dta[ReS_Xij] `cXij'
	if (`jvlen') char _dta[ReS_jv] `cjv'
	char _dta[ReS_str] `cstr'
	char _dta[ReS_j] `cj'
	char _dta[ReS_ver] v.2
	char _dta[ReS_i] `ci'
	char _dta[ReS_atwl] `catwl'
	* 11. Return results.
	return scalar N = _N
	return scalar k = c(k)
	return scalar width = c(width)
	return scalar changed = 1
	* 12. Display report about results.
	di "Data                               long   ->   wide"
	di "-----------------------------------------------------------------------------"
	di "Number of obs." _col(32) as result %8.0g `initN' _col(43) as text "->" as result %8.0g _N
	di as text "Number of variables" _col(32) as result %8.0g `initk' _col(43) as text "->" as result %8.0g c(k)
	local jVarAndNVals "j variable (`nJValues' values)"
	local jVarAndNValsLen : length local jVarAndNVals
	local jVarnameLen : length local cj
	local displayString = "`jVarAndNVals'"+(max(0,39-`jVarAndNValsLen'-`jVarnameLen')*" ")+"`cj'"
	local displayStringLen : length local displayString
	local spacesBeforeArrow = max(0, 42 - `displayStringLen')
	local spacesAfterArrow = max(0, 45 - `displayStringLen' - `spacesBeforeArrow')
	di as text ("`jVarAndNVals'"+(max(0,39-`jVarAndNValsLen'-`jVarnameLen')*" ")) as result "`cj'" as text ((`spacesBeforeArrow'*" ")+"->"+(`spacesAfterArrow'*" ")+"(dropped)")
	di as text "xij variables:"
	local x = 0
	foreach Xijvar of local cXijSubstituted {  // This presents info on the Xij variables in the order they appear in the long data, whereas Stata 14.0 uses the order they were listed in the command line, but orders the variables into the order they had in the long data.
		local ++x
		local xijwidevarLast = ""
		local j = 0
		foreach xijwidevar of local xijvars_byx_`x' {
			if ("`xijwidevar'"==".") continue  // Ignore Xij wide variable names if the variables do not exist.  Unlike Stata's built-in command as of 14.0, this does not list nonexistent variables when showing the transformation made.
			local ++j
			if (`j'==1) local xijwideThisX `xijwidevar'
			else if (`j'==2) local xijwideThisX `xijwideThisX' `xijwidevar'
			else local xijwidevarLast `xijwidevar'
		}
		if (`j'==3) local xijwideThisX `xijwideThisX' `xijwidevarLast'
		else local xijwideThisX `xijwideThisX' ... `xijwidevarLast'
		local xijlongThisXLen : length local Xijvar
		if (`xijlongThisXLen'<=39) {  // This if... else... else is not necessary given the current limit of 32 characters in a variable name; just the content within the first "if" would be fine.  However, this coding allows for a possible future increase in max. variable name lengths.
			local startAtCol = 40 - `xijlongThisXLen'
			di _col(`startAtCol') as result "`Xijvar'" _col(43) as text "->" _continue
			local extraSpaceTakenAtLeft = 0
		}
		else if (`xijlongThisXLen'<42) {
			di as result "`Xijvar'" _col(43) as text "->" _continue
			local extraSpaceTakenAtLeft = 0
		}
		else {
			di as result "`Xijvar'" as text "->" _continue
			local extraSpaceTakenAtLeft = `xijlongThisXLen' - 42  // This is the amount of less space than usual to the right of the arrow.
		}
		local Xijwidelen : length local xijwideThisX  // Length of the Xij long variable name.
		local maxspacesok = 33 - `Xijwidelen' - `extraSpaceTakenAtLeft'  // 33 is the number of chars of space to the right of the arrow, allowing 77 total.
		if (`maxspacesok'>0) {
			local colToGoTo = 45 + min(`maxspacesok',3)  // Display up to 3 spaces if there is room without exceeding 77 chars.
			di _col(`colToGoTo') as result "`xijwideThisX'"
		}
		else di as result "`xijwideThisX'"
	}
	di as text "-----------------------------------------------------------------------------"
	* 13. Cancel the previous data preservation.
	if `preserved' restore, not
end

* Since sreshape stores data outside the Stata dataset, the stores should be cleared if there is a break or an unanticipated error (otherwise there would be a memory leak).  This clears the storage areas if necessary whenever exiting with a nonzero return code.
program define runAndEndStoreVarsIfBreak
	version 13
	capture noisily `0'
	nobreak {
		local rcVal = _rc
		if `rcVal' {
			endStoreVarsUsingPlugin
			exit `rcVal'
		}
	}
end

* Check i-variables are valid, when transforming data from wide to long.  Usage: iVarsValid_WideToLong ivarlist
program define iVarsValid_WideToLong, rclass
	version 13
	capture confirm variable `0', exact
	if (_rc==1) error 1
	else if _rc {
		local wc : word count `0'
		if (`wc'==1) giveError 111 "The i varlist is invalid, because the variable specified for i does not exist."
		else giveError 111 "The i varlist is invalid, because one or more of the variables specified for i does not exist."
	}
	capture qbys `0': assert _N==1, fast  // In Stata 13, this is the same as: isid `0'.  However, the isid command did not allow strings variables in some earlier versions of Stata.
	if (_rc==1) error 1
	else if _rc {
		local wc : word count `0'
		if (`wc'==1) return local iuniqerror = `"The i varlist is invalid, because variable `0' does not uniquely identify the observations."'
		else return local iuniqerror = `"The i varlist is invalid, because variables `0' do not uniquely identify the observations."'
		//The following is not used; instead the error message is to be given at the appropriate time by the calling routine.
		// if (`wc'==1) giveError 459 `"The i varlist is invalid, because variable `0' does not uniquely identify the observations."'
		// else giveError 459 `"The i varlist is invalid, because variables `0' do not uniquely identify the observations."'
	}
end

* Given a datatype, return a type number indicating the size of the datatype.
program define getDatatypeNum, rclass
	version 13
	args type
	local str = substr("`type'",1,3)=="str"
	if `str' {  // String type.
		local varSize = real(substr("`type'",4,.))  // So strL has size missing.
		if ("`varSize'"=="." & "`type'"!="strL") giveError 459 "A datatype `type' exists that is unknown to sreshape, apparently because a new version of Stata has introduced the new type.  The sreshape command needs to be reprogrammed to handle variables of this type."
	}
	else {  // Numeric type.
		local d "byte int long float double"  // datatypes
		local varSize : list posof "`type'" in d
		if (`varSize'==0) giveError 459 "A datatype `type' exists that is unknown to sreshape, apparently because a new version of Stata has introduced the new type.  The sreshape command needs to be reprogrammed to handle variables of this type."
	}
	return local tnum = `varSize'
	return local str = `str'
end

* Given a datatype, return a type number indicating the size of the datatype, in the form required by the memVar plugins.
* Types are: -5 double, -4 float, -3 long, -2 int, -1 byte, 0 strL, 1-2045 str# with the type number being #.
program define getDatatypeNumForMemVar, rclass
	version 13
	args type
	local str = substr("`type'",1,3)=="str"
	if `str' {  // String type.
		local varSize = real(substr("`type'",4,.))  // So strL has size missing.
		if ("`varSize'"=="." & "`type'"!="strL") giveError 459 "A datatype `type' exists that is unknown to sreshape, apparently because a new version of Stata has introduced the new type.  The sreshape command needs to be reprogrammed to handle variables of this type."
		if (`varSize'==.) local varSize = 0
	}
	else {  // Numeric type.
		local d "byte int long float double"  // datatypes
		local varSize : list posof "`type'" in d
		if (`varSize'==0) giveError 459 "A datatype `type' exists that is unknown to sreshape, apparently because a new version of Stata has introduced the new type.  The sreshape command needs to be reprogrammed to handle variables of this type."
		local varSize = -`varSize'
	}
	return local memVarTNum = `varSize'
end

* Exit with an error message.
* Example usage: giveError 198 "Error message."  The error message may contain quotation marks, as in: giveError 198 `"What does "expedited" mean?"'
* In Stata 13, this works: giveError _rc "message"   and this works: giveError `=_rc' "message"   but this does NOT work: giveError `_rc' "message"
program define giveError, rclass  // This is rclass to clear out any returned results that have already been generated by functions within sreshape.
	version 13
	gettoken errnum 0 : 0
	gettoken errmsg 0 : 0
	di as error `"`errmsg'"'
	//di in smcl "{search r(`errnum'):r(`errnum');}"  // Not needed if runAndEndStoreVarsIfBreak shows the error number.
	return clear
	exit `errnum'
end

program define giveErrorWithErrnum, rclass  // This is rclass to clear out any returned results that have already been generated by functions within sreshape.
	version 13
	gettoken errnum 0 : 0
	gettoken errmsg 0 : 0
	di as error `"`errmsg'"'
	di in smcl "{search r(`errnum'):r(`errnum');}"
	return clear
	exit `errnum'
end

* initStoreVarUsingPlugin: Prepare to store and retrieve data outside the Stata dataset, using a plugin program or mata code as needed.
* Call this as follows:
*   initStoreVarUsingPlugin , maxstores(#) [futuremanyobs]
* When calling, the maxstores(#) option tells the maximum number of stored chunks of data expected at any one time.  (This upper limit constrains the number of java stores.)
* The futuremanyobs option indicates that the number of observations may grow beyond 2147483647.  If so, information might not be retrievable unless this option is specified.  (The information would not be retrievable if stored using a C plugin, so this prevents storage using a C plugin.)
program define initStoreVarUsingPlugin
	version 13
	// Parse syntax.
	syntax , maxstores(integer) [FUTUREMANYobs mataonly]
	if "`mataonly'"=="" {
		if (`maxstores'<1 | `maxstores'>80000) giveError 198 "maxstores option must be 0 to 80000"
		// Set global variables used to control data storage behavior.
		global sreshape_svup_notc = cond( (_N > 2147483647) | ("`futuremanyobs'"!=""), "notc", "")  // If the number of observations exceeds what the C plugin interface can handle, do not use C plugins.
		//global sreshape_svup_maxvars = `maxstores'  // This constrains the number of concurrent java stores possible.
		capture javacall SreshapeStoreStataDataInJava initMemVarStore , args("`maxstores'")  // This is done with capture because the Java Runtime Environment may not be installed.  Also, if an error code of 9820 is returned, the storage space was already initialized and has been freed.
		if (_rc==9820) giveError 9820 "java storage space was already initialized; maybe initStoreVarUsingPlugin was already called"
		else if (_rc>1) {
			global sreshape_svup_notjava = "notjava"  // Java does not seem to be working.
			global sreshape_svup_javainit = 0  // Java was not initialized.
		}
		else if (_rc==1) error 1
		else {
			global sreshape_svup_notjava = ""  // Java seems to be available.
			global sreshape_svup_javainit = 1  // Java was initialized.
		}
		global sreshape_svup_cstores = ""  // This will contain a list of active storage spaces using C plugins.
		//global sreshape_svup_jstores = ""  // There is no need to track individual stores in java, because they can all be freed in one call.
		global sreshape_svup_mstores = ""  // This will contain a list of active storage spaces using mata.
	}
	else {
		global sreshape_svup_notc = "notc"
		global sreshape_svup_notjava = "notjava"
		global sreshape_svup_javainit = 0  // Java was not initialized.
		global sreshape_svup_cstores = ""
		global sreshape_svup_mstores = ""
	}
end

* storeVarUsingPlugin: Store data, calling a plugin program or mata code as needed to do the storage.
* Call this as follows:
*   storeVarUsingPlugin varname [if varname] [in #/#] , vartypenum(#) [nobssaved(#) favorspace(#)]
*   local infoToAccessStoredData = r(savedDataAccessInfo)
* When calling, the varname specifies the variable whose observations are to be stored.
* The if and in conditions allow only selected observations to have information stored.
* vartypenum(#) indicates the type number of the variable stored; this is required.  -1 = byte, -2 = int, -3 = long, -4 = float, -5 = double, 0 = strL, 1-2045 = str# with this length, -10 = see below.
*   When saving in C, getting this number wrong could cause Stata to crash or could corrupt Stata's memory (including the data).
*     When saving string data in C, it will not be allowed to retrieve the data to a strL variable, only to a str# variable.  If strL retrieval will be needed, use the strlout option.
*   If this is -10, it indicates that the observations are element numbers (1,2,...,nobssaved) in the stored data, with these elements set to 1 and other elements set to 0.  No if-condition may be used.
* Option nobssaved defaults to -1, which means all observations are being saved.  However, if an if-variable is used, this must specify the number of observations being saved.
*   When saving in C, getting this number wrong could cause Stata to crash or could corrupt Stata's memory.  When saving in mata, this number will be ignored.
* Option strlout, if specified, indicates that string data being stored might need to be retrieved into a Stata variable that has type strL.
* Option favorspace(#) indicates to what degree to favor space over speed when storing in mata, 0, 1, 2, 3, or 4.
*   1 causes C or java to be used in preference to mata for storing bytes, ints, longs, floats, and (in C) str# strings.  These are stored using efficient amounts of space in C or java.
*   Higher numbers pertain when storing in mata.
*   Bytes, ints, and longs can be squeezed into strings to save space, for an 8x saving with bytes, 4x with ints, and 2x with longs.
*   However, doing this take more time for ints than for bytes, and it takes longest for longs.
*   Choosing 0 or 1 might be say 20x faster than 2/3/4 when storing bytes in mata, and the speedup by choosing not to squeeze ints and longs is even greater.  However, this is only true if the computer does not need to fall back on virtual memory.
*   4 squeezes all three integer type variables, 3 squeezes bytes and ints only, and 2 squeezes bytes only.
* The returned result r(savedDataAccessInfo) is the key to access the stored data.
* Internally, for most variable types this saves using a C plugin if possible, failing that using a java plugin if possible, or using mata as a last resort.
*   Due to limitations of Stata's plugin interfaces, C cannot be used if #obs>2,147,483,647 or the data type is strL.  Java cannot be used if the data type is str# or strL (since the java
*     plugin interface corrupts some strings), nor if the java runtime environment is not available.
*   Mata is always used to store doubles, as mata may provide a speed advantage and uses space efficiently for doubles.
*   Global sreshape_svup_notc, if set to "notc", prevents use of C plugins.  This must be specified if observation numbers exceeding 2,147,483,647 will be used to store or retrieve data.
*   Global sreshape_svup_notjava, if set to "notjava", prevents use of java plugins.  If the java runtime environment is not available, it is faster to specify this.
program define storeVarUsingPlugin, rclass
	version 13
	// Parse syntax.
	syntax varname [if/] [in/] , VARTypenum(integer) [NOBSsaved(integer -1) STRLout FAVORSPace(integer 0)]
	local iflen : length local if
	if `iflen' {
		capture confirm variable `if'
		if (_rc>1) giveError 198 "if condition must be a single variable"
		else if (_rc==1) error 1
		if (`nobssaved'<0) giveError 198 "nobssaved must be the number of observations being stored if there is an if-variable"
		if (`vartypenum'==-10) giveError 198 "if condition not allowed with alternate storage method (variable type -10)"
	}
	else if (`nobssaved'>=0 & `vartypenum'!=-10) giveError 198 "use nobssaved>=0 only if there is an if-variable, or with alternate storage method (variable type -10)"
	local inlen : length local in
	if `inlen' {
		gettoken inObs1 rest : in, parse("/")
		gettoken slash inObs2 : rest, parse("/")
	}
	else {
		local inObs1 = 1
		local inObs2 = _N
	}
	local typeIsStrL = `vartypenum'==0
	local typeIsStr = `vartypenum'>=0
	local mayusec = `favorspace' & ("$sreshape_svup_notc"=="") & (!`typeIsStrL') & (_N<=2147483646)  // Upper limit on number of observations seems to be 2147483646, not 2147483647 as one would expect, my tests show.
	local mayusejava = `favorspace' & ("$sreshape_svup_notjava"=="")
	// Store data.
	local savedDataAccessInfo = ""
	local javaRuntimeEnvWasAvailable = .
	if `mayusec' & `vartypenum'>-5 {
		// Use C plugin.
		if (`nobssaved'==-1 | `vartypenum'==-10) capture plugin call sreshapeMemVarFromStataVar `varlist' in `inObs1'/`inObs2', "_storageLoc" "`vartypenum'" "-1"
		else capture plugin call sreshapeMemVarFromStataVar `varlist' if `if' in `inObs1'/`inObs2', "_storageLoc" "`vartypenum'" "`nobssaved'"
		if (_rc==0) {
			local savedDataAccessInfo = "C `storageLoc'"
			global sreshape_svup_cstores $sreshape_svup_cstores `storageLoc'
		}
		else if (_rc==1) error 1
		else global sreshape_svup_notc = "notc"
	}
	if `mayusejava' & (!`typeIsStr') & ("`savedDataAccessInfo'"=="") & `vartypenum'>-5 {
		// Try to use java plugin.  (Note, java was introduced in Stata 13.)
		if (`nobssaved'==-1 | `vartypenum'==-10) capture javacall SreshapeStoreStataDataInJava sreshapeMemVarFromStataVar `varlist' in `inObs1'/`inObs2', args("_storageLoc" "`vartypenum'" "-1")
		else capture javacall SreshapeStoreStataDataInJava sreshapeMemVarFromStataVar `varlist' if `if' in `inObs1'/`inObs2', args("_storageLoc" "`vartypenum'" "`nobssaved'")
		if (_rc==0) {
			local savedDataAccessInfo = "j `storageLoc'"
			//global sreshape_svup_jstores $sreshape_svup_jstores `storageLoc'  // There is no need to track individual stores in java, because they can all be freed in one call.
		}
		else if (_rc==1) error 1
		else global sreshape_svup_notjava = "notjava"
	}
	if ("`savedDataAccessInfo'"=="") {
		// Use mata.
		mata: StoreStataDataInMata("`varlist'", `vartypenum', `nobssaved', "`if'", `inObs1', `inObs2', `favorspace')
		if (`vartypenum'==-10) local vartypenum = -1  // -10 indicates to use an alternate method to store byte data.  The stored data should be accessed as byte.
		global storeVarUsingPlugin_NextMStore = cond("$storeVarUsingPlugin_NextMStore"=="", 1, $storeVarUsingPlugin_NextMStore + 1)
		mata: mata rename sreshapeStore_out sreshapeStore_out$storeVarUsingPlugin_NextMStore
		local storageLoc `vartypenum',`favorspace',$storeVarUsingPlugin_NextMStore
		local savedDataAccessInfo = "m `storageLoc'"
		global sreshape_svup_mstores $sreshape_svup_mstores `storageLoc'
	}
	// Return results.
	return clear
	return local savedDataAccessInfo "`savedDataAccessInfo'"
end

* retrieveVarUsingPlugin: Retrieve data stored using storeVarUsingPlugin, calling a plugin program or mata code as needed to do the retrieval.
* Call this as follows:
*   retrieveVarUsingPlugin varname [if varname] [in] , VARTypenum(integer) ACCessinfo(string) [NOBSsaved(integer -1) FREEram]
* When calling, the varname specifies the variable whose observations are to be set.
* The if and in conditions allow only selected observations to have information set.
*   THE IF-VARNAME IS CURRENTLY SUPPORTED ONLY IF THE DATA WERE STORED USING C OR MATA (C STILL TO BE TESTED).
* vartypenum(#) indicates the type number of the variable being set; this is required.  -1 = byte, -2 = int, -3 = long, -4 = float, -5 = double, 0 = strL, 1-2045 = str# with this length.
* accessinfo(string) is required, and is where you provide the key to access the stored data, as previously returned by storeVarUsingPlugin in r(savedDataAccessInfo).
* Option freeram, if specified, causes the stored information to be deleted after retrieving it.  All stored information should be freed to avoid memory loss.
program define retrieveVarUsingPlugin
	version 13
	// Parse syntax.
	syntax varname [if/] [in/] , VARTypenum(integer) ACCessinfo(string) [FREEram]
	local iflen : length local if
	if `iflen' {
		capture confirm variable `if'
		if (_rc>1) giveError 198 "if condition must be a single variable"
		else if (_rc==1) error 1
	}
	local inlen : length local in
	if `inlen' {
		gettoken inObs1 rest : in, parse("/")
		gettoken slash inObs2 : rest, parse("/")
	}
	else {
		local inObs1 = 1
		local inObs2 = _N
	}
	gettoken cJOrM accessloc : accessinfo  // cJOrM tells whether the data were stored using a C plugin (C), java plugin (j), or mata (m); accessloc is the information needed for access in C, java, or mata.
	//                                        The accessloc for C is a numeric memory address, for java is an element number in an array, or for mata is two integers separated by a comma: storedVarType,storageLocInMata.
	local accessloc `accessloc'  // This strips off a possible leading space in accessloc.
	local freeRamWhenDone = "`freeram'"=="freeram"
	// Retrieve data.
	if "`cJOrM'"=="C" {
		if (`vartypenum'==0) giveError 999 "strL cannot be written from data saved in C plugin (because C plugin interface does not handle strL's)"
		if (`iflen') plugin call sreshapeMemVarToStataVar `varlist' if `if' in `inObs1'/`inObs2', "`accessloc'" "`vartypenum'" "`freeRamWhenDone'" "if"
		else plugin call sreshapeMemVarToStataVar `varlist' in `inObs1'/`inObs2', "`accessloc'" "`vartypenum'" "`freeRamWhenDone'"
		if `freeRamWhenDone' global sreshape_svup_cstores : list global(sreshape_svup_cstores) - accessloc
	}
	else if "`cJOrM'"=="j" {
		if (`iflen') javacall SreshapeStoreStataDataInJava sreshapeMemVarToStataVar `varlist' if `if' in `inObs1'/`inObs2', args("`accessloc'" "`vartypenum'" "`freeRamWhenDone'" "if")
		else javacall SreshapeStoreStataDataInJava sreshapeMemVarToStataVar `varlist' in `inObs1'/`inObs2', args("`accessloc'" "`vartypenum'" "`freeRamWhenDone'")
		//if `freeRamWhenDone' global sreshape_svup_jstores : list global(sreshape_svup_jstores) - accessloc  // There is no need to track individual stores in java, because they can all be freed in one call.
	}
	else if "`cJOrM'"=="m" {
		gettoken storedVarType rest : accessloc, parse(",")
		gettoken shouldBeComma rest : rest, parse(",")
		if ("`shouldBeComma'"!=",") giveError 999 "Invalid accessloc, which, for stored mata data, should be of the form '<datatypenum>,<favoredSpaceOverSpeed>,<storagenum>'."
		gettoken favoredSpaceOverSpeed rest : rest, parse(",")
		gettoken shouldBeComma storageLocInMata : rest, parse(",")
		if ("`shouldBeComma'"!=",") giveError 999 "Invalid accessloc, which, for stored mata data, should be of the form '<datatypenum>,<favoredSpaceOverSpeed>,<storagenum>'."
		mata : mata rename sreshapeStore_out`storageLocInMata' sreshapeRetrieve_in
		mata: RetrieveStataDataFromMata("`varlist'", `vartypenum', "`if'", `storedVarType', `inObs1', `inObs2', `favoredSpaceOverSpeed')
		if (`freeRamWhenDone'==1) {
			mata: mata drop sreshapeRetrieve_in
			global sreshape_svup_mstores : list global(sreshape_svup_mstores) - accessloc
		}
		else mata : mata rename sreshapeRetrieve_in sreshapeStore_out`storageLocInMata'
	}
	else giveError 999 "Bad accessinfo when calling retrieveVarUsingPlugin (cJOrM must be C or j or m)."
end

* Free a single storage space filled using storeVarUsingPlugin.
program define freeVarUsingPlugin
	version 13
	// Parse syntax.
	syntax , ACCessinfo(string)
	gettoken cJOrM accessloc : accessinfo  // cJOrM tells whether the data were stored using a C plugin (C), java plugin (j), or mata (m); accessloc is the information needed for access in C, java, or mata.
	//                                        The accessloc for C is a numeric memory address, for java is an element number in an array, or for mata is two integers separated by a comma: storedVarType,storageLocInMata.
	local accessloc `accessloc'  // This strips off a possible leading space in accessloc.
	// Free RAM.
	if "`cJOrM'"=="C" {
		plugin call sreshapeMemVarFree , "`accessloc'"
	}
	else if "`cJOrM'"=="j" {
		javacall SreshapeStoreStataDataInJava sreshapeMemVarFree , args("`accessloc'")
	}
	else if "`cJOrM'"=="m" {
		gettoken storedVarType rest : accessloc, parse(",")
		gettoken shouldBeComma rest : rest, parse(",")
		if ("`shouldBeComma'"!=",") giveError 999 "Invalid accessloc, which, for stored mata data, should be of the form '<datatypenum>,<favoredSpaceOverSpeed>,<storagenum>'."
		gettoken favoredSpaceOverSpeed rest : rest, parse(",")
		gettoken shouldBeComma storageLocInMata : rest, parse(",")
		if ("`shouldBeComma'"!=",") giveError 999 "Invalid accessloc, which, for stored mata data, should be of the form '<datatypenum>,<favoredSpaceOverSpeed>,<storagenum>'."
		mata : mata drop sreshapeStore_out`storageLocInMata'
	}
	else giveError 999 "Bad accessinfo when calling freeVarUsingPlugin (cJOrM must be C or j or m)."
end

* endStoreVarsUsingPlugin: Free all storage spaces and clean out system to store data outside the Stata dataset.
* Call this as follows:
*   endStoreVarsUsingPlugin
* This must be called at the end, to ensure RAM with stored data spaces is freed.
program define endStoreVarsUsingPlugin
	version 13
	// Free C stores.
	nobreak {  // The records of what is or is not stored in C should be kept straight, since calling C code to free memory that's already freed could conceivably cause a crash.
		foreach s of global sreshape_svup_cstores {
			plugin call sreshapeMemVarFree , "`s'"
		}
		global sreshape_svup_cstores = ""
	}
	// Free java stores and java store array.
	if "$sreshape_svup_javainit"=="1" {
		capture javacall SreshapeStoreStataDataInJava freeMemVarStore
		if (_rc>1) di as error "warning: unable to free java storage space created"
		//else if (_rc==1) error 1  // Do not allow break key usage in this routine.
		else global sreshape_svup_javainit = ""
	}
	global sreshape_svup_javainit = ""
	// Free mata stores.
	capture mata : mata drop sreshapeStore_out*
	capture mata : mata drop sreshapeRetrieve_in
	global sreshape_svup_mstores = ""
	// Clear out globals used in this system.
	global sreshape_svup_notc = ""
	global sreshape_svup_notjava = ""
end

* Define C plugin programs.  Using them requires that the plugin be available for the platform.  Uncomment below to allow use.
//program sreshapeMemVarFromStataVar, plugin
//program sreshapeMemVarToStataVar, plugin
//program sreshapeMemVarFree, plugin




* Mata code.  

version 13
mata:
//mata set matalnum on  // DEBUG - This line turns on Mata line numbers in error messages, but turns off Mata optimization, so this line should be removed for general use.
mata set matastrict on


// MATA PART 1 : MATA FUNCTIONS FOR MAIN USE.

// Given the name of a variable whose values are sorted, this determines the first observation with a value the same as in the last observation.
//   This ASSUMES that the last observation is NOT the same as the first observation.  If it is, and the last observation is missing, this will enter an (almost) infinite loop.
//     In my usage, I am never calling this when the last observation is the same as the first observation.
//   I.e., after "sort j", this starts from the last observation and looks in previous observations to find where j[obsnum]!=j[_N], and returns obsnum+1.
// findFirstObsWithLastValIfSorted(varname) returns r(firstObsWithLastVal), a numeric scalar.
void findFirstObsWithLastValIfSorted(string scalar pVarName) {
	real scalar varIndex, obsNum, lastValN
	string scalar lastValS
	varIndex = st_varindex(pVarName)
	obsNum = st_nobs()
	if (st_isnumvar(varIndex)) {  // The variable is numeric.
		lastValN = _st_data(obsNum,varIndex)
		do {
			obsNum--;
		} while (_st_data(obsNum,varIndex)==lastValN)
	}
	else {  // The variable is string.
		lastValS = _st_sdata(obsNum,varIndex)
		do {
			obsNum--;
		} while (_st_sdata(obsNum,varIndex)==lastValS)
	}
	st_rclear()
	st_numscalar("r(firstObsWithLastVal)", obsNum+1)
}

// Minimum value, i.e., lowest by sort order, of string variable, returned in r(minStr).
// The variable does not need to be in any particular order.
// If the answer is the null string, r(minStr) will retrieve the correct value but will not be listed in a return list.
// (Char-0's might not be represented right in returned macros?  But I am only using this for j-values, which are not permitted to contain char-0s.)
void minValOfStringVar(string scalar pVarName)
{
	real scalar nobs, varIndex, i
	string scalar minstr
	nobs = st_nobs()
	varIndex = st_varindex(pVarName)
	minstr = _st_sdata(1,varIndex)
	for(i=2; i<=nobs; i++) {
		if (_st_sdata(i,varIndex) < minstr) minstr = _st_sdata(i,varIndex)
	}
	st_rclear()
	st_global("r(minStr)",minstr)
}



// MATA PART 2 : MATA FUNCTIONS TO ALLOW TEMPORARY STORAGE OF STATA DATA IN MATA VARIABLES.

// Store data in mata.
void StoreStataDataInMata(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
//printf("StoreStataDataInMata: pVarName=%s, pVarTypeNum=%g, pNObsSaved=%g, pSaveIfVar=%s, pInObs1=%g, pInObs2=%g, favorSpaceOverSpeed=%g.\n", pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
	if (pVarTypeNum==-10 & favorSpaceOverSpeed>1) StoreStataDataInMata_AltByte(pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
	else if (pVarTypeNum==-10) StoreStataDataInMata_AltReal(pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
	else if (pVarTypeNum==-1 & favorSpaceOverSpeed>1) StoreStataDataInMata_Byte(pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
	else if (pVarTypeNum==-2 & favorSpaceOverSpeed>2) StoreStataDataInMata_Int(pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
	else if (pVarTypeNum==-3 & favorSpaceOverSpeed>3) StoreStataDataInMata_Long(pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
	else if (pVarTypeNum<0) StoreStataDataInMata_Real(pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
	else StoreStataDataInMata_String(pVarName, pVarTypeNum, pNObsSaved, pSaveIfVar, pInObs1, pInObs2, favorSpaceOverSpeed)
}

// Store Stata data in mata, using alternate storage method, to store 0-1 byte data given element numbers of 1s.
//   This stores using strings.  No if-var is used, even if one was specified.
void StoreStataDataInMata_AltByte(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
	external string sreshapeStore_out
	real scalar tDataSortedLength, tBufferLength, tDatumNum, tDatum, tOffset, tBufferPosition
	real rowvector tBuffer
	real colvector tDataSorted
	// Load the Stata data into a mata variable.
	// Storing bytes, which are converted to a string of characters to save space.
	if (pVarTypeNum!=-10) _error("Programmer's error - StoreStataDataInMata_AltByte must have dataType = -10.")  // DEBUG
	if (pNObsSaved<0) _error("Programmer's error - StoreStataDataInMata_AltByte (with dataType = -10) must be called with pNObsSaved>0 indicating number of obs stored.")  // DEBUG
	tDataSorted = sort( st_data((pInObs1,pInObs2),pVarName), 1 )
	tDataSortedLength = rows(tDataSorted)
	sreshapeStore_out = ""
	tBufferLength = min((pNObsSaved,25000))
	tBuffer = J(1,tBufferLength,127)  // 0 is represented as 127.
	tOffset = 0
	for(tDatumNum=1; tDatumNum<=tDataSortedLength; tDatumNum++) {
		tDatum = tDataSorted[tDatumNum]
		if (tDatum<.) {  // Data with missing values are ignored.
			tBufferPosition = tDatum - tOffset  // Position within the buffer.
			while (tBufferPosition > tBufferLength) {
				// Write buffer and reinitialize the buffer, preparing to deal with the datum in a later buffer.
				sreshapeStore_out = sreshapeStore_out + char(tBuffer)  // Write buffer.
				tOffset = tOffset + tBufferLength  // This many characters in the string of resulting characters have already been dealt with, and we need to be able to compute the c-th character AFTER what's been dealt with.
				tBufferPosition = tDatum - tOffset  // Position within the new (about to be made) buffer.
				tBufferLength = min((pNObsSaved - tOffset,25000))
				tBuffer = J(1,tBufferLength,127)  // 0 is represented as 127.
			}
			tBuffer[tBufferPosition] = 128  // 1 is represented as 128.
		}
	}
	while (tOffset<pNObsSaved) {
		// Write buffer, and point to next buffer-full of zeros if any.
		sreshapeStore_out = sreshapeStore_out + char(tBuffer)  // Write buffer.
		tOffset = tOffset + tBufferLength
		tBufferLength = min((pNObsSaved - tOffset,25000))
		tBuffer = J(1,tBufferLength,127)  // 0 is represented as 127.
	}
}
// Store Stata data in mata, using alternate storage method, to store 0-1 byte data given element numbers of 1s.
//   This stores using an array of doubles.  No if-var is used, even if one was specified.
void StoreStataDataInMata_AltReal(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
	real scalar tVarIndex, tObsNum, tDatum
	external real colvector sreshapeStore_out
	// Load the Stata data into a mata variable.
	if (pVarTypeNum!=-10) _error("Programmer's error - StoreStataDataInMata_AltByte must have dataType = -10.")  // DEBUG
	if (pNObsSaved<0) _error("Programmer's error - StoreStataDataInMata_AltByte (with dataType = -10) must be called with pNObsSaved>0 indicating number of obs stored.")  // DEBUG
	tVarIndex = st_varindex(pVarName)
	sreshapeStore_out = J(pNObsSaved,1,0)  // Initialize with zeros.
	for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
		tDatum = _st_data(tObsNum,tVarIndex)
		if (tDatum<.) sreshapeStore_out[tDatum] = 1
	}
}
// Store Stata data in mata, for stored byte data.
//   This stores using strings.
void StoreStataDataInMata_Byte(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
	external string sreshapeStore_out
	real scalar tVarIndex, tSaveIfVarIndex, tObsNum, tBufferLength, tBufferPosition
	real rowvector tBuffer
	// Load the Stata data into a mata variable.
	// Storing bytes, which are converted to a string of characters to save space.  This is about 10-25 times slower than just saving the data into an array of doubles, but at least RAM shortage is unlikely to occur.
	//   The use of a buffer here is critical to speed this up: values to be written are held in a numeric array and only periodically converted to a string and appended to the larger string.
	//   When I first tried this without a buffer, appending to the strings took around 1 2/3 minutes for 1,500,027 observations.  With a 25,000-element buffer, it happens in about 0.5-0.6 seconds (approx. timings: with a 500-element buffer 1.05 seconds; with a 1000-element buffer 1.1 seconds; with a 5,000-element buffer 0.6-0.7 seconds; with a 10,000-element buffer 0.58 seconds; with a 50,000-element buffer 0.5 seconds; with 500,000-element buffer 0.5 seconds).
	//   I am afraid to increase the buffer size too much, because a 25,000-element buffer already takes 200K bytes and this should easily fit in on-chip cache for optimal performance.
	sreshapeStore_out = ""
	tVarIndex = st_varindex(pVarName)
	if (pNObsSaved<0) tBufferLength = min((pInObs2-pInObs1+1,25000))
	else tBufferLength = min((pNObsSaved,25000))
	tBuffer = J(1,tBufferLength,.)
	tBufferPosition = 1
	if (pSaveIfVar!="") {
		tSaveIfVarIndex = st_varindex(pSaveIfVar)
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			if (_st_data(tObsNum,tSaveIfVarIndex)) {
				tBuffer[tBufferPosition++] = byteValTo0to255(_st_data(tObsNum,tVarIndex))
				if (tBufferPosition>tBufferLength) {
					sreshapeStore_out = sreshapeStore_out + char(tBuffer)
					tBufferPosition = 1
				}
			}
		}
	}
	else {
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			tBuffer[tBufferPosition++] = byteValTo0to255(_st_data(tObsNum,tVarIndex))
			if (tBufferPosition>tBufferLength) {
				sreshapeStore_out = sreshapeStore_out + char(tBuffer)
				tBufferPosition = 1
			}
		}
	}
	if (tBufferPosition>1) {
		sreshapeStore_out = sreshapeStore_out + char(tBuffer[|1\(tBufferPosition-1)|])
	}
}
// Store data in mata, for stored int data.
//   This stores using strings.  I have not yet programmed for more than 140,737,488,355,327 observations.  To allow this, need to allow 2 different strings.
void StoreStataDataInMata_Int(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
	external string sreshapeStore_out
	real scalar tVarIndex, tNObsSaved, tSaveIfVarIndex, tObsNum, tBufferLength, tBufferPosition, valConverted, valHighByte, valLowByte
	real rowvector tBuffer
	// Storing ints, which are converted to a string of characters to save space.  This is much slower than just saving the data into an array of doubles, but at least RAM shortage is unlikely to occur.
	//   The use of a buffer here is critical to speed this up: values to be written are held in a numeric array and only periodically converted to a string and appended to the larger string.
	sreshapeStore_out = ""
	tVarIndex = st_varindex(pVarName)
	tNObsSaved = ( pNObsSaved<0 ? pInObs2-pInObs1+1 : pNObsSaved )
	if (tNObsSaved>140737488355327) _error("Not yet programmed for storing over 140,737,488,355,327 int observations in mata when favoring space over speed.")
	tBufferLength = min((2*tNObsSaved,50000))  // This MUST be a multiple of 2.
	tBuffer = J(1,tBufferLength,.)
	tBufferPosition = 1
	if (pSaveIfVar!="") {
		tSaveIfVarIndex = st_varindex(pSaveIfVar)
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			if (_st_data(tObsNum,tSaveIfVarIndex)) {
				valConverted = intValTo0to65535(_st_data(tObsNum,tVarIndex))
				valHighByte = trunc(valConverted/256)
				valLowByte = valConverted - 256*valHighByte
				tBuffer[tBufferPosition++] = valLowByte
				tBuffer[tBufferPosition++] = valHighByte
				if (tBufferPosition>tBufferLength) {
					sreshapeStore_out = sreshapeStore_out + char(tBuffer)
					tBufferPosition = 1
				}
			}
		}
	}
	else {
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			valConverted = intValTo0to65535(_st_data(tObsNum,tVarIndex))
			valHighByte = trunc(valConverted/256)
			valLowByte = valConverted - 256*valHighByte
			tBuffer[tBufferPosition++] = valLowByte
			tBuffer[tBufferPosition++] = valHighByte
			if (tBufferPosition>tBufferLength) {
				sreshapeStore_out = sreshapeStore_out + char(tBuffer)
				tBufferPosition = 1
			}
		}
	}
	if (tBufferPosition>1) {
		sreshapeStore_out = sreshapeStore_out + char(tBuffer[|1\(tBufferPosition-1)|])
	}
}
// Store data in mata, for stored long data.
//   This stores using strings.  I have not yet programmed for more than 140,737,488,355,327 observations.  To allow this, need to allow 2 different strings.
void StoreStataDataInMata_Long(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
	external string sreshapeStore_out
	real scalar tVarIndex, tNObsSaved, tSaveIfVarIndex, tObsNum, tBufferLength, tBufferPosition, valConverted, valBytes234, valByte1, valBytes34, valByte2, valByte3, valByte4
	real rowvector tBuffer
	// Storing longs, which are converted to a string of characters to save space.  This is much slower than just saving the data into an array of doubles, but at least RAM shortage is unlikely to occur.
	//   The use of a buffer here is critical to speed this up: values to be written are held in a numeric array and only periodically converted to a string and appended to the larger string.
	sreshapeStore_out = ""
	tVarIndex = st_varindex(pVarName)
	tNObsSaved = ( pNObsSaved<0 ? pInObs2-pInObs1+1 : pNObsSaved )
	if (tNObsSaved>70368744177663) _error("Not yet programmed for storing over 70,368,744,177,663 long observations in mata when favoring space over speed.")
	tBufferLength = min((4*tNObsSaved,100000))  // This MUST be a multiple of 4.
	tBuffer = J(1,tBufferLength,.)
	tBufferPosition = 1
	if (pSaveIfVar!="") {
		tSaveIfVarIndex = st_varindex(pSaveIfVar)
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			if (_st_data(tObsNum,tSaveIfVarIndex)) {
				valConverted = longValTo0to4294967295(_st_data(tObsNum,tVarIndex))
				valBytes234 = trunc(valConverted/256)
				valByte1 = valConverted - 256*valBytes234
				valBytes34 = trunc(valBytes234/256)
				valByte2 = valBytes234 - 256*valBytes34
				valByte4 = trunc(valBytes34/256)
				valByte3 = valBytes34 - 256*valByte4
				tBuffer[tBufferPosition++] = valByte1
				tBuffer[tBufferPosition++] = valByte2
				tBuffer[tBufferPosition++] = valByte3
				tBuffer[tBufferPosition++] = valByte4
				if (tBufferPosition>tBufferLength) {
					sreshapeStore_out = sreshapeStore_out + char(tBuffer)
					tBufferPosition = 1
				}
			}
		}
	}
	else {
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			valConverted = longValTo0to4294967295(_st_data(tObsNum,tVarIndex))
			valBytes234 = trunc(valConverted/256)
			valByte1 = valConverted - 256*valBytes234
			valBytes34 = trunc(valBytes234/256)
			valByte2 = valBytes234 - 256*valBytes34
			valByte4 = trunc(valBytes34/256)
			valByte3 = valBytes34 - 256*valByte4
			tBuffer[tBufferPosition++] = valByte1
			tBuffer[tBufferPosition++] = valByte2
			tBuffer[tBufferPosition++] = valByte3
			tBuffer[tBufferPosition++] = valByte4
			if (tBufferPosition>tBufferLength) {
				sreshapeStore_out = sreshapeStore_out + char(tBuffer)
				tBufferPosition = 1
			}
		}
	}
	if (tBufferPosition>1) {
		sreshapeStore_out = sreshapeStore_out + char(tBuffer[|1\(tBufferPosition-1)|])
	}
}
// Store data in mata, for stored real values.
//   For any kind of real, this uses a mata colvector of doubles.
void StoreStataDataInMata_Real(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
	external real colvector sreshapeStore_out
	// Load the Stata data into a mata variable.
	sreshapeStore_out = st_data((pInObs1,pInObs2),pVarName,pSaveIfVar)
}
// Store data in mata, for stored string values.
//   For any kind of string, this uses a mata colvector of strings.
void StoreStataDataInMata_String(string scalar pVarName, real scalar pVarTypeNum, real scalar pNObsSaved, string scalar pSaveIfVar, real scalar pInObs1, real scalar pInObs2, real scalar favorSpaceOverSpeed)
{
	external string colvector sreshapeStore_out
	// Load the Stata data into a mata variable.
	sreshapeStore_out = st_sdata((pInObs1,pInObs2),pVarName,pSaveIfVar)
}


void RetrieveStataDataFromMata(string scalar pVarName, real scalar pVarTypeNum, string scalar pRetrieveIfVar, real scalar pStoredDataTypeNum, real scalar pInObs1, real scalar pInObs2, real scalar pFavoredSpaceOverSpeed)
{
//printf("RetrieveStataDataFromMata: pVarName=%s, pVarTypeNum=%g, pRetrieveIfVar=%s, pStoredDataTypeNum=%g, pInObs1=%g, pInObs2=%g, pFavoredSpaceOverSpeed=%g.\n", pVarName, pVarTypeNum, pRetrieveIfVar, pStoredDataTypeNum, pInObs1, pInObs2, pFavoredSpaceOverSpeed)
	if (pStoredDataTypeNum==-1 & pFavoredSpaceOverSpeed>1) RetrieveStataDataFromMata_Byte(pVarName, pVarTypeNum, pRetrieveIfVar, pStoredDataTypeNum, pInObs1, pInObs2)
	else if (pStoredDataTypeNum==-2 & pFavoredSpaceOverSpeed>2) RetrieveStataDataFromMata_Int(pVarName, pVarTypeNum, pRetrieveIfVar, pStoredDataTypeNum, pInObs1, pInObs2)
	else if (pStoredDataTypeNum==-3 & pFavoredSpaceOverSpeed>3) RetrieveStataDataFromMata_Long(pVarName, pVarTypeNum, pRetrieveIfVar, pStoredDataTypeNum, pInObs1, pInObs2)
	else if (pStoredDataTypeNum<0) RetrieveStataDataFromMata_Real(pVarName, pVarTypeNum, pRetrieveIfVar, pStoredDataTypeNum, pInObs1, pInObs2)
	else RetrieveStataDataFromMata_Str(pVarName, pVarTypeNum, pRetrieveIfVar, pStoredDataTypeNum, pInObs1, pInObs2)
}

// Retrieve data from mata, for stored byte data.
void RetrieveStataDataFromMata_Byte(string scalar pVarName, real scalar pVarTypeNum, string scalar pRetrieveIfVar, real scalar pStoredDataTypeNum, real scalar pInObs1, real scalar pInObs2)
{
	external string sreshapeRetrieve_in
	real scalar tVarIndex, tRetrieveIfVarIndex, charWithinStorageStr, tObsNum, val0to255
	// Confirm byte data.
	assert(pStoredDataTypeNum==-1)
	// Retrieve the Stata data from a mata variable.  Bytes were stored as a string of characters.
	tVarIndex = st_varindex(pVarName)
	charWithinStorageStr = 1
	if (pRetrieveIfVar!="") {
		tRetrieveIfVarIndex = st_varindex(pRetrieveIfVar)
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			if (_st_data(tObsNum,tRetrieveIfVarIndex)) {
				val0to255 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
				_st_store(tObsNum,tVarIndex,from0to255ToByteVal(val0to255))
			}
		}
	}
	else {
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			val0to255 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
			_st_store(tObsNum,tVarIndex,from0to255ToByteVal(val0to255))
		}
	}
}
// Retrieve data from mata, for stored int data.
void RetrieveStataDataFromMata_Int(string scalar pVarName, real scalar pVarTypeNum, string scalar pRetrieveIfVar, real scalar pStoredDataTypeNum, real scalar pInObs1, real scalar pInObs2)
{
	external string sreshapeRetrieve_in
	real scalar tVarIndex, tRetrieveIfVarIndex, charWithinStorageStr, tObsNum, valLowByte, valHighByte, valConverted
	assert(pStoredDataTypeNum==-2)  // Confirm int stored data.
	// Retrieve the Stata data from a mata variable.  Ints were stored as a string of characters.
	tVarIndex = st_varindex(pVarName)
	charWithinStorageStr = 1
	if (pRetrieveIfVar!="") {
		tRetrieveIfVarIndex = st_varindex(pRetrieveIfVar)
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			if (_st_data(tObsNum,tRetrieveIfVarIndex)) {
				valLowByte = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
				valHighByte = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
				valConverted = 256*valHighByte + valLowByte
				_st_store(tObsNum,tVarIndex,from0to65535ToIntVal(valConverted))
			}
		}
	}
	else {
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			valLowByte = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
			valHighByte = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
			valConverted = 256*valHighByte + valLowByte
			_st_store(tObsNum,tVarIndex,from0to65535ToIntVal(valConverted))
		}
	}
}
// Retrieve data from mata, for stored long data.
void RetrieveStataDataFromMata_Long(string scalar pVarName, real scalar pVarTypeNum, string scalar pRetrieveIfVar, real scalar pStoredDataTypeNum, real scalar pInObs1, real scalar pInObs2)
{
	external string sreshapeRetrieve_in
	real scalar tVarIndex, tRetrieveIfVarIndex, charWithinStorageStr, tObsNum, valByte1, valByte2, valByte3, valByte4, valConverted
	assert(pStoredDataTypeNum==-3)  // long int stored data.
	// Retrieve the Stata data from a mata variable.  Ints were stored as a string of characters.
	tVarIndex = st_varindex(pVarName)
	charWithinStorageStr = 1
	if (pRetrieveIfVar!="") {
		tRetrieveIfVarIndex = st_varindex(pRetrieveIfVar)
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			if (_st_data(tObsNum,tRetrieveIfVarIndex)) {
				valByte1 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
				valByte2 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
				valByte3 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
				valByte4 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
				valConverted = 16777216*valByte4 + 65536*valByte3 + 256*valByte2 + valByte1
				_st_store(tObsNum,tVarIndex,from0to4294967295ToLongVal(valConverted))
			}
		}
	}
	else {
		for(tObsNum=pInObs1; tObsNum<=pInObs2; tObsNum++) {
			valByte1 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
			valByte2 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
			valByte3 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
			valByte4 = ascii(substr(sreshapeRetrieve_in,charWithinStorageStr++,1))
			valConverted = 16777216*valByte4 + 65536*valByte3 + 256*valByte2 + valByte1
			_st_store(tObsNum,tVarIndex,from0to4294967295ToLongVal(valConverted))
		}
	}
}
// Retrieve data from mata, for stored real data.
void RetrieveStataDataFromMata_Real(string scalar pVarName, real scalar pVarTypeNum, string scalar pRetrieveIfVar, real scalar pStoredDataTypeNum, real scalar pInObs1, real scalar pInObs2)
{
	external real colvector sreshapeRetrieve_in
	assert(pStoredDataTypeNum<0)  // Confirm real stored data.
	st_store((pInObs1,pInObs2),pVarName,pRetrieveIfVar,sreshapeRetrieve_in)  // Retrieve the Stata data from a mata variable.
}
// Retrieve data from mata, for stored str# or strL data.
void RetrieveStataDataFromMata_Str(string scalar pVarName, real scalar pVarTypeNum, string scalar pRetrieveIfVar, real scalar pStoredDataTypeNum, real scalar pInObs1, real scalar pInObs2)
{
	external string colvector sreshapeRetrieve_in
	assert(pStoredDataTypeNum>=0)  // Confirm str# or strL stored data.
	st_sstore((pInObs1,pInObs2),pVarName,pRetrieveIfVar,sreshapeRetrieve_in)  // Retrieve the Stata data from a mata variable.
}

// Convert byte number with possible missing value codes and negative values to a number 0 to 255.
real scalar byteValTo0to255(real scalar valueFromAStataByte) {
	if (valueFromAStataByte<.) return(valueFromAStataByte+127)
	else if (valueFromAStataByte==.) return(228)
	else if (valueFromAStataByte<=.m) {  // .a to .m
		if (valueFromAStataByte<=.f) {
			if (valueFromAStataByte<=.c) {  // .a to .c
				if (valueFromAStataByte==.a) return(229)  // .a
				else if (valueFromAStataByte==.b) return(230)  // .b
				else return(231)  // .c
			}
			else {  // .d to .f
				if (valueFromAStataByte==.d) return(232)  // .d
				else if (valueFromAStataByte==.e) return(233)  // .e
				else return(234)  // .f
			}
		}
		else {  // .g to .m
			if (valueFromAStataByte<=.j) {  // .g to .j
				if (valueFromAStataByte<=.h) {  // .g to .h
					if (valueFromAStataByte==.g) return(235)  // .g
					else return(236)  // .h
				}
				else if (valueFromAStataByte==.i) return(237)  // .i
				else return(238)  // .j
			}
			else {  // .k to .m
				if (valueFromAStataByte==.k) return(239)  // .k
				else if (valueFromAStataByte==.l) return(240)  // .l
				else return(241)  // .m
			}
		}
	}
	else {  // .n to .z
		if (valueFromAStataByte<=.s) {
			if (valueFromAStataByte<=.p) {  // .n to .p
				if (valueFromAStataByte==.n) return(242)  // .n
				else if (valueFromAStataByte==.o) return(243)  // .o
				else return(244)  // .p
			}
			else {  // .q to .s
				if (valueFromAStataByte==.q) return(245)  // .q
				else if (valueFromAStataByte==.r) return(246)  // .r
				else return(247)  // .s
			}
		}
		else {  // .t to .z
			if (valueFromAStataByte<=.w) {  // .t to .w
				if (valueFromAStataByte<=.u) {  // .t to .u
					if (valueFromAStataByte==.t) return(248)  // .t
					else return(249)  // .u
				}
				else if (valueFromAStataByte==.v) return(250)  // .v
				else return(251)  // .w
			}
			else {  // .x to .z
				if (valueFromAStataByte==.x) return(252)  // .x
				else if (valueFromAStataByte==.y) return(253)  // .y
				else return(254)  // .z
			}
		}
	}
}

real scalar from0to255ToByteVal(real scalar convertedVal) {
	if (convertedVal<228) return(convertedVal-127)
	else if (convertedVal==228) return(.)
	else if (convertedVal<=241) {  // 229 to 241
		if (convertedVal<=234) {  // 229 to 234
			if (convertedVal<=231) {  // 229 to 231
				if (convertedVal==229) return(.a)  // 229
				else if (convertedVal==230) return(.b)  // 230
				else return(.c)  // 231
			}
			else {  // 232 to 234
				if (convertedVal==232) return(.d)  // 232
				else if (convertedVal==233) return(.e)  // 233
				else return(.f)  // 234
			}
		}
		else {  // 235 to 241
			if (convertedVal<=238) {  // 235 to 238
				if (convertedVal<=236) {  // 235 to 236
					if (convertedVal==235) return(.g)  // 235
					else return(.h)  // 236
				}
				else if (convertedVal==237) return(.i)  // 237
				else return(.j)  // 238
			}
			else {  // 239 to 241
				if (convertedVal==239) return(.k)  // 239
				else if (convertedVal==240) return(.l)  // 240
				else return(.m)  // 241
			}
		}
	}
	else {  // 242 to 254
		if (convertedVal<=247) {  // 242 to 247
			if (convertedVal<=244) {  // 242 to 244
				if (convertedVal==242) return(.n)  // 242
				else if (convertedVal==243) return(.o)  // 243
				else return(.p)  // 244
			}
			else {  // 245 to 247
				if (convertedVal==245) return(.q)  // 245
				else if (convertedVal==246) return(.r)  // 246
				else return(.s)  // 247
			}
		}
		else {  // 248 to 254
			if (convertedVal<=251) {  // 248 to 251
				if (convertedVal<=249) {  // 248 to 249
					if (convertedVal==248) return(.t)  // 248
					else return(.u)  // 249
				}
				else if (convertedVal==250) return(.v)  // 250
				else return(.w)  // 251
			}
			else {  // 252 to 254
				if (convertedVal==252) return(.x)  // 252
				else if (convertedVal==253) return(.y)  // 253
				else return(.z)  // 254
			}
		}
	}
}

// Convert int number with possible missing value codes and negative values to a number with missing values represented numerically.
real scalar intValTo0to65535(real scalar valueFromAStataByte) {
	if (valueFromAStataByte<.) return(valueFromAStataByte+32767)
	else if (valueFromAStataByte==.) return(65508)
	else if (valueFromAStataByte<=.m) {  // .a to .m
		if (valueFromAStataByte<=.f) {
			if (valueFromAStataByte<=.c) {  // .a to .c
				if (valueFromAStataByte==.a) return(65509)  // .a
				else if (valueFromAStataByte==.b) return(65510)  // .b
				else return(65511)  // .c
			}
			else {  // .d to .f
				if (valueFromAStataByte==.d) return(65512)  // .d
				else if (valueFromAStataByte==.e) return(65513)  // .e
				else return(65514)  // .f
			}
		}
		else {  // .g to .m
			if (valueFromAStataByte<=.j) {  // .g to .j
				if (valueFromAStataByte<=.h) {  // .g to .h
					if (valueFromAStataByte==.g) return(65515)  // .g
					else return(65516)  // .h
				}
				else if (valueFromAStataByte==.i) return(65517)  // .i
				else return(65518)  // .j
			}
			else {  // .k to .m
				if (valueFromAStataByte==.k) return(65519)  // .k
				else if (valueFromAStataByte==.l) return(65520)  // .l
				else return(65521)  // .m
			}
		}
	}
	else {  // .n to .z
		if (valueFromAStataByte<=.s) {
			if (valueFromAStataByte<=.p) {  // .n to .p
				if (valueFromAStataByte==.n) return(65522)  // .n
				else if (valueFromAStataByte==.o) return(65523)  // .o
				else return(65524)  // .p
			}
			else {  // .q to .s
				if (valueFromAStataByte==.q) return(65525)  // .q
				else if (valueFromAStataByte==.r) return(65526)  // .r
				else return(65527)  // .s
			}
		}
		else {  // .t to .z
			if (valueFromAStataByte<=.w) {  // .t to .w
				if (valueFromAStataByte<=.u) {  // .t to .u
					if (valueFromAStataByte==.t) return(65528)  // .t
					else return(65529)  // .u
				}
				else if (valueFromAStataByte==.v) return(65530)  // .v
				else return(65531)  // .w
			}
			else {  // .x to .z
				if (valueFromAStataByte==.x) return(65532)  // .x
				else if (valueFromAStataByte==.y) return(65533)  // .y
				else return(65534)  // .z
			}
		}
	}
}

real scalar from0to65535ToIntVal(real scalar convertedVal) {
	if (convertedVal<65508) return(convertedVal-32767)
	else if (convertedVal==65508) return(.)
	else if (convertedVal<=65521) {  // 65509 to 65521
		if (convertedVal<=65514) {  // 65509 to 65514
			if (convertedVal<=65511) {  // 65509 to 65511
				if (convertedVal==65509) return(.a)  // 65509
				else if (convertedVal==65510) return(.b)  // 65510
				else return(.c)  // 65511
			}
			else {  // 65512 to 65514
				if (convertedVal==65512) return(.d)  // 65512
				else if (convertedVal==65513) return(.e)  // 65513
				else return(.f)  // 65514
			}
		}
		else {  // 65515 to 65521
			if (convertedVal<=65518) {  // 65515 to 65518
				if (convertedVal<=65516) {  // 65515 to 65516
					if (convertedVal==65515) return(.g)  // 65515
					else return(.h)  // 65516
				}
				else if (convertedVal==65517) return(.i)  // 65517
				else return(.j)  // 65518
			}
			else {  // 65519 to 65521
				if (convertedVal==65519) return(.k)  // 65519
				else if (convertedVal==65520) return(.l)  // 65520
				else return(.m)  // 65521
			}
		}
	}
	else {  // 65522 to 65534
		if (convertedVal<=65527) {  // 65522 to 65527
			if (convertedVal<=65524) {  // 65522 to 65524
				if (convertedVal==65522) return(.n)  // 65522
				else if (convertedVal==65523) return(.o)  // 65523
				else return(.p)  // 65524
			}
			else {  // 65525 to 65527
				if (convertedVal==65525) return(.q)  // 65525
				else if (convertedVal==65526) return(.r)  // 65526
				else return(.s)  // 65527
			}
		}
		else {  // 65528 to 65534
			if (convertedVal<=65531) {  // 65528 to 65531
				if (convertedVal<=65529) {  // 65528 to 65529
					if (convertedVal==65528) return(.t)  // 65528
					else return(.u)  // 65529
				}
				else if (convertedVal==65530) return(.v)  // 65530
				else return(.w)  // 65531
			}
			else {  // 65532 to 65534
				if (convertedVal==65532) return(.x)  // 65532
				else if (convertedVal==65533) return(.y)  // 65533
				else return(.z)  // 65534
			}
		}
	}
}

real scalar longValTo0to4294967295(real scalar valueFromAStataByte) {
	if (valueFromAStataByte<.) return(valueFromAStataByte+2147483647)
	else if (valueFromAStataByte==.) return(4294967268)
	else if (valueFromAStataByte<=.m) {  // .a to .m
		if (valueFromAStataByte<=.f) {
			if (valueFromAStataByte<=.c) {  // .a to .c
				if (valueFromAStataByte==.a) return(4294967269)  // .a
				else if (valueFromAStataByte==.b) return(4294967270)  // .b
				else return(4294967271)  // .c
			}
			else {  // .d to .f
				if (valueFromAStataByte==.d) return(4294967272)  // .d
				else if (valueFromAStataByte==.e) return(4294967273)  // .e
				else return(4294967274)  // .f
			}
		}
		else {  // .g to .m
			if (valueFromAStataByte<=.j) {  // .g to .j
				if (valueFromAStataByte<=.h) {  // .g to .h
					if (valueFromAStataByte==.g) return(4294967275)  // .g
					else return(4294967276)  // .h
				}
				else if (valueFromAStataByte==.i) return(4294967277)  // .i
				else return(4294967278)  // .j
			}
			else {  // .k to .m
				if (valueFromAStataByte==.k) return(4294967279)  // .k
				else if (valueFromAStataByte==.l) return(4294967280)  // .l
				else return(4294967281)  // .m
			}
		}
	}
	else {  // .n to .z
		if (valueFromAStataByte<=.s) {
			if (valueFromAStataByte<=.p) {  // .n to .p
				if (valueFromAStataByte==.n) return(4294967282)  // .n
				else if (valueFromAStataByte==.o) return(4294967283)  // .o
				else return(4294967284)  // .p
			}
			else {  // .q to .s
				if (valueFromAStataByte==.q) return(4294967285)  // .q
				else if (valueFromAStataByte==.r) return(4294967286)  // .r
				else return(4294967287)  // .s
			}
		}
		else {  // .t to .z
			if (valueFromAStataByte<=.w) {  // .t to .w
				if (valueFromAStataByte<=.u) {  // .t to .u
					if (valueFromAStataByte==.t) return(4294967288)  // .t
					else return(4294967289)  // .u
				}
				else if (valueFromAStataByte==.v) return(4294967290)  // .v
				else return(4294967291)  // .w
			}
			else {  // .x to .z
				if (valueFromAStataByte==.x) return(4294967292)  // .x
				else if (valueFromAStataByte==.y) return(4294967293)  // .y
				else return(4294967294)  // .z
			}
		}
	}
}

real scalar from0to4294967295ToLongVal(real scalar convertedVal) {
	if (convertedVal<4294967268) return(convertedVal-2147483647)
	else if (convertedVal==4294967268) return(.)
	else if (convertedVal<=4294967281) {  // 4294967269 to 4294967281
		if (convertedVal<=4294967274) {  // 4294967269 to 4294967274
			if (convertedVal<=4294967271) {  // 4294967269 to 4294967271
				if (convertedVal==4294967269) return(.a)  // 4294967269
				else if (convertedVal==4294967270) return(.b)  // 4294967270
				else return(.c)  // 4294967271
			}
			else {  // 4294967272 to 4294967274
				if (convertedVal==4294967272) return(.d)  // 4294967272
				else if (convertedVal==4294967273) return(.e)  // 4294967273
				else return(.f)  // 4294967274
			}
		}
		else {  // 4294967275 to 4294967281
			if (convertedVal<=4294967278) {  // 4294967275 to 4294967278
				if (convertedVal<=4294967276) {  // 4294967275 to 4294967276
					if (convertedVal==4294967275) return(.g)  // 4294967275
					else return(.h)  // 4294967276
				}
				else if (convertedVal==4294967277) return(.i)  // 4294967277
				else return(.j)  // 4294967278
			}
			else {  // 4294967279 to 4294967281
				if (convertedVal==4294967279) return(.k)  // 4294967279
				else if (convertedVal==4294967280) return(.l)  // 4294967280
				else return(.m)  // 4294967281
			}
		}
	}
	else {  // 4294967282 to 4294967294
		if (convertedVal<=4294967287) {  // 4294967282 to 4294967287
			if (convertedVal<=4294967284) {  // 4294967282 to 4294967284
				if (convertedVal==4294967282) return(.n)  // 4294967282
				else if (convertedVal==4294967283) return(.o)  // 4294967283
				else return(.p)  // 4294967284
			}
			else {  // 4294967285 to 4294967287
				if (convertedVal==4294967285) return(.q)  // 4294967285
				else if (convertedVal==4294967286) return(.r)  // 4294967286
				else return(.s)  // 4294967287
			}
		}
		else {  // 4294967288 to 4294967294
			if (convertedVal<=4294967291) {  // 4294967288 to 4294967291
				if (convertedVal<=4294967289) {  // 4294967288 to 4294967289
					if (convertedVal==4294967288) return(.t)  // 4294967288
					else return(.u)  // 4294967289
				}
				else if (convertedVal==4294967290) return(.v)  // 4294967290
				else return(.w)  // 4294967291
			}
			else {  // 4294967292 to 4294967294
				if (convertedVal==4294967292) return(.x)  // 4294967292
				else if (convertedVal==4294967293) return(.y)  // 4294967293
				else return(.z)  // 4294967294
			}
		}
	}
}

end
