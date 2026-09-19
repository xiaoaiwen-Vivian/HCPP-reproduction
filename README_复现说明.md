# HCPP：与 final draft0918 对齐的复现代码

维护署名：Xiaoai。版本：2026-09-19。

## 本机怎么运行

在 Stata 18 中将工作目录设为本代码包，然后完整运行：

```stata
do RUN_ALL.do
```

本机目录已配有私有 `config.local.do`。公开上传包不含这个私有文件；其他人需要复制 `config.example.do` 为 `config.local.do` 并填写自己的路径。

每次运行都从原始上游资料新建 `charls.dta` 和 `dataset 0507.dta`，后续模型使用本次新生成的0507。不会读取之前的0507、旧分析样本或旧结果来代替计算。只重建数据可运行 `do RUN_ALL.do build`。

需准备五波CHARLS原始模块、Harmonized C/D、PSU以及城市年鉴、市政、COVID和PM2.5输入。共有56个外部输入，清单及哈希见 `verification/INPUT_MANIFEST.json`。Harmonized文件本身也是上游输入，不能将此流程表述为所有Harmonized变量均已逐题从raw重建。

## 与论文的对应

- 清洗逻辑沿用已确认版本，包括已修正的2020收入公式。
- Green/Road使用保存的2011–2020市政工作簿，包含四直辖市。
- Table5保留原PanelA可用样本和城市聚类；PanelB额外要求结果变量非缺失。
- A1a是传统Sobel及联合协方差诊断；A1b继续使用共同样本的2,000次城市bootstrap。
- A3保留五个正式交互，不增加中等收入交互；Table4仍保留中等收入描述分组。
- A4收入是低收入对中高收入合并，城市聚类。
- 其余已确认的PSM、事件研究、wild bootstrap、城市安慰剂、COVID中心化、非线性诊断、个体FE和收入缺失比较均保留。
- 新增统一导出，不再依赖散落在桌面或旧工作目录里的补充脚本。导出19张论文编号CSV表和六幅图。
- 不新增尚未确认的收入缺失回归、多重插补或其他模型。

## 去哪里找结果

运行结束时会打印本次新建目录，形如 `runs/run_日期_时间/`：

| 内容 | 本次运行目录下的位置 |
|---|---|
| 新建CHARLS面板、0507 | `data/` |
| 16,661条主分析样本 | `output/primary_estimation_sample.dta` |
| 19张按论文编号命名的完整精度表 | `output/manuscript_tables/` |
| 每张表对应哪个结果文件 | `output/manuscript_tables/TABLE_INDEX.csv` |
| Figure1、Figure2、Figure3及A1/A2/A3 | `output/figures/` |
| 所有模型原始输出、抽样明细 | `output/` |
| 分析日志 | `logs/` |
| 校验结果 | `verification.json`及`verification_passed.ok` |

Figure1为可编辑SVG；其他五幅图提供PNG、PDF及Stata图形文件。表格CSV可用Excel打开；这是数值复现文件，不会自动改动论文Word。

完整成功的标准是最后出现 `REPRODUCTION_PACKAGE_RUN_VERIFIED`，且 `verification.json`中`passed`为`true`。仅看到Stata进程结束，不能当作全部成功。

## Table1两格应随数据纠正

当前稿COVID Obs=86,696、SD=0.228是旧值。最终数据对应 **86,654、0.230**，代码输出采用正确值。42条COVID缺失属于环境来源记录；主模型16,661条不受影响。本代码不会为迁就旧表格而把缺失值填零。

## 上传GitHub

建议使用单独交付的 `HCPP_GitHub_READY_20260919.zip`：解压后，将其中的文件和真实子文件夹上传到仓库根目录。

应包含 `RUN_ALL.do`、`pipeline_v4.do`、配置示例、说明文件、`support/`、`vendor/`、`verification/`、依赖清单和校验清单。旧仓库中的同名文件应由新版替换；旧的原始输入清单和试跑核验结果也由本版同名文件替换。旧 `support.zip`、`vendor.zip`、`verification.zip`应删除，改为展开后的文件夹。不要把整个新文件夹嵌套在旧仓库的同级内容之下，造成入口仍指向旧文件。

不要上传本机工作目录里的 `runs/`、`config.local.do`、原始数据、0507、个体分析样本或日志。本次单独制作的上传ZIP已排除这些内容。`.gitignore`不会自动删除以前已经提交的数据；上传前仍应核对仓库文件列表。

代码同步后，再为对应发行版本建立DOI存档。本次不代替你修改GitHub，也不声称已创建DOI。
