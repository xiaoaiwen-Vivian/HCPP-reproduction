# HCPP：从原始资料到新 0507 的完整复现代码包

维护署名：Xiaoai。版本：2026-09-18，基于 2026-09-17 已核查的 v4 清洗及最终模型。

## 1. 这个包做什么

统一入口从五波 CHARLS 原始模块、Harmonized C/D、PSU 和城市来源资料开始，依次生成全新的 `charls.dta`、全新的 `dataset 0507.dta`，再运行最终保留的模型。

**运行输入不包括旧 charls、旧 0507、旧样本名单或旧个人数据。** 每次运行使用一个新建的时间戳目录；不会读取上次运行的数据来替代原始数据重建。输入文件核验不通过时停止，不会改用旧数据。

这是 Stata 18 主控、调用 Python 辅助的流程；不是纯 Stata 程序。五波原始模块与 Harmonized 整理数据都属于上游输入，不能表述为所有 Harmonized 变量都已重新逐题构造。

本 ZIP 是代码包，包含所有正式运行所需的研究 do/Python 文件、Stata 扩展命令快照和核验资料。它不附原始或个人层面数据，也不附旧 0507。原始输入继续从本机现有目录读取。不要把 ZIP 当作包含原始数据的独立数据包。

## 2. 本机最简单的运行方法

在 Stata 18 命令窗口执行：

```stata
cd "/Users/apple/Documents/honor thesis/HCPP_从原始数据复现_代码包_20260918"
do RUN_ALL.do
```

如果解压到了其他地方，第一行改成实际解压目录。不要直接运行 `pipeline_v4.do`，不要先打开旧 0507。

只重建数据、不运行模型：

```stata
do RUN_ALL.do build
```

两个入口都会重新从上游原始资料生成数据。统一入口不提供沿用旧数据的 `models` 模式。

## 3. 换电脑时修改哪里

只需编辑 `config.do`，填写：

- 五波原始模块路径：`raw2011`、`raw2013`、`raw2015`、`raw2018`、`raw2020`；
- Harmonized D 与 C 的目录：`harmonized`、`harmonizedC`；
- `rawroot` 下的上游资料布局；
- 城市数据库、市政数据、COVID、PM2.5 来源文件；
- Python 可执行文件路径。

路径保留双引号。当前版本按 macOS 本机路径配置并测试；未宣称已经在 Windows/Linux 或区分大小写的文件系统完成测试。原 do 文件部分原始文件名大小写不同，在其他系统上需对应实际文件名核对。

Stata 需另行安装并持有有效授权；本包不包含 Stata 软件或许可证。Python 验证环境为 3.12.14；依赖固定在 `requirements.txt`。给选定的 Python 环境安装依赖时可执行：

```text
python3 -m pip install -r requirements.txt
```

然后将 `config.do` 中的 `global python` 指向安装了这些依赖的解释器。本机当前已具备所需环境，无需重复安装。

扩展命令 sreshape、ftools、reghdfe、psmatch2、pstest、esttab、estpost 和 boottest 已随包保留实际使用的文件；运行时优先读取包内版本。第三方原作者与帮助文件归属保留，不改署名。

## 4. 包内代码的分工

| 文件 | 作用 |
|---|---|
| `RUN_ALL.do` | 唯一推荐入口；创建新目录、检查来源和依赖、运行主流程、验证新结果 |
| `config.do` | 输入路径和 Python 路径配置 |
| `pipeline_v4.do` | 集成五波清洗、合并、收入修正、新 0507 生成及全部保留的最终分析 |
| `support/prepare_source_workbooks.py` | 从原 Excel 读取并提取城市、市政、COVID 字段 |
| `support/city_placebo_fast.py` | 5,000 次城市安慰剂加速计算及与 Stata 抽查比较 |
| `support/mediation_cluster_bootstrap.py` | 六条路径各 2,000 次城市重抽样及 FDR |
| `support/preflight.py` | 检查原始来源文件哈希和 Python 依赖版本 |
| `support/verify_run.py` | 检查本轮新数据及结果，不读取任何旧个人数据 |
| `vendor/` | 固定的第三方 Stata 扩展命令及帮助文件 |
| `verification/INPUT_MANIFEST.json` | 56 个外部输入文件的路径模板、大小和 SHA-256 |
| `verification/EXPECTED_RESULTS.json` | 已核查的汇总数值，仅用于运行结束后比较 |
| `verification/CODE_ORIGIN.json` | v4 来源、代码哈希及本次路径改造说明 |
| `verification/STATA_DEPENDENCIES.json` | 第三方依赖快照的来源记录和哈希 |
| `verification/PACKAGE_TEST.json` | 打包版本完整试跑结论 |
| `MANIFEST_SHA256.json` | ZIP 所含文件的 SHA-256，便于发现文件变化 |

主流程已整合在一个 do 文件中，不需要按顺序打开多份旧 do 文件。未纳入旧模型草稿和用于组装、修改论文的开发脚本；这些不是从原始数据复现本研究分析的运行依赖。

## 5. 每次运行生成什么

所有新文件写入 `runs/run_日期_时间/`：

```text
runs/run_日期_时间/
├── input_paths.tsv              本轮实际输入路径
├── preflight.json               来源文件及 Python 环境检查
├── preflight_passed.ok          输入检查通过标记
├── data/
│   ├── charls.dta               重新合并的五波个人面板
│   └── dataset 0507.dta         本轮重新生成的 0507
├── temp/                       分波与城市来源中间文件
├── output/                     主模型、诊断、图形、抽样明细
├── logs/
│   ├── dependencies.log        实际调用的扩展命令位置
│   └── pipeline_.log           默认完整运行日志
├── verification.json           本轮数据和最终结果核验
└── verification_passed.ok      结果核验通过标记
```

仅重建模式的日志名为 `pipeline_build.log`。完整模式成功后，Stata 显示 `REPRODUCTION_PACKAGE_RUN_VERIFIED`。Stata 批处理退出状态不能单独证明成功，要查看这个标记及 `verification.json`。

完整模式的重要结果：

- `primary_estimation_sample.dta`：真正进入主模型的样本；
- `main_DID_city_cluster.xlsx`：主 DID；
- `main_did_wild_cluster_results.xlsx`：Webb/Rademacher 9,999 次 wild bootstrap；
- `event_study_city_cluster.xlsx/.png`：事件研究；
- `prepolicy_means_psmdid_summary.xlsx`：政策前个人均值 PSM-DID；
- `prepolicy_psm_diagnostics.dta`：匹配个人、得分、支持域及权重；
- `prepolicy_psm_balance.xlsx/.png`、`prepolicy_psm_overlap.png`：匹配平衡和重叠；
- `heterogeneity_subgroups_city_cluster.xlsx`、`heterogeneity_interactions_city_cluster.xlsx`：分组与正式交互；
- `mechanism_panelAB_city_cluster.xlsx`：共同样本路径回归；
- `city_bootstrap_indirect_FDR.csv/.xlsx/.dta`：城市中介重抽样；
- `city_bootstrap_draws_*.csv`、`city_bootstrap_city_counts_*.npz`：逐次结果和城市抽样计数；
- `city_level_placebo_5000.csv/.xlsx/.dta/.png`：城市安慰剂；
- `city_placebo_assignments.csv/.dta`：所有安慰剂分配；
- `placebo_policy_timing_results.xlsx`：政策前虚假起点；
- `covid_centered_model_summary.xlsx`、`covid_centered_marginal_effects.xlsx`：中心化 COVID；
- `nonlinear_cityFE_citycluster.xlsx`、`nonlinear_separation_cells.csv`：非线性及完全预测诊断；
- `individual_FE_citycluster.xlsx`：个体固定效应；
- `income_missingness_by_wave_treatment.xlsx`、`retained_vs_income_missing.xlsx`：收入缺失分析。

## 6. 样本与口径

新 `charls.dta`：96,628 行。新 0507：86,696 行，其中 1,310 行没有个人—波次标识，是原作者 PM2.5 合并口径保留的环境来源独有记录。

模型明确排除这 1,310 行；有效个人记录 85,386 人次。依次排除已知年龄低于45岁、农村居住、年龄缺失、收入及其他控制缺失、结局缺失，主模型得到 **16,661 人次、7,995 人、94 城市（10处理、84对照）**。

16,661 是实际重建结果，不是筛选目标。`verify_run.py` 中出现该数值仅是模型运行结束后的核验，不会修改数据或决定样本。

保留作者已确认清洗逻辑；明确落实2020年收入六项各计一次、Harmonized C对应2015年、分年PSU编码副本、第五波合并年份、完整年龄条件和13项主回归控制。匹配仅用政策前12项变量个人均值；后续加权DID包含年龄等13项控制。

医疗资源 `hosper` 的单位是**每万人医院／卫生院数**，不是每人；它也不是家庭医疗支出。绿地/道路各15,921条、90城，因来源未覆盖四个直辖市而缺740条主样本记录，不用旧0507回填。

## 7. 结果核验和解释边界

输入文件的哈希若变化，入口会停止，并在 `preflight.json` 中列出差异。需先核对是不是源数据版本变动，不应删除检查以强行获得目标N。

结果核验使用随包的汇总参考值，不读取旧0507或旧个人名单。主DID约−0.08667948，城市SE约0.03304536；政策前PSM N=12,037，系数约−0.08591807。城市安慰剂5,000次均有效，各中介2,000次均有效。

Stata随机种子为2025；中介程序对每条路径使用NumPy PCG64并分别重置2025。两种软件的同名种子不意味着抽样序列相同，因此保存实际分配/抽样计数及版本。

城市安慰剂的加速计算与27次独立Stata回归对照；中介原样本路径系数与Stata一致，并检查总关联=直接关联+路径乘积。仅运行结束不代表识别假设或机制成立：六项间接关联均未通过FDR；正式异质性交互均未在5%显著；两个Logit保留诊断限制；未收敛广义有序Logit不作为稳健性证据。

图形是统计运行输出。论文后期排版重绘和Word修订操作不属于这个数据复现代码包。

## 8. 保存和交接

保留整个代码包目录，不能只拷贝主do文件。其他电脑还需要合法取得同版本上游原始资料，并修改 `config.do`。本包尚未上传外部仓库，没有生成DOI。

首次复现或日后重跑，都用 `RUN_ALL.do`。每次结果写入新目录，历史结果保持可对照。
