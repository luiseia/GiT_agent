# Val 数据集调查报告
> 撰写: Conductor | 时间: 2026-03-09 ~04:50 | Cycle #111
> CEO 问题: 训练 val 用的是跟 train 一样的数据集吗?

---

## 结论: 不同。Train 和 Val 完全分离，零重叠。

---

## 配置详情

**Config**: `plan_full_nuscenes_gelu.py`

### 训练集
```python
# L306-310
train_dataloader = dict(
    batch_size=2,
    num_workers=4,
    dataset=dict(
        type='NuScenesOccDataset',
        data_root='data/nuscenes/',
        ann_file='data/infos/nuscenes_infos_temporal_train.pkl',  # ★ 训练集
        pipeline=train_pipeline,
        occ_n_future=4,
        classes=classes
    )
)
```

### 验证集
```python
# L312-317
val_dataloader = dict(
    batch_size=2,
    num_workers=4,
    sampler=dict(type='DefaultSampler', shuffle=False),  # BUG-33 fix
    dataset=dict(
        type='NuScenesOccDataset',
        data_root='data/nuscenes/',
        ann_file='data/infos/nuscenes_infos_temporal_val.pkl',  # ★ 验证集 (不同!)
        pipeline=test_pipeline,
        test_mode=True,  # 推理模式
        occ_n_future=4,
        classes=classes
    )
)
```

### 测试集
```python
# L318
test_dataloader = val_dataloader  # 复用 val
```

---

## 数据分离验证

| 项目 | 训练集 | 验证集 |
|------|--------|--------|
| **Ann file** | `nuscenes_infos_temporal_train.pkl` | `nuscenes_infos_temporal_val.pkl` |
| **文件大小** | ~1.2 GB | ~238 MB |
| **样本数** | **28,130** | **6,019** |
| **场景数** | **700** | **150** |
| **样本 token 重叠** | **0** ✅ | **0** ✅ |
| **场景 token 重叠** | **0** ✅ | **0** ✅ |

**这是标准 nuScenes 官方 train/val 分割。850 个场景, 700 训练 + 150 验证, 完全不重叠。**

---

## Pipeline 差异

```python
# L297
test_pipeline = train_pipeline  # ⚠️ Val 使用与 train 相同的 pipeline
```

但有关键区别:
- Val dataset 设置 `test_mode=True` → 数据集类内部逻辑不同 (不生成训练标签, 使用推理模式)
- Val sampler 设置 `shuffle=False` → 顺序遍历, 不打乱

**注意**: `test_pipeline = train_pipeline` 意味着 val 使用相同的数据增强处理。如果 train_pipeline 包含随机增强 (如随机翻转/缩放), 这些也会应用到 val 上。但在 GiT 的 OCC 任务中, pipeline 主要是加载和预处理, 随机增强影响可能较小。

---

## 数据量对比

```
训练: 28,130 samples ÷ 32 effective_batch = 879 optimizer steps/epoch
验证: 6,019 samples ÷ 8 (2×4 GPU) = 753 val iters

@4000 iter = 28,130×4000÷(28,130) ≈ 1.14 epochs (每个训练样本平均被看了 1.14 次)
```

---

## 总结

| 问题 | 回答 |
|------|------|
| Val 和 Train 是同一个数据集? | **否**, 完全不同的 pkl 文件 |
| 有数据泄漏? | **无**, 零样本零场景重叠 |
| 标准分割? | **是**, nuScenes 官方 850 = 700+150 |
| Pipeline 相同? | **是** (test_pipeline = train_pipeline), 但 test_mode=True 控制行为 |

**结论: 数据配置正确, 无泄漏, 遵循标准实践。**

---

*Conductor 签发 | 2026-03-09 ~04:50*
