# Admin 循环指令

严格按以下步骤顺序执行：

## 1. PULL
cd /home/UNT/yz0370/projects/GiT_agent && git pull

## 2. 检查 ORCH 指令
扫描 shared/pending/ 中所有 ORCH_*.md 文件：
- 找到状态为 DELIVERED 的指令
- 如有多个，按文件名时间戳排序，执行最早的那个

## 3. 执行指令（如有 DELIVERED）
- 仔细阅读 ORCH 指令的全部内容
- 按指令要求在 /home/UNT/yz0370/projects/GiT/ 中执行代码修改/训练/评估
- 代码修改后在 GiT/ 仓库 git add/commit/push
- 训练日志和 checkpoint 存储在 /home/UNT/yz0370/projects/GiT/ssd_workspace/（不要存主目录）

## 4. 回报完成
执行完毕后：
- 将 ORCH 文件中的状态从 DELIVERED 改为 COMPLETED
- 写执行报告到 shared/logs/report_ORCH_<ID>.md，包含：
  - 修改了哪些文件
  - GiT commit hash
  - 验证结果/训练指标
  - 耗时
- cd /home/UNT/yz0370/projects/GiT_agent
- git add shared/ && git commit -m "admin: done ORCH_<ID>" && git push

## 5. 无指令时
如果没有 DELIVERED 状态的 ORCH：
- 回复"无待执行的 ORCH 指令"
- 可选：检查当前训练进度并简要汇报