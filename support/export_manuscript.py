"""Xiaoai: manuscript-numbered aggregate CSV tables and a computed flow chart.

Only the current run is read. No reference results enter any calculation.
CSV preserves numerical precision; table formatting can be applied in Word.
"""
from pathlib import Path
from html import escape
import json
import sys
import numpy as np
import pandas as pd

VARIABLES = [
    ('Anergia-based proxy score','rgoingl'),('Gender','gender'),('Age','age'),
    ('Marital status','marry'),('Log real income per capita','log_real_inc_per'),
    ('Work status','rwork'),('Hukou type','rural2'),('Education','edu'),
    ('Number of children','hchild'),('Retirement','retire'),('ADL','adlab_c'),
    ('Smoking','smoken'),('Drinking','drinkl'),('Self-rated health','srh'),
    ('Green','GreenCoverageRateBD'),('Road','RoadSurAreaPerCap'),
    ('SO2','工业二氧化硫排放量吨'),('Medical','hosper'),('PM2.5','pm'),
    ('Reciprocal Social Interaction Score','act_12'),('COVID-19 cases (thousands)','covidnumber')]
CONTROLS = [v for _,v in VARIABLES[1:14]]

def main():
    run=Path(sys.argv[1]);out=run/'output';dest=out/'manuscript_tables';dest.mkdir()
    def read(name):
        path=out/name
        return pd.read_excel(path) if name.endswith('.xlsx') else pd.read_csv(path,na_values=['.'],skipinitialspace=True)
    def model(name):return read('model_'+name+'.csv')
    index=[]
    def save(label,frame,source,note):
        file=label+'.csv';frame.to_csv(dest/file,index=False,encoding='utf-8-sig',float_format='%.16g')
        index.append({'table':label,'file':file,'source':source,'note':note})
    data=pd.read_stata(run/'data/dataset 0507.dta',convert_categoricals=False)
    primary=pd.read_stata(out/'primary_estimation_sample.dta',convert_categoricals=False)
    for number,df in [(1,data),(2,primary)]:
        rows=[]
        for label,var in VARIABLES:
            x=df[var].dropna();rows.append(dict(Variable=label,Obs=len(x),Mean=x.mean(),SD=x.std(ddof=1),Min=x.min(),Max=x.max()))
        save(f'Table_{number}',pd.DataFrame(rows),'new dataset 0507.dta' if number==1 else 'primary_estimation_sample.dta',
             'Table 1 includes environmental-only merged rows and uses variable-specific nonmissing counts. COVID N=86,654 and SD rounds to 0.230; these correct two stale cells in draft0918.' if number==1 else 'Main analytical sample; pathway-specific availability can differ.')
    save('Table_3',pd.concat([model(n) for n in ['pooled','city','year','twfe','psm']],ignore_index=True),
         'model_*.csv','Columns are pooled, city FE, year FE, TWFE, and pre-policy PSM-DID; city clustering throughout.')
    save('Table_4',read('heterogeneity_subgroups_city_cluster.xlsx'),'heterogeneity_subgroups_city_cluster.xlsx',
         'Descriptive subgroup estimates; middle-income subgroup remains here, but is not an extra A3 interaction.')
    save('Table_5',read('mechanism_panelAB_city_cluster.xlsx'),'mechanism_panelAB_city_cluster.xlsx',
         'Panel A retains available pathway/control cases even if outcome missing. Panel B also requires outcome. BH-FDR separately by panel.')
    g=read('sensitivity_geometry.csv').iloc[0];f2=(g.b/g.se)**2/g.df
    rv=(np.sqrt(f2*f2+4*f2)-f2)/2
    sen=[{'Quantity':'DID-outcome partial R2','Multiplier':np.nan,'Value':f2/(1+f2)},
         {'Quantity':'Point-estimate robustness value','Multiplier':np.nan,'Value':rv}]
    for k in [1,2,3]:
        rd=k*g.r2_srh_d/(1-g.r2_srh_d)
        rz=k*g.r2_srh_d**2/((1-k*g.r2_srh_d)*(1-g.r2_srh_d))
        ry=((np.sqrt(k)+np.sqrt(rz))/np.sqrt(1-rz))**2*g.r2_srh_y/(1-g.r2_srh_y)
        adj=g.b+np.sqrt(ry*rd/(1-rd))*g.se*np.sqrt(g.df)
        sen.extend([dict(Quantity='R2dz.x',Multiplier=k,Value=rd),dict(Quantity='R2yz.dx',Multiplier=k,Value=ry),dict(Quantity='Bias-adjusted DID',Multiplier=k,Value=adj)])
    save('Table_6a',pd.DataFrame(sen),'sensitivity_geometry.csv','Ordinary-OLS residual geometry; not city-clustered significance sensitivity.')
    robust=pd.concat([model(n) for n in ['twfe','additive_covid','lpm','ologit','logit','individual_fe']],ignore_index=True)
    robust['Interpretation']=np.where(robust.Model.isin(['ologit','logit']),'Diagnostic only; see nonlinear warnings','Linear sensitivity specification')
    save('Table_6b',robust,'model_*.csv; nonlinear_cityFE_citycluster.csv','No nonconverged generalized ordered logit is reported. Logit coefficients are not probability-scale effects.')
    covid=pd.concat([model('additive_covid'),model('covid_centered')],ignore_index=True)
    margins=read('covid_centered_marginal_effects.csv');margins=margins[margins.Distribution.eq('Treated cities')].copy()
    margins=margins.rename(columns={'Estimate':'Coef','Level':'Term'});margins['Model']='Conditional DID'
    save('Table_6c',pd.concat([covid,margins],ignore_index=True),'model_*covid*.csv; covid_centered_marginal_effects.csv',
         'Centered at unique treated-city 2020 mean. Margins use the complete city-clustered coefficient covariance.')
    sob=read('sobel_city.csv');save('Appendix_Table_A1a',sob[sob.Sample.eq('original')],
         'sobel_city.csv','Traditional Sobel is supplementary, unadjusted, and uses path-specific samples. Joint delta diagnostic is also included.')
    save('Appendix_Table_A1b',read('city_bootstrap_indirect_FDR.csv'),'city_bootstrap_indirect_FDR.csv',
         'Common pathway-specific samples; 2,000 city draws; empirical sign-tail summaries; all six q>0.05.')
    ps=read('prepolicy_means_psmdid_summary.xlsx');bal=read('prepolicy_psm_global_balance.csv')
    stats=[{'Metric':k,'Value':v} for k,v in ps.iloc[0].items()]
    stats+=bal.to_dict('records');b=read('prepolicy_psm_balance.xlsx')
    stats += [{'Metric':'max_abs_bias_before','Value':b.Bias_U.abs().max()},{'Metric':'max_abs_bias_after','Value':b.Bias_M.abs().max()}]
    save('Appendix_Table_A2a',pd.DataFrame(stats),'prepolicy_means_psmdid_summary.xlsx; prepolicy_psm_global_balance.csv; prepolicy_psm_balance.xlsx',
         'Score-model statistics use logit; balance statistics use the auxiliary probit in pstest. They are distinct.')
    save('Appendix_Table_A2b',b,'prepolicy_psm_balance.xlsx','All matching covariates are 2011/2013/2015 respondent means; max matched bias is slightly over 5%.')
    save('Appendix_Table_A3',read('heterogeneity_interactions_city_cluster.xlsx'),'heterogeneity_interactions_city_cluster.xlsx','Five approved contrasts only; all p>0.05.')
    save('Appendix_Table_A4',read('full_chow_tests_city_cluster.xlsx'),'full_chow_tests_city_cluster.xlsx','Income is low versus combined middle/high; Full Chow tests all specified group intercept/slopes, not DID alone.')
    mis=read('income_missingness_by_wave_treatment.xlsx');mis['Missing_percent']=mis.Income_Missing_Rate*100
    total=pd.DataFrame([dict(iwy='All',treat='All',Eligible_N=mis.Eligible_N.sum(),Income_Missing_N=mis.Income_Missing_N.sum(),Income_Missing_Rate=mis.Income_Missing_N.sum()/mis.Eligible_N.sum(),Missing_percent=100*mis.Income_Missing_N.sum()/mis.Eligible_N.sum())])
    save('Appendix_Table_A5a',pd.concat([mis,total],ignore_index=True),'income_missingness_by_wave_treatment.xlsx','Known age >=45 and urban residence; unavailable log income includes nonpositive income.')
    save('Appendix_Table_A5b',read('retained_vs_income_missing.xlsx'),'retained_vs_income_missing.xlsx','Available-case comparisons; difference = income-missing minus retained. Does not identify selection bias in DID.')
    fe=read('individual_FE_citycluster.xlsx');one=primary.groupby('ID').size();fe['Respondents']=(one>1).sum();fe['Singleton_observations_excluded']=(one==1).sum()
    fe['R2']=model('individual_fe').R2.iloc[0]
    save('Appendix_Table_A6',fe,'individual_FE_citycluster.xlsx; primary_estimation_sample.dta','Respondent/year FE, city clustering; gender and age absorbed.')
    wild=read('main_did_wild_cluster_results.csv');ma=read('main_DID_city_cluster.xlsx').iloc[0]
    wild['City_t']=ma.DID/ma.City_cluster_SE;wild['CI_L']=ma.CI_L;wild['CI_U']=ma.CI_U
    save('Appendix_Table_A7',wild,'main_did_wild_cluster_results.csv; main_DID_city_cluster.xlsx','Wild bootstrap uses areg equivalent sample/point estimate; conventional uncertainty is principal reghdfe.')
    save('Appendix_Table_A8',read('placebo_policy_timing_results.csv'),'placebo_policy_timing_results.csv','Only 2011/2013/2015 waves, actual pilot status, fake 2013/2015 onset.')
    pd.DataFrame(index).to_csv(dest/'TABLE_INDEX.csv',index=False,encoding='utf-8-sig')
    (dest/'README.md').write_text('# Manuscript tables\n\nGenerated from this run only. CSV retains full precision; stars refer to unadjusted p and do not replace FDR q.\n\n'+
        '\n'.join(f"- **{i['table']}**: `{i['file']}`. {i['note']}" for i in index))
    # Compute the manuscript's selection flow, distinct from intermediate merge counts.
    person=data.loc[data.ID.notna() & data.ID.ne('') & data.wave.notna()].copy()
    older=person.loc[~person.age.lt(45)];urban=older.loc[older.rural.eq(0)]
    known=urban.loc[urban.age.notna()];income=known.loc[known.log_real_inc_per.notna()]
    covars=income.dropna(subset=CONTROLS);complete=covars.dropna(subset=['rgoingl'])
    if set(map(tuple,complete[['ID','iwy']].to_numpy()))!=set(map(tuple,primary[['ID','iwy']].to_numpy())):
        raise ValueError('Flow terminal sample differs from primary estimation sample.')
    frames=[data,person,older,urban,known,income,covars,complete]
    labels=['Rebuilt merged file','Identified respondent-wave records','After excluding known ages below 45',
            'Urban observations','Known age >=45 and urban','Usable log household income',
            'Complete required covariates','Final analytical sample']
    reasons=['Environment-only records','Known age below 45','Rural residence','Missing age','Unavailable log income','Other missing covariates','Missing outcome']
    counts=[len(x) for x in frames]
    pd.DataFrame({'Stage':labels,'N':counts}).to_csv(out/'analysis_sample_flow.csv',index=False)
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="970" viewBox="0 0 1000 970">',
         '<rect width="1000" height="970" fill="white"/>',
         '<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8" fill="#466378"/></marker></defs>']
    cities=primary.drop_duplicates('city');nt=int(cities.treat.sum())
    for i,(label,n) in enumerate(zip(labels,counts)):
        y=20+i*116;fill='#e1efea' if i==7 else '#edf3f7'
        svg.append(f'<rect x="20" y="{y}" width="575" height="78" rx="4" fill="{fill}" stroke="#466378"/>')
        svg.append(f'<text x="307" y="{y+24}" text-anchor="middle" font-family="Arial,sans-serif" font-size="16" font-weight="bold">{escape(label)}</text>')
        detail=f'{n:,} rows' if i==0 else f'{n:,} person-wave observations'
        if i==7:detail=f'{n:,} person-waves; {primary.ID.nunique():,} respondents'
        svg.append(f'<text x="307" y="{y+48}" text-anchor="middle" font-family="Arial,sans-serif" font-size="15">{detail}</text>')
        if i==7:svg.append(f'<text x="307" y="{y+67}" text-anchor="middle" font-family="Arial,sans-serif" font-size="15">{len(cities)} cities: {nt} treated, {len(cities)-nt} control</text>')
        else:
            svg.append(f'<path d="M307,{y+79} V{y+113}" stroke="#466378" fill="none" marker-end="url(#arrow)"/>')
            svg.append(f'<path d="M310,{y+96} H635" stroke="#8293a1" marker-end="url(#arrow)"/>')
            svg.append(f'<text x="645" y="{y+102}" font-family="Arial,sans-serif" font-size="14">{escape(reasons[i])}: {counts[i]-counts[i+1]:,}</text>')
    svg.append('</svg>');(out/'figures/Figure1_sample_flow.svg').write_text('\n'.join(svg))
    (out/'manuscript_exports.ok').write_text('19 manuscript-numbered aggregate tables and computed flow chart exported.\n')
    print('MANUSCRIPT_EXPORTS_COMPLETED: 19 tables; sample selection flow calculated from new data.')

if __name__=='__main__':main()
