# CEO 指令

Critic 在 VERDICT_CEO_ARCH_QUESTIONS 中声称"原始 GiT 在 COCO 检测上序列更长，全图数百个目标"，CEO 认为这不准确。

请验证以下问题并签发 AUDIT_REQUEST 给 Critic 复核：

1. 原始 GiT 在 COCO 检测任务中，每个 grid token 解码多长的序列？CEO 认为每个 grid token 只解码一个 box，属性长度仅为 5（class + 4 个坐标），而不是像我们 BEV occ 这样每个 cell 解码 30 token（3 slot × 10 token）
2. 如果 CEO 的理解正确，那么我们的 BEV occ 任务实际上比原始 GiT 的解码负担重 6 倍（30 vs 5），Critic 之前否定"长序列是瓶颈"的结论需要重新审视
3. 请 Conductor 先自己读 GiT 原始论文或代码确认，然后让 Critic 复核

注意：签发 ORCH 必须包含「- **状态**: PENDING」行。
