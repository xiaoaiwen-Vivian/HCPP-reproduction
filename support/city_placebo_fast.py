"""Xiaoai: city-assignment placebo FWL calculations, gated by Stata verification."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import pandas as pd

CONTROLS = ['gender','marry','log_real_inc_per','rwork','rural2','edu','hchild','retire','adlab_c','smoken','drinkl','srh','age']


def checksum(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def compute(args):
    out = Path(args.output_dir)
    d = pd.read_stata(args.sample, convert_categoricals=False).sort_values('placebo_city_id', kind='stable')
    a = pd.read_csv(args.assignments)
    assignment = a.pivot(index='draw', columns='placebo_city_id', values='fake_treat').sort_index().sort_index(axis=1)
    cities = np.sort(d.placebo_city_id.unique())
    if not np.array_equal(assignment.columns.to_numpy(), cities):
        raise ValueError('Assignment cities differ from estimation sample.')
    if assignment.isna().any().any() or not np.isin(assignment.to_numpy(), [0,1]).all():
        raise ValueError('Incomplete or nonbinary treatment assignment.')
    n_treated = int(d.groupby('city').treat.first().sum())
    if len(assignment) != 5000 or not (assignment.sum(axis=1) == n_treated).all():
        raise ValueError('Expected exactly 5,000 assignments, preserving the observed number of treated cities.')
    if not (d.age.ge(45) & d.age.notna() & d.rural.eq(0)).all():
        raise ValueError('Invalid age/residence in frozen sample.')
    n, g = len(d), len(cities)
    if (d.groupby('city').placebo_city_id.nunique() != 1).any() or d.city.nunique() != g:
        raise ValueError('City identifier mismatch.')
    codes = pd.Categorical(d.placebo_city_id, categories=cities).codes
    starts = np.r_[0, np.flatnonzero(np.diff(codes)) + 1]
    years = pd.get_dummies(d.iwy, prefix='year', drop_first=True, dtype=float)
    controls = pd.concat([d[CONTROLS].astype(float), years], axis=1)
    c = (controls - controls.groupby(d.placebo_city_id).transform('mean')).to_numpy()
    scale = np.sqrt(np.sum(c*c, axis=0))
    if np.any(scale == 0):
        raise ValueError('Zero-variation nuisance regressor; inspect the estimation sample.')
    c = c / scale
    if np.linalg.matrix_rank(c) != c.shape[1]:
        raise ValueError('Rank-deficient nuisance design; use Stata reference.')
    y = (d.rgoingl_clean - d.groupby('placebo_city_id').rgoingl_clean.transform('mean')).to_numpy()
    post = (d.post - d.groupby('placebo_city_id').post.transform('mean')).to_numpy()
    gram = c.T @ c
    residual_y = y - c @ np.linalg.solve(gram, c.T @ y)
    k = args.df_model + args.df_absorbed + 1
    if k != c.shape[1] + 2:
        raise ValueError(f'Stata effective parameter count {k} differs from the full-rank FWL design.')
    adjustment = (n-1)/(n-k) * g/(g-1)

    def evaluate(assign):
        z = post[:,None] * assign[:,codes].T
        v = z - c @ np.linalg.solve(gram, c.T @ z)
        denominator = np.sum(v*v, axis=0)
        valid = np.isfinite(denominator) & (denominator > 1e-12)
        b = np.full(len(assign), np.nan); se = b.copy(); leverage = b.copy()
        b[valid] = (residual_y @ v[:,valid]) / denominator[valid]
        e = residual_y[:,None] - v*b[None,:]
        cluster_scores = np.add.reduceat(v*e, starts, axis=0)
        se[valid] = np.sqrt(adjustment*np.sum(cluster_scores[:,valid]**2,axis=0)/denominator[valid]**2)
        leverage[valid] = np.max(np.add.reduceat(v[:,valid]**2, starts, axis=0),axis=0)/denominator[valid]
        valid &= np.isfinite(b) & np.isfinite(se) & (se>0)
        return b,se,valid,denominator,leverage

    actual = d.groupby('placebo_city_id',sort=True).treat.first().to_numpy()[None,:]
    if actual.sum() != n_treated or (d.groupby('placebo_city_id').treat.nunique() != 1).any():
        raise ValueError('Observed treatment must be constant within each sampled city.')
    ab, ase, av, _, _ = evaluate(actual)
    if not av[0] or abs(ab[0]-args.actual_beta)>1e-8 or abs(ase[0]-args.actual_se)>1e-8:
        raise ValueError(f'Observed FWL/Stata mismatch: b={ab[0]}, se={ase[0]}.')
    rows=[]
    values=assignment.to_numpy(dtype=float)
    for start in range(0,len(values),64):
        b,se,valid,den,lev=evaluate(values[start:start+64])
        for j in range(len(b)):
            rows.append({'draw':int(assignment.index[start+j]),'beta':b[j],'se':se[j],'t':b[j]/se[j],
                         'treated_cities':n_treated,'valid_draw':int(valid[j]),'N':n,'G':g,
                         'residualized_treatment_ss':den[j],'max_city_leverage':lev[j]})
    result=pd.DataFrame(rows)
    # First 20 assignments plus numerical stress cases: highest leverage, smallest
    # treatment residual variation, and most extreme t statistics. Selection is
    # solely for implementation validation and never changes the 5,000 draws.
    selected=set(result.draw.iloc[:20])
    for col,ascending in [('max_city_leverage',False),('residualized_treatment_ss',True),('t',True),('t',False)]:
        selected.update(result.sort_values(col,ascending=ascending).draw.iloc[:2])
    result['verify_draw']=result.draw.isin(selected).astype(int)
    result.to_csv(out/'city_placebo_fast_candidate.csv',index=False)
    pd.DataFrame({'draw':sorted(selected)}).to_csv(out/'city_placebo_verification_draws.csv',index=False)
    diagnostic={'author':'Xiaoai','method':'city-demeaned FWL with city-cluster sandwich',
                'N':n,'G':g,'df_model':args.df_model,'df_absorbed':args.df_absorbed,'effective_parameters':k,
                'finite_sample_adjustment':adjustment,'actual_beta_fwl':float(ab[0]),'actual_se_fwl':float(ase[0]),
                'maximum_allowed_absolute_error':1e-8,'requested_draws':5000,'valid_draws':int(result.valid_draw.sum()),
                'verification_draws':sorted(int(x) for x in selected),
                'assignment_rng':'Stata 18 mt64; seed 2025; sorted draw and canonical city ID',
                'numpy_version':np.__version__,'pandas_version':pd.__version__,
                'sample_sha256':checksum(args.sample),'assignments_sha256':checksum(args.assignments)}
    (out/'city_placebo_fast_diagnostics.json').write_text(json.dumps(diagnostic,ensure_ascii=False,indent=2))


def verify(args):
    out=Path(args.output_dir)
    c=pd.read_csv(out/'city_placebo_fast_candidate.csv')
    s=pd.read_csv(out/'city_placebo_stata_verification.csv')
    selected=c[c.verify_draw.eq(1)]
    if set(selected.draw)!=set(s.draw) or len(s)<20:
        raise ValueError('Stata verification must cover every selected draw and at least 20 draws.')
    m=selected.merge(s,on='draw',suffixes=('_python','_stata'),validate='one_to_one')
    errors={k:float(np.max(np.abs(m[k+'_python']-m[k+'_stata']))) for k in ['beta','se','t']}
    ok=all(np.isfinite(list(errors.values()))) and all(v<=1e-8 for v in errors.values())
    ok=ok and bool((m.N_python==m.N_stata).all()) and bool((m.G_python==m.G_stata).all())
    record={'author':'Xiaoai','passed':bool(ok),'verified_draws':len(m),'max_absolute_errors':errors,
            'N_G_exactly_equal':bool((m.N_python==m.N_stata).all() and (m.G_python==m.G_stata).all()),
            'candidate_sha256':checksum(out/'city_placebo_fast_candidate.csv'),
            'stata_verification_sha256':checksum(out/'city_placebo_stata_verification.csv')}
    (out/'city_placebo_fast_validation.json').write_text(json.dumps(record,indent=2))
    if not ok:
        raise ValueError(f'Fast placebo validation failed: {errors}')
    (out/'city_placebo_fast_verified.ok').write_text('Verified against Stata reghdfe; Xiaoai\n')


def main():
    p=argparse.ArgumentParser();s=p.add_subparsers(dest='command',required=True)
    c=s.add_parser('compute');c.add_argument('--sample',required=True);c.add_argument('--assignments',required=True)
    c.add_argument('--output-dir',required=True)
    for name in ['actual-beta','actual-se','actual-p']:
        c.add_argument('--'+name,type=float,required=True)
    c.add_argument('--df-model',type=int,required=True);c.add_argument('--df-absorbed',type=int,required=True)
    v=s.add_parser('verify');v.add_argument('--output-dir',required=True)
    a=p.parse_args();compute(a) if a.command=='compute' else verify(a)

if __name__=='__main__': main()
