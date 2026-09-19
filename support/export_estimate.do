* Xiaoai: write the current fit without changing data, e(sample), or e().
capture program drop hcpp_export_estimate
program define hcpp_export_estimate
    args model terms
    tempname handle
    local df = e(df_r)
    local critical = cond(missing(`df'),invnormal(.975),invttail(`df',.025))
    file open `handle' using "$outpath/model_`model'.csv", write text replace
    file write `handle' "Model,Term,Coef,SE,P,CI_L,CI_U,N,Cities,R2,Pseudo_R2,Residual_df" _n
    foreach term of local terms {
        local p = cond(missing(`df'),2*normal(-abs(_b[`term']/_se[`term'])),2*ttail(`df',abs(_b[`term']/_se[`term'])))
        file write `handle' "`model',`term'," %24.16g (_b[`term']) "," %24.16g (_se[`term']) "," %24.16g (`p') "," ///
            %24.16g (_b[`term']-`critical'*_se[`term']) "," %24.16g (_b[`term']+`critical'*_se[`term']) "," ///
            %24.16g (e(N)) "," %24.16g (e(N_clust)) "," %24.16g (e(r2)) "," %24.16g (e(r2_p)) "," %24.16g (`df') _n
    }
    file close `handle'
end
