
## CEO 的扩展思路（V2X 协作 + 时序融合）

### 长期目标
不仅用 3D Anchor 编码当前帧的空间信息，还要融合：
1. **Ego 时序信息**: ego 车自身过去的位置和行驶轨迹
2. **V2X 协作信息**: sender 车发送的它观测到的 occ box 结果

### 两种融合架构选择

**方案 A: 全文本 Token 方案**
- ego 历史轨迹 → 文本 token（如 "ego_t-1: x=10.5, y=3.2, heading=45°"）
- sender 的 occ box → 文本 token（如 "sender_1: car at grid(5,8), NEAR"）
- 每个 Anchor 的 3D 坐标 → 文本 token
- 全部送入文本编码器 → 融合 → 注入 ViT K/V

**方案 B: BEV Grid 方案**
- 不用射线 Anchor（射线长度不一致），改用 BEV grid 中心作为 Anchor
- 每个 BEV cell 中心 = 一个 Anchor 点
- ego 历史和 sender 信息投影到 BEV grid 上融合
- 问题：BEV grid 是 2D 的，丢失了深度方向的精度

### 额外审计要求

### 5. 两种方案对比
- 方案 A（射线 Anchor + 全文本）vs 方案 B（BEV grid 中心 Anchor）各自优劣
- 射线长度不一致的问题有没有解决办法（如截断到固定范围、非均匀采样）
- 是否可以混合：BEV 平面用 grid 中心，深度方向用射线采样

### 6. V2X 信息融合的可行性
- sender 的 occ box 结果如何表示为 token？直接文本还是 embedding？
- 时序信息（ego 轨迹）的编码方式：逐帧 token 还是轨迹级特征？
- 与当前 GiT 的 text decoding 架构是否兼容？
- 相关文献：V2X-ViT、Where2comm、CoBEVT 等 V2X 协作感知方法的编码方式

### 7. 分阶段实现建议
- 第一步应该先验证什么？（最小可行实验）
- 如何在不改变当前训练流程的前提下验证 3D Anchor 的价值？
