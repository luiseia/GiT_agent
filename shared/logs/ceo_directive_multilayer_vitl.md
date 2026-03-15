# CEO 指令: 多层 LN/BN ViT-L 计划

- **时间**: 2026-03-14 23:30
- **条件**: @6000 eval 确认 frozen predictions 不存在
- **内容**: 实施冻结的多层 + LN/BN 的 ViT-L

## 具体改动

1. **多层提取**: `online_dinov3_layer_idx=23` → `online_dinov3_layer_indices=[5, 11, 17, 23]`
   - ViT-L 24 层，取 4 层均匀分布（类比 ORCH_035 的 [9,19,29,39]）
2. **LayerNorm**: 每层特征过 LN 再拼接，对齐不同层的 scale
3. **投影**: 拼接后 1024×4=4096 → 投影回 1024（GiT-Large embed_dim）
4. **ViT-L 仍冻结**: unfreeze_last_n=0 不变
5. **需停训练改 config + 代码，从当前 checkpoint resume**
