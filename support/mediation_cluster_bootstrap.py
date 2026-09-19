"""Xiaoai: reproducible nonparametric city bootstrap of six path products.

Whole cities are sampled with replacement. Multiplicity-weighted city-demeaned
crossproducts are equivalent to copying entire cities and giving every sampled
copy a separate fixed-effect identifier. Year effects are re-estimated in every
draw. All path equations use one mediator-specific common complete-case sample.
"""
from __future__ import annotations
import hashlib
import json
import sys
from pathlib import Path
from statistics import NormalDist
import numpy as np
import pandas as pd

CONTROLS=['gender','marry','log_real_inc_per','rwork','rural2','edu','hchild','retire','adlab_c','smoken','drinkl','srh','age']
MEDIATORS=[('Green','GreenCoverageRateBD'),('Road','RoadSurAreaPerCap'),('SO2','工业二氧化硫排放量吨'),('Medical','hosper'),('PM25','pm'),('Social','act_12')]


def drop_singletons(frame):
    """Mirror reghdfe's iterative removal of singleton city/year FE groups."""
    frame=frame.copy()
    while len(frame):
        keep=np.ones(len(frame),dtype=bool)
        for column in ['city','iwy']:
            keep &= frame.groupby(column)[column].transform('size').to_numpy()>1
        if keep.all():break
        frame=frame.loc[keep].copy()
    return frame


def demean_by_city(frame,columns):
    values=frame[columns].astype(float)
    return (values-values.groupby(frame.city).transform('mean')).to_numpy()


def prepare_equation(frame,dependent,regressors):
    y=demean_by_city(frame,[dependent]).ravel()
    x=demean_by_city(frame,regressors)
    scale=np.sqrt(np.sum(x*x,axis=0))
    # Redundant nuisance terms may be absorbed, but target coefficients must
    # remain estimable. Current common samples have full-rank active designs.
    active=scale>0
    if not active[0]:
        raise ValueError('Target regressor has no within-city variation.')
    dropped=[name for name,ok in zip(regressors,active) if not ok]
    x=x[:,active]/scale[active]
    rank=int(np.linalg.matrix_rank(x))
    if rank!=x.shape[1]:
        raise ValueError('Observed active design is rank deficient; inspect collinearity rather than returning a pseudoinverse target.')
    codes,cities=pd.factorize(frame.city,sort=True)
    xx=np.zeros((len(cities),x.shape[1],x.shape[1]));xy=np.zeros((len(cities),x.shape[1]))
    for g in range(len(cities)):
        xg=x[codes==g];yg=y[codes==g];xx[g]=xg.T@xg;xy[g]=xg.T@yg
    # Independent rectangular SVD solution verifies the observed crossproduct fit.
    observed_scaled=np.linalg.solve(xx.sum(axis=0),xy.sum(axis=0))
    observed_rect=np.linalg.lstsq(x,y,rcond=None)[0]
    if not np.allclose(observed_scaled,observed_rect,rtol=1e-8,atol=1e-8):
        raise ValueError('Observed crossproduct fit fails rectangular-SVD verification.')
    full=np.zeros(len(regressors));full[active]=observed_scaled/scale[active]
    return {'xx':xx,'xy':xy,'scale':scale[active],'active':active,'cities':cities,'observed':full,
            'rank':rank,'columns':x.shape[1],'dropped':dropped,'x':x,'y':y,'codes':codes,
            'condition':float(np.linalg.cond(x)),'max_observed_svd_difference':float(np.max(np.abs(observed_scaled-observed_rect)))}


def solve_draws(eq,counts):
    lhs=np.einsum('bg,gij->bij',counts,eq['xx'],optimize=True)
    rhs=np.einsum('bg,gi->bi',counts,eq['xy'],optimize=True)
    eigenvalues=np.linalg.eigvalsh(lhs)
    tol=eigenvalues[:,-1]*lhs.shape[1]*np.finfo(float).eps
    ranks=np.sum(eigenvalues>tol[:,None],axis=1)
    valid=(ranks==lhs.shape[1]) & np.isfinite(eigenvalues).all(axis=1)
    result=np.full((len(counts),len(eq['active'])),np.nan)
    condition=np.full(len(counts),np.inf)
    for j in np.flatnonzero(valid):
        try:
            b=np.linalg.solve(lhs[j],rhs[j])/eq['scale']
            valid[j]=np.isfinite(b).all()
            if valid[j]:result[j,eq['active']]=b;result[j,~eq['active']]=0
            condition[j]=eigenvalues[j,-1]/eigenvalues[j,0]
        except np.linalg.LinAlgError:
            valid[j]=False
    return result,valid,ranks,condition


def main():
    if len(sys.argv)!=5:
        raise SystemExit('Usage: mediation_cluster_bootstrap.py ANALYSIS_DTA OUTPUT_CSV REPS SEED')
    data_path=Path(sys.argv[1]);output=Path(sys.argv[2]);reps=int(sys.argv[3]);seed=int(sys.argv[4])
    if reps!=2000 or seed!=2025:
        raise ValueError('The prespecified manuscript run requires 2,000 draws and seed 2025.')
    output.parent.mkdir(parents=True,exist_ok=True)
    data=pd.read_stata(data_path,convert_categoricals=False)
    data=data.loc[data.age.ge(45)&data.age.notna()&data.rural.eq(0)].copy()
    if not data.iwy.dropna().isin([2011,2013,2015,2018,2020]).all():
        raise ValueError('Unexpected survey year.')
    # Freeze the primary complete-case sample before mediator-specific losses.
    baseline_columns=['rgoingl','did','city','iwy']+CONTROLS
    data=data.dropna(subset=baseline_columns)
    data=data.loc[data.city.astype(str).str.strip().ne('')].copy()
    data=drop_singletons(data)
    reference_path=output.parent/'mediation_observed_stata.csv'
    reference=pd.read_csv(reference_path).set_index('Mediator') if reference_path.exists() else None
    results=[];diagnostics=[]
    for label,mediator in MEDIATORS:
        needed=['rgoingl',mediator,'did','city','iwy']+CONTROLS
        sample=data[needed].dropna().copy()
        sample=drop_singletons(sample)
        numeric=sample.select_dtypes(include=[np.number])
        if not np.isfinite(numeric.to_numpy(dtype=float)).all():
            raise ValueError(f'{label}: nonfinite numeric input.')
        years=pd.get_dummies(sample.iwy.astype(int),prefix='year',drop_first=True,dtype=float)
        sample=pd.concat([sample,years],axis=1)
        common=['did']+CONTROLS+list(years.columns)
        a=prepare_equation(sample,mediator,common)
        b=prepare_equation(sample,'rgoingl',[mediator]+common)
        t=prepare_equation(sample,'rgoingl',common)
        if not np.array_equal(a['cities'],b['cities']):raise ValueError('City ordering mismatch.')
        path_a=float(a['observed'][0]);path_b=float(b['observed'][0]);indirect=path_a*path_b
        g=len(a['cities'])
        if not np.isclose(float(t['observed'][0]),float(b['observed'][1])+indirect,rtol=1e-7,atol=1e-9):
            raise ValueError(f'{label}: total/direct/product identity failed.')
        stata_errors={}
        if reference is not None:
            if label not in reference.index:raise ValueError(f'{label}: missing Stata reference.')
            ref=reference.loc[label]
            if int(ref.N)!=len(sample) or int(ref.Cities)!=g:
                raise ValueError(f'{label}: sample count or city count differs from Stata.')
            observed={'Path_A':path_a,'Path_B':path_b,'Total':float(t['observed'][0]),'Direct':float(b['observed'][1])}
            for name,value in observed.items():
                stata_errors[name]=float(abs(value-float(ref[name])))
                if not np.isclose(value,float(ref[name]),rtol=1e-7,atol=1e-8):
                    raise ValueError(f'{label}: {name} differs from Stata ({value} versus {ref[name]}).')
        # Reset per mediator, as in the final 2026-09-07 implementation. RNG
        # scope is explicit; changing mediator order cannot alter another draw.
        rng=np.random.Generator(np.random.PCG64(seed))
        selections=rng.integers(0,g,size=(reps,g))
        counts=np.zeros((reps,g),dtype=float)
        np.add.at(counts,(np.repeat(np.arange(reps),g),selections.ravel()),1.0)
        assert (counts.sum(axis=1)==g).all()
        boot_a,ok_a,rank_a,cond_a=solve_draws(a,counts)
        boot_b,ok_b,rank_b,cond_b=solve_draws(b,counts)
        boot=boot_a[:,0]*boot_b[:,0]
        valid=ok_a&ok_b&np.isfinite(boot)
        # Verify initial draws directly on a rectangular weighted design,
        # independently of the Gram-matrix implementation.
        checks=[]
        for j in range(min(10,reps)):
            if not valid[j]:continue
            weight=np.sqrt(counts[j,a['codes']])
            ar=np.linalg.lstsq(a['x']*weight[:,None],a['y']*weight,rcond=None)[0][0]/a['scale'][0]
            br=np.linalg.lstsq(b['x']*weight[:,None],b['y']*weight,rcond=None)[0][0]/b['scale'][0]
            error=abs(ar*br-boot[j]);checks.append(float(error))
            if error>1e-8:raise ValueError(f'{label}: bootstrap draw {j+1} fails independent SVD verification.')
        draws=pd.DataFrame({'Draw':np.arange(1,reps+1),'Indirect':boot,'Path_A':boot_a[:,0],
                            'Path_B':boot_b[:,0],'Valid':valid,'Rank_A':rank_a,'Rank_B':rank_b,
                            'Scaled_Gram_Condition_A':cond_a,'Scaled_Gram_Condition_B':cond_b})
        draws.to_csv(output.parent/f'city_bootstrap_draws_{label}.csv',index=False)
        # Persist exact sampled multiplicities without expanding respondent data.
        np.savez_compressed(output.parent/f'city_bootstrap_city_counts_{label}.npz',
                            counts=counts.astype(np.int16),cities=a['cities'].to_numpy(dtype=str))
        valid_boot=boot[valid]
        diagnostic={'Mediator':label,'N':len(sample),'Cities':g,'Attempted':reps,'Valid':int(valid.sum()),
                    'Failed':int((~valid).sum()),'Actual_Years':sorted(int(v) for v in sample.iwy.unique()),
                    'Dropped_Nuisance_A':a['dropped'],'Dropped_Nuisance_B':b['dropped'],
                    'Observed_Rank_A':a['rank'],'Observed_Rank_B':b['rank'],
                    'Observed_Condition_A':a['condition'],'Observed_Condition_B':b['condition'],
                    'Stata_Observed_Path_Errors':stata_errors,
                    'First_10_Max_Rectangular_SVD_Error':max(checks,default=0.0)}
        diagnostics.append(diagnostic)
        if len(valid_boot)<2:raise ValueError(f'{label}: fewer than two estimable draws.')
        pct_l,pct_u=np.quantile(valid_boot,[.025,.975],method='linear')
        nd=NormalDist();prop=float(np.clip(np.mean(valid_boot<=indirect),.0001,.9999));z0=nd.inv_cdf(prop)
        probs=[nd.cdf(2*z0+nd.inv_cdf(.025)),nd.cdf(2*z0+nd.inv_cdf(.975))]
        bc_l,bc_u=np.quantile(valid_boot,probs,method='linear')
        nneg=int((valid_boot<0).sum());npos=int((valid_boot>0).sum())
        p_boot=min(1.,2*(min(nneg,npos)+1)/(len(valid_boot)+1))
        results.append({'Mediator':label,'Path_A':path_a,'Path_B':path_b,'Total':float(t['observed'][0]),
                        'Direct':float(b['observed'][1]),'Indirect':indirect,'Bootstrap_SE':float(valid_boot.std(ddof=1)),
                        'Pct_CI_L':float(pct_l),'Pct_CI_U':float(pct_u),'BC_CI_L':float(bc_l),'BC_CI_U':float(bc_u),
                        'Bootstrap_P':p_boot,'Reps':len(valid_boot),'Attempted_Reps':reps,'Failed_Reps':int((~valid).sum()),
                        'N':len(sample),'Cities':g,'Seed':seed})
        print(f'{label}: N={len(sample)}, cities={g}, valid={valid.sum()}/{reps}',flush=True)
    result=pd.DataFrame(results)
    pvalues=result.Bootstrap_P.to_numpy();order=np.argsort(pvalues,kind='stable')
    q_ordered=np.minimum.accumulate((pvalues[order]*len(result)/np.arange(1,len(result)+1))[::-1])[::-1]
    q=np.empty(len(result));q[order]=np.minimum(q_ordered,1)
    result['Bonferroni_P']=np.minimum(pvalues*len(result),1)
    result['Rank']=pd.Series(pvalues).rank(method='first').to_numpy().astype(int)
    result['FDR_Q']=q;result['FDR_reject_005']=q<=.05
    audit={'author':'Xiaoai','input_sha256':hashlib.sha256(data_path.read_bytes()).hexdigest(),
           'seed':seed,'rng':'NumPy PCG64, reset to seed 2025 separately for each mediator',
           'numpy_version':np.__version__,'pandas_version':pd.__version__,'replications':reps,
           'stata_observed_reference_verified':reference is not None,
           'stata_reference_sha256':hashlib.sha256(reference_path.read_bytes()).hexdigest() if reference is not None else None,
           'sample_definition':'primary outcome/control complete cases and mediator-specific complete cases; iterative city/year singletons removed',
           'CI':'percentile and bias-corrected (BC, not BCa); linear quantile interpolation',
           'p_value':'two-sided bootstrap sign-tail summary, 2*(min(n_negative,n_positive)+1)/(valid+1), capped at 1; not a null-imposed bootstrap-t test',
           'FDR':'Benjamini-Hochberg across the six sign-tail p values','models':diagnostics}
    (output.parent/'city_bootstrap_diagnostics.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2))
    if any(x['Failed'] for x in diagnostics):
        result.to_csv(output.parent/'city_bootstrap_incomplete_diagnostic_summary.csv',index=False)
        raise ValueError('At least one of the 2,000 planned city draws is rank-deficient or nonfinite. Draw diagnostics saved; primary summary withheld pending review.')
    temp=output.with_name(output.name+'.tmp')
    result.sort_values('Rank').to_csv(temp,index=False,encoding='utf-8-sig');temp.replace(output)

if __name__=='__main__':main()
