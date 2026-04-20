# 上市公司资本结构影响因素分析

> [作业要求](https://github.com/lianxhcn/dsfin/blob/main/homework/ex_P03_Panel-capital_strucuture.md)

## 个人信息

- 姓名：谢婧怡
- 学号：25210094

### 数据来源
- CSMAR，下载时间：2026-04-20
- 最终样本：4686 个公司，43026 个观测值，2011-2025 年

### 样本筛选流程
（见 [output/sample_counts.csv](output/sample_counts.csv)）

### 工具
- Stata 18.X（主要建模）/ Python 3.X（辅助检查）
- Jupyter Notebook

### GitHub 仓库
https://github.com/xiejingyi25210094/dshw--panel/tree/final

### Quarto Book（如完成）
- [Quarto Book 源文件](index.qmd)
- 章节文件位于 [chapters/](chapters/)
- 渲染命令：`quarto render`
- GitHub Pages 发布：推送到 `final` 分支后由 GitHub Actions 自动生成站点，发布到 `gh-pages`

### 主要发现（3-5 条）
1. M1-M3 的结果整体更接近权衡理论：`npr` 对杠杆的影响为正，但产权性质交互项不显著，说明差异方向存在、证据不强。
2. M4 的时间变系数在 2015 年前后波动最明显，说明利润率与杠杆关系会受到宏观政策环境影响。
3. M5-M6 显示规模异质性显著：小企业的边际效应更高，阈值大致落在 `ln(Size)` 约 21.4-21.6，对应总资产约 20-25 亿元。
4. IFE 结果已经成功估计并收敛；加入 M2 增长率后，`npr` 系数明显缩小并接近 0，说明 TWFE 中的正向关系不够稳健。
5. 样本清洗后保留 43026 个观测值，回归结果与图形已导出到 [output/](output/) 目录，可直接用于课程提交。
