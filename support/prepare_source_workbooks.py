"""Read-only extraction of the source Excel tables used by the Stata build."""

from __future__ import annotations

import sys
from pathlib import Path
import pandas as pd


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "Usage: prepare_source_workbooks.py CITYBOOK MUNICIPAL COVID OUTDIR"
        )

    citybook, municipal, covidbook, outdir = map(Path, sys.argv[1:])
    outdir.mkdir(parents=True, exist_ok=True)
    survey_years = {2011, 2013, 2015, 2018, 2020}

    city = pd.read_excel(
        citybook,
        sheet_name="原始数据",
        usecols="A,B,C,P,DA,FB,GG",
    )
    city.columns = [
        "iwy",
        "province",
        "city",
        "registered_population_10k",
        "fixed_asset_investment_10k",
        "hospitals",
        "so2_tons",
    ]
    city["iwy"] = pd.to_numeric(city["iwy"], errors="coerce")
    city = city[city["iwy"].isin(survey_years)].copy()
    city["iwy"] = city["iwy"].astype(int)
    city["city"] = city["city"].replace({"北京市": "北京", "天津市": "天津"})
    city.to_csv(outdir / "city_yearbook_extract.csv", index=False, encoding="utf-8-sig")

    # Extract road area and green coverage for the five survey years.
    # The municipal source includes Beijing, Tianjin, Shanghai, and Chongqing.
    muni = pd.read_excel(municipal)
    muni = muni[["iwy", "province", "city", "RoadSurAreaPerCap", "GreenCoverageRateBD"]].copy()
    muni["iwy"] = pd.to_numeric(muni["iwy"], errors="coerce")
    muni = muni[muni["iwy"].isin(survey_years)].copy()
    muni["iwy"] = muni["iwy"].astype(int)
    muni["city"] = muni["city"].replace({"北京市": "北京", "天津市": "天津"})
    for col in ["RoadSurAreaPerCap", "GreenCoverageRateBD"]:
        muni[col] = pd.to_numeric(muni[col], errors="coerce")
    if muni.duplicated(["city", "iwy"]).any():
        raise ValueError("Municipal source has duplicate city-year keys.")
    municipalities = muni[muni.city.isin(["北京", "天津", "上海市", "重庆市"])]
    if len(municipalities) != 20 or municipalities[["RoadSurAreaPerCap", "GreenCoverageRateBD"]].isna().any().any():
        raise ValueError("Municipal source must contain nonmissing road and green-coverage values for four municipalities and five survey years.")
    muni.to_csv(outdir / "municipal_extract.csv", index=False, encoding="utf-8-sig")

    covid = pd.read_excel(covidbook, usecols=["日期", "地区", "累计确诊"])
    covid["日期"] = pd.to_datetime(covid["日期"], errors="coerce")
    covid["iwy"] = covid["日期"].dt.year
    covid["covid_cases"] = pd.to_numeric(covid["累计确诊"], errors="coerce")
    covid = covid[covid["iwy"].notna() & covid["地区"].notna()].copy()
    covid["iwy"] = covid["iwy"].astype(int)
    covid = (
        covid.groupby(["地区", "iwy"], as_index=False)["covid_cases"]
        .max()
        .rename(columns={"地区": "city"})
    )
    covid["city"] = covid["city"].replace({"北京市": "北京", "天津市": "天津"})
    covid["covidnumber"] = covid["covid_cases"] / 1000.0
    covid[["city", "iwy", "covidnumber"]].to_csv(
        outdir / "covid_city_year_extract.csv", index=False, encoding="utf-8-sig"
    )


if __name__ == "__main__":
    main()

