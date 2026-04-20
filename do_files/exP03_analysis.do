* ================================================================
* exP03_analysis.do
* Converted from notebooks/exP03_analysis.ipynb
* ================================================================

clear all
version 18
set more off
set varabbrev off

* ------------------------------------------------
* 0. Path auto-detection
* ------------------------------------------------
local ROOT ""
if fileexists("data/raw/balance_sheet.csv") local ROOT "."
else if fileexists("../data/raw/balance_sheet.csv") local ROOT ".."
else if fileexists("../../data/raw/balance_sheet.csv") local ROOT "../.."
else {
    di as err "Cannot find data/raw/balance_sheet.csv. Please check working directory."
    exit 601
}

global RAW "`ROOT'/data/raw"
global CLEAN "`ROOT'/data/clean"
global OUT "`ROOT'/output"
global FIG "$OUT/figures"

di "RAW: $RAW"
di "CLEAN: $CLEAN"
di "OUT: $OUT"

cap mkdir "$CLEAN"
cap mkdir "$OUT"
cap mkdir "$FIG"

* ------------------------------------------------
* Diagnostic display commands from the notebook
* ------------------------------------------------
display as txt "PWD: `c(pwd)'"
display as txt "exists ./data/raw/balance_sheet.csv = " fileexists("data/raw/balance_sheet.csv")
display as txt "exists ../data/raw/balance_sheet.csv = " fileexists("../data/raw/balance_sheet.csv")
display as txt "exists ../../data/raw/balance_sheet.csv = " fileexists("../../data/raw/balance_sheet.csv")

* ------------------------------------------------
* Helper program: standardize stock code
* ------------------------------------------------
capture program drop mk_stkcd
program define mk_stkcd
    syntax , IDVAR(name)
    capture confirm string variable `idvar'
    if _rc {
        tostring `idvar', gen(stkcd_str) format(%12.0f) force
    }
    else {
        gen str12 stkcd_str = trim(`idvar')
    }
    replace stkcd_str = trim(stkcd_str)
    destring stkcd_str, gen(stkcd) force
    drop stkcd_str
end

* ------------------------------------------------
* 3.1 Balance sheet
* ------------------------------------------------
import delimited "$RAW/balance_sheet.csv", varnames(1) clear case(preserve) encoding(utf-8)
mk_stkcd, idvar(Stkcd)
gen double accper = date(Accper, "YMD")
format accper %td
gen int year = year(accper)
keep if inlist(upper(trim(Typrep)), "A")        // annual report only
keep if month(accper) == 12                     // year-end observations

rename A004000000 total_assets
rename A003000000 total_liab
rename A002000000 fixed_assets_net

keep stkcd year total_assets total_liab fixed_assets_net
duplicates drop stkcd year, force
save "$CLEAN/balance_ann.dta", replace

* ------------------------------------------------
* 3.2 Income statement
* ------------------------------------------------
import delimited "$RAW/income_stmt.csv", varnames(1) clear case(preserve) encoding(utf-8)
mk_stkcd, idvar(Stkcd)
gen double accper = date(Accper, "YMD")
format accper %td
gen int year = year(accper)
keep if inlist(upper(trim(Typrep)), "A")
keep if month(accper) == 12

rename B001000000 net_profit
keep stkcd year net_profit
duplicates drop stkcd year, force
save "$CLEAN/income_ann.dta", replace

* ------------------------------------------------
* 3.3 Cash flow statement
* ------------------------------------------------
import delimited "$RAW/cashflow.csv", varnames(1) clear case(preserve) encoding(utf-8)
mk_stkcd, idvar(Stkcd)
gen double accper = date(Accper, "YMD")
format accper %td
gen int year = year(accper)
keep if inlist(upper(trim(Typrep)), "A")
keep if month(accper) == 12

capture confirm variable C001100000
if !_rc rename C001100000 depreciation
else gen double depreciation = .

keep stkcd year depreciation
duplicates drop stkcd year, force
save "$CLEAN/cashflow_ann.dta", replace

* ------------------------------------------------
* 4.1 Ownership
* ------------------------------------------------
import delimited "$RAW/ownership.csv", varnames(1) clear case(preserve) encoding(utf-8)
mk_stkcd, idvar(Symbol)
gen double endd = date(EndDate, "YMD")
format endd %td
gen int year = year(endd)

capture confirm string variable EquityNatureID
if _rc tostring EquityNatureID, replace force
capture confirm string variable EquityNature
if _rc tostring EquityNature, replace force

gen byte soe = 0
replace soe = 1 if regexm(EquityNatureID, "(^|,)1(,|$)")
replace soe = 1 if strpos(EquityNature, "国企") > 0 | strpos(EquityNature, "国有") > 0

keep stkcd year soe
duplicates drop stkcd year, force
save "$CLEAN/ownership.dta", replace

* ------------------------------------------------
* 4.2 Industry classification
* ------------------------------------------------
import delimited "$RAW/industry.csv", varnames(1) clear case(preserve) encoding(utf-8)
mk_stkcd, idvar(Symbol)
gen double endd = date(EndDate, "YMD")
gen int year = year(endd)
rename IndustryCode ind_code
keep stkcd year ind_code
duplicates drop stkcd year, force
save "$CLEAN/industry.dta", replace

* ------------------------------------------------
* 4.3 ST/PT flag
* ------------------------------------------------
import delimited "$RAW/st_flag.csv", varnames(1) clear case(preserve) encoding(utf-8)
mk_stkcd, idvar(Symbol)
gen double endd = date(EndDate, "YMD")
gen int year = year(endd)
capture confirm string variable LISTINGSTATE
if _rc tostring LISTINGSTATE, replace force
rename LISTINGSTATE listing_state
keep stkcd year listing_state
duplicates drop stkcd year, force
save "$CLEAN/st_flag.dta", replace

* ------------------------------------------------
* 4.4 M2 growth rate
* ------------------------------------------------
import delimited "$RAW/m2.csv", varnames(1) clear case(preserve) encoding(utf-8)

destring year, replace force
tsset year
gen double m2_growth = (m2 - L.m2) / L.m2 * 100
keep year m2_growth
save "$CLEAN/m2.dta", replace

* ------------------------------------------------
* 5. Merge and sample filtering
* ------------------------------------------------
use "$CLEAN/balance_ann.dta", clear
merge 1:1 stkcd year using "$CLEAN/income_ann.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/cashflow_ann.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/ownership.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/industry.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/st_flag.dta", nogen keep(master match)
merge m:1 year using "$CLEAN/m2.dta", nogen keep(master match)

foreach v in total_assets total_liab fixed_assets_net net_profit depreciation {
    capture destring `v', replace force
}

gen double lev = total_liab / total_assets if total_assets > 0
gen double npr = net_profit / total_assets if total_assets > 0
gen double size = ln(total_assets) if total_assets > 0
gen double tang = fixed_assets_net / total_assets if total_assets > 0
gen double ndts = depreciation / total_assets if total_assets > 0

bysort stkcd (year): gen double total_assets_lag1 = total_assets[_n-1]
gen double growth = (total_assets - total_assets_lag1) / total_assets_lag1 if total_assets_lag1 > 0

gen str1 ind1 = substr(ind_code, 1, 1)
gen byte is_finance = (ind1 == "J")

capture confirm string variable listing_state
if _rc tostring listing_state, replace force
gen byte st_flag = (strpos(upper(listing_state), "ST") > 0) if !missing(listing_state)

tempname fh
postfile `fh' str40 step long N using "$OUT/sample_counts.dta", replace

count
post `fh' ("1. Initial merged sample") (r(N))

drop if is_finance == 1
count
post `fh' ("2. After dropping finance (J)") (r(N))

preserve
    keep stkcd st_flag
    bysort stkcd: egen ever_st = max(st_flag)
    keep stkcd ever_st
    duplicates drop stkcd, force
    tempfile st_keep
    save `st_keep', replace
restore

merge m:1 stkcd using `st_keep', nogen
drop if ever_st == 1
drop ever_st st_flag
count
post `fh' ("3. After dropping ST firms") (r(N))

drop if lev > 1 & !missing(lev)
count
post `fh' ("4. After dropping lev > 1") (r(N))

drop if missing(lev, npr, size, tang, growth, ndts)
count
post `fh' ("5. After dropping missing core vars") (r(N))

postclose `fh'

use "$OUT/sample_counts.dta", clear
list, clean noobs
export delimited using "$OUT/sample_counts.csv", replace

use "$CLEAN/balance_ann.dta", clear
merge 1:1 stkcd year using "$CLEAN/income_ann.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/cashflow_ann.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/ownership.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/industry.dta", nogen keep(master match)
merge 1:1 stkcd year using "$CLEAN/st_flag.dta", nogen keep(master match)
merge m:1 year using "$CLEAN/m2.dta", nogen keep(master match)

foreach v in total_assets total_liab fixed_assets_net net_profit depreciation {
    capture destring `v', replace force
}

gen double lev = total_liab / total_assets if total_assets > 0
gen double npr = net_profit / total_assets if total_assets > 0
gen double size = ln(total_assets) if total_assets > 0
gen double tang = fixed_assets_net / total_assets if total_assets > 0
gen double ndts = depreciation / total_assets if total_assets > 0
bysort stkcd (year): gen double total_assets_lag1 = total_assets[_n-1]
gen double growth = (total_assets - total_assets_lag1) / total_assets_lag1 if total_assets_lag1 > 0
gen str1 ind1 = substr(ind_code, 1, 1)
gen byte is_finance = (ind1 == "J")
capture confirm string variable listing_state
if _rc tostring listing_state, replace force
gen byte st_flag = (strpos(upper(listing_state), "ST") > 0) if !missing(listing_state)

drop if is_finance == 1

preserve
    keep stkcd st_flag
    bysort stkcd: egen ever_st = max(st_flag)
    keep stkcd ever_st
    duplicates drop stkcd, force
    tempfile st_keep2
    save `st_keep2', replace
restore

merge m:1 stkcd using `st_keep2', nogen
drop if ever_st == 1
drop ever_st st_flag
drop if lev > 1 & !missing(lev)
drop if missing(lev, npr, size, tang, growth, ndts)

save "$CLEAN/sample_before_winsor.dta", replace

di _n "Sample before winsorizing saved: $CLEAN/sample_before_winsor.dta"
di "Sample counts table exported to $OUT/sample_counts.csv"

* ------------------------------------------------
* 6. Winsorization and panel setup
* ------------------------------------------------
use "$CLEAN/sample_before_winsor.dta", clear
cap which winsor2
if _rc == 0 {
    winsor2 lev npr tang growth ndts, cuts(1 99) by(year) replace
}
else {
    foreach v in lev npr tang growth ndts {
        bysort year: egen p1_`v' = pctile(`v'), p(1)
        bysort year: egen p99_`v' = pctile(`v'), p(99)
        replace `v' = max(`v', p1_`v')
        replace `v' = min(`v', p99_`v')
        drop p1_`v' p99_`v'
    }
}

destring stkcd, replace force
xtset stkcd year
save "$CLEAN/final_panel.dta", replace
export delimited using "$CLEAN/final_panel.csv", replace

* ------------------------------------------------
* 7. Descriptive statistics and plots
* ------------------------------------------------
use "$CLEAN/final_panel.dta", clear

eststo clear
estpost sum lev npr size tang growth ndts
eststo full
estpost sum lev npr size tang growth ndts if soe == 1
eststo soe
estpost sum lev npr size tang growth ndts if soe == 0
eststo nonsoe

esttab full soe nonsoe using "$OUT/desc_summary.rtf", ///
    cells("mean(fmt(3)) sd(fmt(3)) p10(fmt(3)) p25(fmt(3)) p50(fmt(3)) p75(fmt(3)) p90(fmt(3))") ///
    nonumber mtitle("Full" "SOE" "Non-SOE") replace

foreach v in lev npr size tang growth ndts {
    ttest `v', by(soe)
}

pwcorr lev npr size tang growth ndts soe, star(0.05) sig

graph matrix lev npr size tang growth ndts soe, ///
    half msymbol(circle_hollow) mcolor(blue%30) ///
    title("Scatterplot Matrix of Main Variables") ///
    note("Diagonal panels show variable names. Off-diagonal show pairwise scatter plots.")
graph export "$FIG/corr_scatter_matrix.png", replace

preserve
collapse (mean) lev npr, by(year soe)
twoway (line lev year if soe==1, lcolor(blue) lpattern(solid)) ///
       (line lev year if soe==0, lcolor(red) lpattern(dash)), ///
       legend(label(1 "SOE") label(2 "Non-SOE")) ///
       title("Average Leverage by Year") ytitle("Leverage") xtitle("Year")
graph export "$FIG/lev_trend_by_soe.png", replace

twoway (line npr year if soe==1, lcolor(blue) lpattern(solid)) ///
       (line npr year if soe==0, lcolor(red) lpattern(dash)), ///
       legend(label(1 "SOE") label(2 "Non-SOE")) ///
       title("Average NPR by Year") ytitle("NPR") xtitle("Year")
graph export "$FIG/npr_trend_by_soe.png", replace
restore

graph box lev, over(year) nooutsides ///
    title("Leverage Distribution by Year") ytitle("Leverage")
graph export "$FIG/lev_box_by_year.png", replace

* ------------------------------------------------
* 8. Winsorization comparison plots
* ------------------------------------------------
use "$CLEAN/sample_before_winsor.dta", clear
keep if year == 2020
graph box lev, name(before_lev, replace) title("Lev before winsor (2020)")

use "$CLEAN/final_panel.dta", clear
keep if year == 2020
graph box lev, name(after_lev, replace) title("Lev after winsor (2020)")

graph combine before_lev after_lev, rows(1) ycommon title("Effect of Winsorizing on Leverage")
graph export "$FIG/winsor_box_lev.png", replace

use "$CLEAN/sample_before_winsor.dta", clear
keep if year == 2020
graph box npr, name(before_npr, replace) title("NPR before winsor")

use "$CLEAN/final_panel.dta", clear
keep if year == 2020
graph box npr, name(after_npr, replace) title("NPR after winsor")

graph combine before_npr after_npr, rows(1) ycommon title("Effect of Winsorizing on NPR")
graph export "$FIG/winsor_box_npr.png", replace

* ------------------------------------------------
* 9. Main regressions: M1-M3
* ------------------------------------------------
use "$CLEAN/final_panel.dta", clear
xtset stkcd year

global controls "size tang growth ndts"

reghdfe lev npr $controls, absorb(stkcd year) vce(cluster stkcd year)
estimates store M1

reghdfe lev npr $controls if soe == 1, absorb(stkcd year) vce(cluster stkcd year)
estimates store M2_soe

reghdfe lev npr $controls if soe == 0, absorb(stkcd year) vce(cluster stkcd year)
estimates store M2_nonsoe

reghdfe lev c.npr##i.soe $controls, absorb(stkcd year) vce(cluster stkcd year)
estimates store M3

lincom _b[npr] + _b[1.soe#c.npr]
quietly margins, dydx(npr) at(soe=(0 1))
marginsplot, xlabel(0 "Non-SOE" 1 "SOE") ///
    title("Marginal Effect of NPR on Leverage by Ownership") ///
    ytitle("Effect on Leverage") ///
    scheme(s2color)
graph export "$FIG/M3_margins_soe.png", replace

* ------------------------------------------------
* 10. IFE model
* ------------------------------------------------
use "$CLEAN/final_panel.dta", clear
cap confirm variable m2_growth
if _rc {
    di "Error: m2_growth variable not found. Please merge m2 data first."
    exit
}

cap which regife
if _rc == 0 {
    regife lev npr m2_growth $controls, id(stkcd) time(year) factor(1)
    estimates store M1_ife
}
else {
    di "regife not installed. Skipping IFE model."
    estimates store M1_ife
    capture estimates drop M1_ife
}

* ------------------------------------------------
* 11. M4 time-varying coefficient
* ------------------------------------------------
use "$CLEAN/final_panel.dta", clear
xtset stkcd year

reghdfe lev i.year#c.npr $controls, absorb(stkcd year) vce(cluster stkcd year)
estimates store M4

coefplot, keep(*.year#c.npr) vertical recast(line) ///
    title("Time-varying Coefficient of NPR (95% CI)") ///
    xtitle("Year") ytitle("Coefficient") ///
    xlabel(, angle(45)) ciopts(recast(rcap))
graph export "$FIG/M4_timevary_coefs.png", replace

levelsof year, local(yrs)
tempname f_m4
postfile `f_m4' int year double coef se using "$OUT/m4_year_coefs.dta", replace
foreach y of local yrs {
    capture noisily count if year == `y'
    if r(N) >= 20 {
        capture noisily regress lev npr $controls if year == `y', vce(robust)
        if _rc == 0 & !missing(_b[npr]) {
            post `f_m4' (`y') (_b[npr]) (_se[npr])
        }
    }
}
postclose `f_m4'
use "$OUT/m4_year_coefs.dta", clear
gen coef_m = coef * 1000000
gen lb_m = (coef - 1.96*se) * 1000000
gen ub_m = (coef + 1.96*se) * 1000000
count if !missing(coef_m)
di as txt "Non-missing M4 points = " r(N)
sum coef_m, meanonly
local ymin = r(min)
local ymax = r(max)
local pad = max(1, (`ymax' - `ymin') * 0.15)
local ymin = `ymin' - `pad'
local ymax = `ymax' + `pad'
twoway (line coef_m year, lcolor(navy) lwidth(medthick)) ///
       (scatter coef_m year, mcolor(navy) msymbol(O) msize(medlarge)) ///
       (rcap lb_m ub_m year, lcolor(gs8)), ///
       yline(0, lpattern(dash) lcolor(maroon)) ///
       yscale(range(`ymin' `ymax')) ///
       title("M4: Yearly NPR effect (x10^6)") ytitle("Coefficient on NPR (x10^6)") xtitle("Year")
graph export "$FIG/M4_timevary_coefs_alt.png", replace

* ------------------------------------------------
* 12. M5 function coefficient plot
* ------------------------------------------------
use "$CLEAN/final_panel.dta", clear
xtset stkcd year

sum size, meanonly
gen size_c = size - r(mean)

gen npr_size = npr * size_c
gen npr_size2 = npr * size_c^2

reghdfe lev npr npr_size npr_size2 $controls, absorb(stkcd year) vce(cluster stkcd year)
estimates store M5

sum size_c, detail
local sz_min = r(min)
local sz_max = r(max)
local p10 = r(p10)
local p25 = r(p25)
local p50 = r(p50)
local p75 = r(p75)
local p90 = r(p90)

tempfile beta_curve
tempname fh2
postfile `fh2' double size_c meff using `beta_curve', replace
forvalues k = 0(1)100 {
    local s = `sz_min' + (`sz_max' - `sz_min') * `k' / 100
    local me = _b[npr] + _b[npr_size]*`s' + _b[npr_size2]*(`s'^2)
    post `fh2' (`s') (`me')
}
postclose `fh2'
use `beta_curve', clear
twoway (line meff size_c, lcolor(navy) lwidth(medthick)) ///
       (scatter meff size_c, mcolor(navy) msymbol(O) msize(small)) ///
       , yline(0, lpattern(dash) lcolor(maroon)) ///
       xline(`p10' `p25' `p50' `p75' `p90', lpattern(dash) lcolor(gs8)) ///
       title("Marginal Effect of NPR as Function of Centered Size") ///
       xtitle("Centered Size (size_c)") ytitle("Effect on Leverage")
graph export "$FIG/M5_beta_size_function.png", replace

* ------------------------------------------------
* 13. M6 threshold grid search fallback
* ------------------------------------------------
use "$CLEAN/final_panel.dta", clear
xtset stkcd year

di "Running threshold grid search for M6."
tempfile m6grid
tempname f_m6
postfile `f_m6' double th str6 group double coef se long N using `m6grid', replace

centile size, centile(10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90)
local t1 = r(c_1)
local t2 = r(c_2)
local t3 = r(c_3)
local t4 = r(c_4)
local t5 = r(c_5)
local t6 = r(c_6)
local t7 = r(c_7)
local t8 = r(c_8)
local t9 = r(c_9)
local t10 = r(c_10)
local t11 = r(c_11)
local t12 = r(c_12)
local t13 = r(c_13)
local t14 = r(c_14)
local t15 = r(c_15)
local t16 = r(c_16)
local t17 = r(c_17)
local thresholds "`t1' `t2' `t3' `t4' `t5' `t6' `t7' `t8' `t9' `t10' `t11' `t12' `t13' `t14' `t15' `t16' `t17'"
foreach th of local thresholds {
    foreach grp in low high {
        local cond = cond("`grp'" == "low", "size <= `th'", "size > `th'")
        capture noisily reghdfe lev npr $controls if `cond', absorb(stkcd year) vce(cluster stkcd year)
        if _rc != 0 capture noisily regress lev npr $controls if `cond', vce(robust)
        if _rc == 0 & e(N) >= 20 {
            post `f_m6' (`th') ("`grp'") (_b[npr]) (_se[npr]) (e(N))
        }
    }
}
postclose `f_m6'

use `m6grid', clear
drop if missing(th, coef, se)
count
di as txt "M6 points kept = " r(N)
gen lb = coef - 1.96*se
gen ub = coef + 1.96*se
sort group th
twoway (rarea lb ub th if group=="low", color(blue%12) lcolor(blue%0)) ///
       (line coef th if group=="low", lcolor(blue) lwidth(medthick)) ///
       (scatter coef th if group=="low", mcolor(blue) msymbol(O) msize(small)) ///
       (rarea lb ub th if group=="high", color(red%12) lcolor(red%0)) ///
       (line coef th if group=="high", lcolor(red) lwidth(medthick)) ///
       (scatter coef th if group=="high", mcolor(red) msymbol(D) msize(small)) ///
       , legend(order(2 "Size <= threshold" 5 "Size > threshold") rows(1)) ///
       xtitle("Threshold (Size)") ytitle("NPR Coefficient") ///
       title("M6: Threshold Effect Grid Search")
graph export "$FIG/M6_threshold_grid.png", replace
export delimited using "$OUT/m6_threshold_grid.csv", replace

* ------------------------------------------------
* 14. Export regression table
* ------------------------------------------------
use "$CLEAN/final_panel.dta", clear
cap estimates restore M1
cap estimates restore M1_ife
cap estimates restore M2_soe
cap estimates restore M2_nonsoe
cap estimates restore M3

local stats_opts stats(N r2_within N_clust1, fmt(%9.0f %9.3f %9.0f) ///
         labels("Observations" "Within R2" "Firms"))

local has_ife = 0
cap estimates restore M1_ife
if _rc == 0 local has_ife = 1

if `has_ife' == 1 {
    esttab M1 M1_ife M2_soe M2_nonsoe M3 using "$OUT/reg_results_M1_M3.rtf", ///
        replace se star(* 0.1 ** 0.05 *** 0.01) ///
        keep(npr npr_soe m2_growth size tang growth ndts) ///
        order(npr npr_soe m2_growth size tang growth ndts) ///
        `stats_opts' ///
        title("Regression Results: Determinants of Leverage") ///
        addnotes("Standard errors clustered by firm and year (M1_ife uses robust)." ///
                 "SOE dummy absorbed in fixed-effects models.")
}
else {
    esttab M1 M2_soe M2_nonsoe M3 using "$OUT/reg_results_M1_M3.rtf", ///
        replace se star(* 0.1 ** 0.05 *** 0.01) ///
        keep(npr npr_soe size tang growth ndts) ///
        order(npr npr_soe size tang growth ndts) ///
        `stats_opts' ///
        title("Regression Results: Determinants of Leverage") ///
        addnotes("Standard errors clustered by firm and year." ///
                 "SOE dummy absorbed in fixed-effects models.")
}

esttab M1 M2_soe M2_nonsoe M3 using "$OUT/reg_results_M1_M3.csv", replace se star

* ------------------------------------------------
* 15. Completion message
* ------------------------------------------------
di as result _n "========================================="
di as result "All analysis completed successfully!"
di as result "Check output folder: $OUT"
di as result "Figures folder: $FIG"
di as result "========================================="
/* exP03_analysis.do
   Stata workflow template for: 上市公司资本结构影响因素分析 (exP03)
   Author: 谢婧怡 (student)
   Usage: Edit code mapping if needed, then run in Stata: do do_files/exP03_analysis.do
*/

capture program drop _all
version 17

global RAW data/raw
global CLEAN data/clean
global OUT output
mkdir "$CLEAN" 
mkdir "$OUT" 
mkdir "${OUT}/figures"

set more off

* 0. Install required packages (only once)
quietly {
    ssc install reghdfe, replace
    ssc install ftools, replace
    ssc install winsor2, replace
    ssc install regife, replace // if available
    ssc install estout, replace
    ssc install coefplot, replace
}

* 1. Import CSVs (CSMAR format)
* Adjust encoding if necessary. On Windows Stata, use import delimited.

display "Importing balance sheet (annual reports only - Typrep A, month 12)"
import delimited using "$RAW/balance_sheet.csv", varnames(1) stringcols(1) clear
gen stkcd = string(Stkcd)
gen accper = date(Accper, "YMD") if !missing(Accper)
* if Accper is text like 2010-12-31, try:
capture confirm variable accper
if _rc==0 replace accper = daily(Accper, "YMD")
format accper %td
gen year = year(accper)
keep if Typrep=="A" | Typrep=="a"
keep if month(accper)==12

* NOTE: The key CSMAR codes detected in the CSV headers include A004000000 (Total assets), A003000000 (Total liabilities), A002000000 (Fixed assets net)
rename A004000000 total_assets
rename A003000000 total_liab
rename A002000000 fixed_assets_net
save "$CLEAN/balance_ann.dta", replace

display "Importing income statement"
import delimited using "$RAW/income_stmt.csv", varnames(1) stringcols(1) clear
gen stkcd = string(Stkcd)
gen accper = date(Accper, "YMD") if !missing(Accper)
format accper %td
gen year = year(accper)
keep if Typrep=="A" | Typrep=="a"
keep if month(accper)==12
* key codes: B001000000 (Net profit), B001100000 (Operating revenue)
rename B001000000 net_profit
rename B001100000 oper_rev
save "$CLEAN/income_ann.dta", replace

display "Importing cashflow statement"
import delimited using "$RAW/cashflow.csv", varnames(1) stringcols(1) clear
gen stkcd = string(Stkcd)
gen accper = date(Accper, "YMD") if !missing(Accper)
format accper %td
gen year = year(accper)
keep if Typrep=="A" | Typrep=="a"
keep if month(accper)==12
* candidate depreciation flow: C001100000 or similar. Rename if present
capture confirm variable C001100000
if _rc==0 rename C001100000 depreciation
save "$CLEAN/cashflow_ann.dta", replace

display "Importing ownership, industry, st_flag"
import delimited using "$RAW/ownership.csv", varnames(1) clear
rename Symbol stkcd
gen year = year(date(EndDate)) if !missing(EndDate)
rename EquityNature EquityNature_raw
gen soe = (strpos(lower(EquityNature_raw), "state")>0) if !missing(EquityNature_raw)
replace soe = 0 if soe==.
save "$CLEAN/ownership.dta", replace

import delimited using "$RAW/industry.csv", varnames(1) clear
rename Symbol stkcd
gen year = year(date(EndDate)) if !missing(EndDate)
rename IndustryCode ind_code
save "$CLEAN/industry.dta", replace

import delimited using "$RAW/st_flag.csv", varnames(1) clear
rename Symbol stkcd
gen year = year(date(EndDate)) if !missing(EndDate)
rename LISTINGSTATE listing_state
save "$CLEAN/st_flag.dta", replace

* 2. Merge datasets
use "$CLEAN/balance_ann.dta", clear
sort stkcd year
merge 1:1 stkcd year using "$CLEAN/income_ann.dta", keepusing(net_profit oper_rev)
merge 1:1 stkcd year using "$CLEAN/cashflow_ann.dta", keepusing(depreciation)
merge 1:1 stkcd year using "$CLEAN/ownership.dta", keepusing(soe EquityNature_raw)
merge 1:1 stkcd year using "$CLEAN/industry.dta", keepusing(ind_code)
merge 1:1 stkcd year using "$CLEAN/st_flag.dta", keepusing(listing_state)

* 3. Construct variables
gen double lev = total_liab / total_assets
gen double npr = net_profit / total_assets
gen double size = ln(total_assets)
gen double tang = fixed_assets_net / total_assets
gen double ndts = depreciation / total_assets
bysort stkcd (year): gen total_assets_lag1 = total_assets[_n-1]
gen double growth = (total_assets - total_assets_lag1) / total_assets_lag1

* 4. Sample filtering and record counts
preserve
tempfile before
save `before'
local N0 = _N
display "Initial obs: " _N

* drop financial industry (CSMAR codes starting with J)
drop if substr(ind_code,1,1)=="J"
local N1 = _N

* drop companies ever ST (conservative)
preserve
keep stkcd listing_state
bysort stkcd: gen ever_ST = (sum(listing_state=="ST")>0)
keep if ever_ST==1
tempfile stlist
keep stkcd
duplicates drop
save `stlist'
restore
drop if inlist(stkcd, file(`stlist'))
local N2 = _N

* drop lev>1
drop if lev>1
local N3 = _N

* drop missing key vars
drop if missing(lev,npr,size,tang,growth,ndts)
local N4 = _N

display "Sample sizes: initial `N0' -> after drop finance `N1' -> after drop ST `N2' -> after lev>1 `N3' -> after missing `N4'"

* 5. Winsorize continuous vars by year (1% two-sided)
* Using winsor2 by year is cleaner if installed
quietly capture which winsor2
if _rc==0 {
    bysort year: winsor2 lev, gen(lev_w) p(1)
    bysort year: winsor2 npr, gen(npr_w) p(1)
    bysort year: winsor2 tang, gen(tang_w) p(1)
    bysort year: winsor2 growth, gen(growth_w) p(1)
    bysort year: winsor2 ndts, gen(ndts_w) p(1)
} else {
    display "winsor2 not available — using pctile approach"
    egen p1_lev = pctile(lev), by(year) p(1)
    egen p99_lev = pctile(lev), by(year) p(99)
    bysort year: replace lev = max(lev, p1_lev)
    bysort year: replace lev = min(lev, p99_lev)
}

save "$CLEAN/final_panel.dta", replace

* 6. Descriptive statistics and correlation matrices
use "$CLEAN/final_panel.dta", clear
preserve
tabstat lev npr size tang growth ndts, by(soe) stats(n mean sd p10 p25 median p75 p90)
correlate lev npr size tang growth ndts
restore

* 7. Regression M1: TWFE using reghdfe with two-way clustering
reghdfe lev npr size tang growth ndts, absorb(stkcd year) vce(cluster stkcd year)
estimates store M1

* 8. M1' IFE (regife) — if regife installed
capture which regife
if _rc==0 {
    regife lev npr, id(stkcd) time(year) x(size tang growth ndts)
    estimates store M1_ife
} else {
    display "regife not installed; skip IFE step."
}

* 9. M2: group regressions by SOE
reghdfe lev npr size tang growth ndts if soe==1, absorb(stkcd year) vce(cluster stkcd year)
estimates store M2_soe
reghdfe lev npr size tang growth ndts if soe==0, absorb(stkcd year) vce(cluster stkcd year)
estimates store M2_nonsoe

* 10. M3: interaction term (npr * soe)
gen npr_soe = npr * soe
reghdfe lev npr npr_soe size tang growth ndts, absorb(stkcd year) vce(cluster stkcd year)
estimates store M3_interact

* 11. M4: time-varying coefficients — year x npr
reghdfe lev i.year#c.npr size tang growth ndts, absorb(stkcd year) vce(cluster stkcd year)
estimates store M4_timevary
coefplot, keep(*#npr) xline(0) ciopts(recast(rarea)) vertical
graph export "${OUT}/figures/M4_timevary_coefs.png", replace

* 12. M5: function-coefficient (polynomial) — generate npr*size and npr*size^2
gen npr_size = npr*size
gen npr_size2 = npr*(size^2)
reghdfe lev npr npr_size npr_size2 size tang growth ndts, absorb(stkcd year) vce(cluster stkcd year)
estimates store M5_poly

* 13. M6: threshold model (xthreg) — requires balanced panel; use xtbalance then xthreg if installed
capture which xthreg
if _rc==0 {
    xtbalance, range(2010 2025)
    xthreg lev npr size tang growth ndts, thv(size) trim(0.05) nboot(300) id(stkcd) time(year)
    estimates store M6_thresh
} else {
    display "xthreg not installed; perform grid-search threshold in Stata or use Python implementation."
}

* 14. Export regression table
esttab M1 M2_soe M2_nonsoe M3_interact using "${OUT}/regression_table.rtf", replace title("M1-M3 Results")

display "Do-file completed. Check output/ for figures and saved estimates."
