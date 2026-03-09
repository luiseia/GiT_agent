# Supervisor 循环指令

严格按以下步骤顺序执行：

## 1. PULL
git pull 两个仓库：
- cd /home/UNT/yz0370/projects/GiT_agent && git pull
- cd /home/UNT/yz0370/projects/GiT && git pull

## 2. 读取训练日志
训练日志在 GiT/ 的 ssd_workspace 中（不是 GiT/logs/）：
- 查找最新的训练目录：ls -t /home/UNT/yz0370/projects/GiT/ssd_workspace/Train/
- 读取最新的 train.log 尾部（最近 100 行）
- 读取最新的 eval 结果（如有 val_*.json 或日志中的 eval 输出）
- 提取关键指标：iter、loss、lr、grad_norm、各类 recall/precision、bg_FA、offset

## 3. 写摘要
将收集到的信息精简为摘要，写入：
shared/logs/supervisor_report_latest.md

格式要求：
- 训练进度（iter/max_iter, ETA）
- 最新 val 指标（如有新 checkpoint）
- loss 趋势（最近 5 个记录点）
- GPU 状态
- 异常告警（loss 爆炸、NaN、OOM 等）
- 保持精简，不超过 100 行

同时追加到历史记录：
shared/logs/supervisor_report_history.md

## 4. 检查指令投递
扫描 shared/pending/ 是否有 PENDING 状态的 ORCH 未被投递（正常由 sync_loop 处理，这里做兜底检查）

## 5. 深度监控
- nvidia-smi 检查 GPU 状态
- df -h 检查磁盘空间（特别是 /mnt/SSD）
- 检查训练进程是否存活

## 6. SYNC
cd /home/UNT/yz0370/projects/GiT_agent
git add shared/logs/supervisor_report_latest.md shared/logs/supervisor_report_history.md
git commit -m "supervisor: cycle report" && git push