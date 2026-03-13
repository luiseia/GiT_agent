# 报告: @8000 后计划偏差说明
> 作者: claude_supervisor
> 时间: 2026-03-13 05:25
> 触发: CEO_CMD

---

## 问题 1: 为什么 @8000 后没有执行 score_thr 消融实验?

### MASTER_PLAN 原定计划

Phase 1 表格中明确列出:
```
| score_thr 消融 (0.1/0.2/0.3) | 零 | 中 | 待 @8000 eval | VERDICT_034_AT4000_BGFA |
```

Phase 2 标题也写明: "训练优化 (**ORCH_035 @8000 后**)"

### 实际发生了什么

1. **@8000 val 于 03/13 02:51 完成**, 结果: car_R=0.60(+158%), bg_FA=0.257, off_th=0.208
2. **Conductor 的 Critic VERDICT 为 PROCEED** — 继续训练到 @12000, 不中断
3. **score_thr 消融被推迟**到 @12000 附加测试 (MASTER_PLAN L123: "@12000 附加测试: score_thr 消融 0.1/0.2/0.3/0.5 eval")
4. 训练在 val 结束后自动恢复, 未做任何中间实验

### 为什么会这样

**Conductor 的决策逻辑**:
- car_recall 从 0.23→0.60 (+158%), 恢复轨迹强劲, 认为不应中断
- 认为更多训练 iter 能进一步改善指标
- 将 score_thr 消融推迟到 @12000, 与下一轮 eval 合并执行

**但这与 MASTER_PLAN 不一致**:
- Phase 1 明确标注 score_thr 消融 "待 @8000 eval"
- Phase 2 的 Deep Supervision、BUG-45 修复标注 "@8000 后"
- 这些都没有执行

### 能否现在补做?

**score_thr 消融: 可以, 不影响训练**
- score_thr 是推理时的后处理阈值, 不需要重新训练
- 只需对已有的 @8000 checkpoint 用不同 score_thr 跑 eval
- 可以在训练继续运行的同时, 在单独 GPU 上执行 (但当前 4 GPU 全部被 ORCH_035 占用)
- **现实约束**: 需要等训练释放 GPU, 或用 CPU eval (极慢)

**Phase 2 (Deep Supervision, BUG-45): 需要中断训练**
- Deep Supervision 需要修改 config 并重启训练
- BUG-45 需要改代码
- 这些与"继续 ORCH_035 到 @12000"直接冲突

### 根本原因

**计划更新不及时**: Conductor 做了 PROCEED 决策但没有更新 MASTER_PLAN 中 Phase 1/2 的时间节点。MASTER_PLAN 的 Phase 标注仍然写着 "@8000 后", 但实际决策已推迟到 @12000。这导致了计划文档与实际执行的不一致。

---

## 问题 2: DINOv3 ViT-L 参数量

### MASTER_PLAN 中的说法

Phase 3 表格 (L165):
```
| VGGT (论文) | ViT-L (300M) | 整个 backbone | finetune | 3D SOTA |
```

### 代码验证

`dinov3/dinov3/models/vision_transformer.py` L357-366:
```python
def vit_large(patch_size=16, **kwargs):
    model = DinoVisionTransformer(
        patch_size=patch_size,
        embed_dim=1024,
        depth=24,
        num_heads=16,
        ffn_ratio=4,
        **kwargs,
    )
    return model
```

### 参数量计算

| 组件 | 参数量 |
|------|--------|
| Patch Embed (3×16×16×1024 + bias) | ~787K |
| CLS Token | 1K |
| **每个 Transformer Block** | |
| - QKV Linear (1024→3072 + bias) | ~3.15M |
| - Proj Linear (1024→1024 + bias) | ~1.05M |
| - FFN Up (1024→4096 + bias) | ~4.20M |
| - FFN Down (4096→1024 + bias) | ~4.20M |
| - 2× LayerNorm | ~4K |
| - **Block 小计** | **~12.6M** |
| **24 个 Block 合计** | **~302.3M** |
| Final LayerNorm | ~2K |
| **总计** | **~303M** |

### 结论

**ViT-L 约 303M 参数, "300M" 是合理的近似值。**

如果 CEO 指的是另一个数字来源:
- DINOv2 官方 ViT-L/14 报告为 **304M** (patch_size=14, 比 patch_size=16 的 patch embed 大一些)
- VGGT 论文可能引用的也是 ~304M

**其他 DINOv3 变体参考** (同一代码文件):

| 变体 | embed_dim | depth | ffn_ratio | 估算参数量 |
|------|-----------|-------|-----------|-----------|
| vit_small | 384 | 12 | 4 | ~22M |
| vit_base | 768 | 12 | 4 | ~86M |
| **vit_large** | **1024** | **24** | **4** | **~303M** |
| vit_so400m | 1152 | 27 | 3.78 | ~400M |
| vit_huge2 | 1280 | 32 | 4 | ~632M |
| vit_giant2 | 1536 | 40 | 4 | ~1.1B |
| **vit_7b** | **4096** | **40** | **3** | **~6.8B** |

**注**: vit_7b 是当前使用的 backbone (frozen), embed_dim=4096, 40层, ~6.8B 参数。

---

## 建议

1. **score_thr 消融**: 建议在 @10000 checkpoint 时补做 (距离 ~1.5h), 不需要等到 @12000
2. **Phase 2**: 需 CEO 明确: 是否在 @12000 前中断训练执行 Phase 2? 还是让 ORCH_035 继续, Phase 2 与 Phase 3 合并?
3. **MASTER_PLAN 时间节点**: 建议 Conductor 更新 Phase 1/2 的时间标注以反映实际决策
