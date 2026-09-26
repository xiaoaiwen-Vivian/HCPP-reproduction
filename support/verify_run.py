"""Xiaoai: validate the upstream-data pipeline and manuscript outputs."""
from pathlib import Path
import argparse, json, re
import numpy as np
import pandas as pd

def main():
    ap=argparse.ArgumentParser();ap.add_argument('package',type=Path);ap.add_argument('run',type=Path);ap.add_argument('--build-only',action='store_true');a=ap.parse_args()
    (a.run/'verification_passed.ok').unlink(missing_ok=True)
    checks=[]
    def check(name,value):
        checks.append({'check':name,'passed':bool(value)})
    def compare(name,got,want):
        if isinstance(want,dict):
            for key,value in want.items():compare(f'{name}.{key}',got.get(key),value)
        elif isinstance(want,list):
            check(name+'.length',len(got)==len(want))
            for i,(x,y) in enumerate(zip(got,want)):compare(f'{name}[{i}]',x,y)
        elif want is None or isinstance(want,float) and np.isnan(want):check(name,got is None or pd.isna(got))
        elif isinstance(want,(int,float)) and not isinstance(want,bool):
            check(name,got is not None and np.isclose(float(got),float(want),rtol=1e-6,atol=1e-8))
        else:check(name,got==want)
    log=(a.run/'logs'/('pipeline_build.log' if a.build_only else 'pipeline_.log')).read_text(errors='replace')
    check('no_unhandled_stata_error',not re.search(r'^r\(\d+\);',log,re.M))
    sentinel='RAW_TO_0507_COMPLETED' if a.build_only else 'HCPP_RAW_0507_ALL_FINAL_MODELS_COMPLETED'
    check('completed_sentinel','\n'+sentinel+'\n' in log)
    charls=pd.read_stata(a.run/'data/charls.dta',convert_categoricals=False)
    data=pd.read_stata(a.run/'data/dataset 0507.dta',convert_categoricals=False)
    person=data.ID.notna() & data.ID.ne('') & data.wave.notna()
    check('charls_rows',len(charls)==96628);check('0507_rows',len(data)==86696)
    check('identified_person_waves',person.sum()==85386)
    check('environment_only_rows',(~person).sum()==1310)
    check('unique_person_wave_keys',not data.loc[person].duplicated(['ID','wave']).any())
    if not a.build_only:
        o=a.run/'output';expected=json.loads((a.package/'verification/EXPECTED_RESULTS.json').read_text())
        primary=pd.read_stata(o/'primary_estimation_sample.dta',convert_categoricals=False)
        check('primary_observations',len(primary)==16661);check('primary_people',primary.ID.nunique()==7995)
        check('primary_age_eligible',primary.age.notna().all() and primary.age.ge(45).all())
        check('primary_urban',primary.rural.eq(0).all())
        maps={'main':'main_DID_city_cluster.xlsx','PSM':'prepolicy_means_psmdid_summary.xlsx','heterogeneity_interactions':'heterogeneity_interactions_city_cluster.xlsx','mediation':'city_bootstrap_indirect_FDR.csv','wild_bootstrap':'main_did_wild_cluster_results.csv','nonlinear':'nonlinear_cityFE_citycluster.csv','individual_FE':'individual_FE_citycluster.xlsx','covid':'covid_centered_model_summary.csv'}
        for key,name in maps.items():
            frame=pd.read_csv(o/name) if name.endswith('.csv') else pd.read_excel(o/name)
            rows=frame.to_dict('records');compare(key,rows[0] if key in ['main','PSM'] else rows,expected[key])
        compare('event_pretrend_p',pd.read_excel(o/'event_study_city_cluster.xlsx').Joint_pretrend_P.iloc[0],expected['event_pretrend_p'])
        nl=pd.read_stata(o/'nonlinear_estimation_sample.dta',convert_categoricals=False)
        check('nonlinear_N',len(nl)==16638)
        check('nonlinear_cities',nl.city.nunique()==93)
        removed=primary.loc[~primary.set_index(['ID','iwy']).index.isin(nl.set_index(['ID','iwy']).index)]
        check('nonlinear_exclusions',len(removed)==23 and removed.city.eq('鞍山市').all() and removed.rgoingl_clean.eq(1).all())
        po=pd.read_csv(o/'did_parallel_lines.csv').iloc[0]
        check('DID_specific_test_sample',po.N==16638 and po.Cities==93)
        check('DID_specific_test_df',po.df==2)
        check('DID_specific_test_chi2',abs(po.Wald_chi2-3.487152)<0.0001)
        check('DID_specific_test_p',abs(po.P-.17489398)<0.00001 and round(po.P,4)==.1749)
        check('DID_specific_test_fit_valid',po.Converged==1 and po.Invalid_fitted_prob==0)
        independent=json.loads((a.package/'verification/NONLINEAR_INDEPENDENT_REFERENCE.json').read_text())
        ofit=pd.read_csv(o/'model_ologit.csv',skipinitialspace=True).iloc[0]
        check('ordered_independent_analytic_coef',abs(ofit.Coef-independent['ordered_DID'])<1e-6)
        check('ordered_independent_analytic_SE',abs(ofit.SE-independent['ordered_city_SE'])<1e-6)
        slopes=pd.read_csv(o/'did_threshold_slopes.csv').sort_values('Threshold')
        check('DID_threshold_independent_coefficients',np.allclose(slopes.Coef,independent['threshold_DID'],rtol=0,atol=1e-5))
        check('DID_threshold_independent_SE',np.allclose(slopes.SE,independent['threshold_city_SE'],rtol=0,atol=1e-5))
        pl=pd.read_csv(o/'city_level_placebo_5000.csv')
        check('placebo_5000_valid',len(pl)==5000 and pl.valid_draw.eq(1).all())
        check('placebo_10_treated',pl.treated_cities.eq(10).all())
        main=pd.read_excel(o/'main_DID_city_cluster.xlsx').iloc[0]
        compare('placebo_coefficient_p',(np.count_nonzero(np.abs(pl.beta)>=abs(main.DID))+1)/5001,expected['placebo']['coefficient_p'])
        compare('placebo_studentized_p',(np.count_nonzero(np.abs(pl.t)>=abs(main.DID/main.City_cluster_SE))+1)/5001,expected['placebo']['studentized_p'])
        fast=json.loads((o/'city_placebo_fast_validation.json').read_text());check('placebo_independent_stata_check',fast['passed'] and fast['verified_draws']>=20)
        med=pd.read_csv(o/'city_bootstrap_indirect_FDR.csv');check('all_mediation_2000_valid',med.Reps.eq(2000).all() and med.Failed_Reps.eq(0).all())
        # Verify all six products and uncertainty from the saved draws.
        observed=pd.read_csv(o/'mediation_observed_stata.csv').set_index('Mediator')
        for _,row in med.iterrows():
            label=row['Mediator'];ref=observed.loc[label]
            for field in ['Path_A','Path_B','Total','Direct','N','Cities']:
                check('mediation_stata.'+label+'.'+field,np.isclose(row[field],ref[field],rtol=1e-7,atol=1e-8))
            check('mediation_product.'+label,np.isclose(row['Indirect'],ref.Path_A*ref.Path_B,rtol=1e-7,atol=1e-8))
            check('mediation_identity.'+label,np.isclose(ref.Total-ref.Direct,row['Indirect'],rtol=1e-7,atol=1e-8))
        for label in ['Green','Road']:
            row=med.set_index('Mediator').loc[label]
            check('mediation_N.'+label,row.N==16661)
            check('mediation_cities.'+label,row.Cities==94)
        ordered=med.Bootstrap_P.to_numpy().argsort()
        ranked=med.Bootstrap_P.to_numpy()[ordered]*len(med)/np.arange(1,len(med)+1)
        q=np.minimum.accumulate(ranked[::-1])[::-1].clip(0,1)
        check('mediation_FDR_recomputed',np.allclose(med.FDR_Q.to_numpy()[ordered],q,rtol=1e-7,atol=1e-8))
        diag=json.loads((o/'city_bootstrap_diagnostics.json').read_text())
        check('mediation_independent_stata_reference',diag['stata_observed_reference_verified'])
        table5=pd.read_excel(o/'mechanism_panelAB_city_cluster.xlsx').sort_values(['Panel','Mediator']).reset_index(drop=True)
        ref5=pd.read_csv(a.package/'verification/TABLE5_REFERENCE.csv').sort_values(['Panel','Mediator']).reset_index(drop=True)
        check('table5_panel_labels',table5[['Panel','Mediator']].equals(ref5[['Panel','Mediator']]))
        for field in ['Coef','SE','P','N','Cities','R2','DID_Coef','DID_SE','DID_P','FDR_Q']:
            check('table5_panel_city_cluster.'+field,np.allclose(table5[field],ref5[field],rtol=1e-6,atol=1e-8))
        sob=pd.read_csv(o/'sobel_city.csv').sort_values(['Mediator','Sample']).reset_index(drop=True)
        sob_ref=pd.read_csv(a.package/'verification/SOBEL_REFERENCE.csv').sort_values(['Mediator','Sample']).reset_index(drop=True)
        check('sobel_labels',sob[['Mediator','Sample']].equals(sob_ref[['Mediator','Sample']]))
        for field in sob_ref.select_dtypes(include='number').columns:
            check('sobel.'+field,np.allclose(sob[field],sob_ref[field],rtol=1e-6,atol=1e-8))
        chow=pd.read_excel(o/'full_chow_tests_city_cluster.xlsx')
        chow_ref=pd.read_csv(a.package/'verification/A4_REFERENCE.csv')
        for field in ['F_stat','df1','df2','P_value','N']:
            check('chow_binary_income.'+field,np.allclose(chow[field],chow_ref[field],rtol=1e-6,atol=1e-8))
        check('chow_all_city_clusters',chow.City_clusters.eq(94).all())
        sen=pd.read_csv(o/'sensitivity_geometry.csv')
        sen_ref=pd.read_csv(a.package/'verification/SENSITIVITY_REFERENCE.csv')
        check('sensitivity_OLS_geometry',np.allclose(sen,sen_ref,rtol=1e-6,atol=1e-10))
        flow=pd.read_csv(o/'analysis_sample_flow.csv')
        check('analysis_sample_flow',flow.N.tolist()==[86696,85386,83386,34331,34228,19759,16968,16661])
        tables=o/'manuscript_tables';idx=pd.read_csv(tables/'TABLE_INDEX.csv')
        check('19_manuscript_tables',len(idx)==19)
        for name in idx.file:check('manuscript_table.'+name,(tables/name).is_file() and len(pd.read_csv(tables/name))>0)
        covid=pd.read_csv(tables/'Table_1.csv').iloc[-1]
        check('Table1_COVID_N',covid.Obs==86654)
        check('Table1_COVID_SD',round(covid.SD,3)==.230)
        a5b=pd.read_csv(tables/'Appendix_Table_A5b.csv')
        check('A5b_descriptive_columns',a5b.columns.tolist()==['Variable','Retained_Mean','Retained_N','Missing_Mean','Missing_N'])
        check('A5b_retained_N',a5b.Retained_N.eq(16661).all())
        check('A5b_income_unavailable_N',a5b.Missing_N.max()==14469)
        check('A5b_outcome_N',a5b.loc[a5b.Variable.eq('rgoingl_clean'),'Missing_N'].iloc[0]==12507)
        check('five_formal_interactions',len(pd.read_csv(tables/'Appendix_Table_A3.csv'))==5)
        for name in ['Figure1_sample_flow.svg','Figure2_event_study.png','Figure3_sensitivity.png','Appendix_Figure_A1_placebo.png','Appendix_Figure_A2_balance.png','Appendix_Figure_A3_overlap.png']:
            check('manuscript_figure.'+name,(o/'figures'/name).is_file() and (o/'figures'/name).stat().st_size>1000)
        global_balance=pd.read_csv(o/'prepolicy_psm_global_balance.csv').set_index('Metric').Value
        check('PSM_global_balance_complete',global_balance.notna().all())
        check('PSM_probit_LR_after',round(global_balance['chi2aft'],2)==3.61)
        check('PSM_meanbias_before',round(global_balance['meanbiasbef'],1)==13.1)
        for label in med.Mediator:
            row=med.set_index('Mediator').loc[label]
            draw=pd.read_csv(o/f'city_bootstrap_draws_{label}.csv').Indirect.to_numpy()
            signp=min(1,2*(1+min(np.count_nonzero(draw<0),np.count_nonzero(draw>0)))/(len(draw)+1))
            check('bootstrap_draws.'+label,len(draw)==2000 and np.isfinite(draw).all())
            check('bootstrap_draws_SE.'+label,np.isclose(draw.std(ddof=1),row.Bootstrap_SE,rtol=1e-7,atol=1e-10))
            check('bootstrap_draws_CI.'+label,np.allclose(np.quantile(draw,[.025,.975]),[row.Pct_CI_L,row.Pct_CI_U],rtol=1e-7,atol=1e-10))
            check('bootstrap_draws_signp.'+label,np.isclose(signp,row.Bootstrap_P,rtol=1e-7,atol=1e-10))
        for name,marker in [('did_parallel_lines.log','DID_PARALLEL_LINES_COMPLETED'),('sobel_city.log','SOBEL_CITY_COMPLETED'),('figures_appendix.log','APPENDIX_FIGURES_COMPLETED')]:
            module_log=(a.run/'logs'/name).read_text(errors='replace')
            check('module_completion.'+name,marker in module_log and not re.search(r'^r\(\d+\);',module_log,re.M))
        linear_ref=pd.read_csv(a.package/'verification/LINEAR_REFERENCE.csv')
        for row in linear_ref.itertuples():
            fit=pd.read_csv(o/f'model_{row.model}.csv',na_values=['.'],skipinitialspace=True).set_index('Term').loc[row.term]
            for gotkey,refkey in [('Coef','b'),('SE','se'),('P','p'),('CI_L','lo'),('CI_U','hi'),('N','N'),('Cities','G'),('R2','r2')]:
                check('linear_table.'+row.model+'.'+row.term+'.'+gotkey,np.isclose(fit[gotkey],getattr(row,refkey),rtol=1e-6,atol=1e-8))
        t3=pd.read_csv(tables/'Table_3.csv')
        check('Table3_numeric_fit_columns',all(pd.api.types.is_numeric_dtype(t3[k]) for k in ['Coef','SE','P','N','R2','Pseudo_R2']))
        check('Table3_PSM_R2',round(t3.loc[t3.Model.eq('psm'),'R2'].iloc[0],3)==.117)
        check('FE_overall_R2',round(pd.read_csv(tables/'Appendix_Table_A6.csv').R2.iloc[0],4)==.5199)
        required=['full_chow_tests_city_cluster.xlsx','income_missingness_by_wave_treatment.xlsx','retained_vs_income_missing.xlsx','placebo_policy_timing_results.xlsx','prepolicy_psm_balance.xlsx','prepolicy_psm_diagnostics.dta','prepolicy_psm_balance.png','prepolicy_psm_overlap.png','covid_centered_marginal_effects.csv','mechanism_panelAB_city_cluster.xlsx']
        for name in required:check('output_present.'+name,(o/name).is_file() and (o/name).stat().st_size>0)
    report={'maintainer':'Xiaoai','passed':all(x['passed'] for x in checks),'mode':'build' if a.build_only else 'full','checks':checks,'comparison':'Aggregate references are checked after estimation; they are not inputs to sample selection or model estimation.'}
    (a.run/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    failed=[x['check'] for x in checks if not x['passed']]
    if failed:raise SystemExit('Verification failed: '+', '.join(failed))
    (a.run/'verification_passed.ok').write_text('All checks passed.\n')
    print(f'Verified {len(checks)} checks; data and outputs verified within the run directory.')

if __name__=='__main__':main()
