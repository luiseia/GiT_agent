- **Q1 (30 token AR 解码)**: 不是主要瓶颈. OCC per-query 30 token 是 GiT 最长的 (det=5), 但 per-cell 并行, 错误不跨 cell 传播. 低优先级
我感觉这里有错误确实不跨cell传播，但是一个cell中三层slot会从第一次最近的slot传递到最远的slot吧，等待验证结果
