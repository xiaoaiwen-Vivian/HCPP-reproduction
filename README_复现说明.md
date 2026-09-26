# HCPP 论文复现代码

维护署名：Xiaoai。日期：2026-09-26。对应稿件：`final draft0923_开会.docx`。

## 运行方法

1. 准备 `verification/INPUT_MANIFEST.json` 列出的56份外部输入，包括五波CHARLS模块、Harmonized C/D、PSU以及城市、市政、COVID和PM2.5资料。数据不随公开代码包提供。
2. 使用 Stata 18；Python依赖版本见 `requirements.txt`。
3. 将 `config.example.do` 复制为 `config.local.do`，填入数据路径和Python程序路径。
4. 在Stata中将工作目录设为本代码包，运行：

```stata
do RUN_ALL.do
```

程序按顺序生成 `charls.dta`、`dataset 0507.dta`，再运行模型、导出表图并核验。Harmonized数据属于上游输入。每次执行都在独立的 `runs/run_日期_时间/` 目录保存结果。只生成数据时运行 `do RUN_ALL.do build`。

成功标准：出现 `REPRODUCTION_PACKAGE_RUN_VERIFIED`，并且运行目录的 `verification.json` 中 `passed` 为 `true`，同时存在 `verification_passed.ok`。输入文件不匹配、模型失败或核验失败会停止流程。

## 模型与表格

- 数据清洗保持既定口径；2020年收入各项只计入一次。主分析16,661条、7,995人、94城。
- 政策层面主要推断按城市聚类。保留Webb和Rademacher各9,999次wild bootstrap、政策前个人均值PSM、事件研究、正式异质性交互检验、5,000次城市安慰剂及COVID中心化分析。
- Table5 Panel A使用路径变量和控制变量可用的观测；Panel B还要求结果变量可用。
- A1a为传统Sobel及联合协方差诊断；A1b为六条路径各2,000次城市bootstrap及FDR。
- Ordered logit和binary logit均先排除鞍山市23条最低结果类别的完全预测观测，使用16,638条、93城；主线性模型样本不变。
- DID专项平行线检验在部分比例优势模型中只释放DID的阈值系数，其他斜率保持一致。它不检验所有变量的平行线约束。每次运行由当次ordered logit产生初值。
- 全部斜率可变的广义有序Logit不列入正式模型结果，也不纳入总入口的常规运行。
- A5a展示年龄和居住地合格的34,228条中收入不可用的14,469条。A5b仅导出均值及每项变量有效N，保留组为16,661条；收入不可用组的结果变量有效N为12,507。两组独立计数。
- 正式表格导出不含A5b差值、SE或p值；底层工作簿中的诊断计算仍供核查。

## 输出位置

| 内容 | 运行目录内的位置 |
|---|---|
| CHARLS面板、0507 | `data/` |
| 主分析样本 | `output/primary_estimation_sample.dta` |
| 非线性模型样本 | `output/nonlinear_estimation_sample.dta` |
| 19张论文编号CSV表 | `output/manuscript_tables/` |
| 每张表的来源与解释 | `output/manuscript_tables/TABLE_INDEX.csv` |
| Figure1/2/3和Appendix Figure A1/A2/A3 | `output/figures/` |
| DID专项平行线检验 | `output/did_parallel_lines.csv` |
| 全精度结果和抽样明细 | `output/` |
| 模型日志 | `logs/` |
| 核验报告 | `verification.json` |

Figure1为SVG；其余图提供PNG/PDF/GPH。CSV保留计算精度，Word中展示时按论文格式舍入。代码不会修改论文文件。

## 需与论文核对的数字

1. Table1的COVID有效N为86,654，SD四舍五入为0.230；稿件显示86,696和0.228。42条收入无关的COVID缺失记录属于环境来源记录，主分析样本不受影响。
2. Binary logit实际估计110个斜率加1个截距，共111个参数。稿件112的计数包含一个被省略的全零城市指标列；去掉这列不会改变拟合模型或DID系数。Ordered logit为113个参数。
3. DID专项Wald统计量受数值优化与导数计算精度影响，在独立实现之间末位有微小差异，p值按四位小数均为0.1749。程序保存当次计算值，核验使用明确的数值容差。

## 上传GitHub

使用 `HCPP_GitHub_READY_20260926.zip`。解压后将文件及展开的 `support/`、`vendor/`、`verification/` 放到仓库根目录，替换对应内容。

公开包不含 `config.local.do`、`runs/`、原始数据、0507、个体分析样本或运行日志。请勿把本机核验目录上传。第三方Stata程序的作者和许可信息保留在 `vendor/`。校验参考数值仅用于估计完成后的核对，不参与样本筛选或模型拟合。
