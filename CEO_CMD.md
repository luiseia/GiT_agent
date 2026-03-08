CEO 指令
请签发 AUDIT_REQUEST 到 shared/audit/requests/，要求 Critic 审计以下 CEO 方案，并要求你（Conductor）也提出自己认为更好的方案一并送审。
CEO 方案
1. DINOv3 适配层改进
当前 Linear(4096,768) 的 5.3:1 压缩是结构性瓶颈，sqrt 加权无法根治类别子空间干扰。
CEO 建议：
	∙	方案 A：增加适应层，如 Linear(4096,1024)+GELU+Linear(1024,768)，缓解压缩损失
	∙	方案 B：更激进——直接将 DINOv3 纳入训练（unfreeze 部分层），同时增加更多适应层
	∙	考虑到完整数据集训练较慢，且存在类别竞争问题，建议先在 nuScenes-mini 上只做 car 单类数据集验证，确认方案有效后再扩展
2. 3D 空间编码路线图调整
VERDICT_3D_ANCHOR 和 CEO 词汇表方案需要更多考虑：
	∙	目前只设计历史 occ box 占用信息的编码，基于历史预判当前帧
	∙	先不做全部类，只做车辆相关类（car/truck/bus/trailer/construction_vehicle）
	∙	行人、自行车等小目标太难，暂不纳入 3D anchor 编码
	∙	分阶段：先验证历史 occ box → 再加 ego 轨迹 → 最后 V2X
3. 要求 Conductor 补充
请你（Conductor）基于当前实验数据和 Critic 历史判决，思考：
	∙	以上方案有没有更好的替代？
	∙	DINOv3 unfreeze 的风险和收益？
	∙	是否需要验证竞争是影响recall和precision同时上升的原因，如果需要验证单类 car 在mini数据集上训练，是否足够验证？
	∙	历史 occ box 的时间窗口应该多长？我的建议是只用过去最近的一个时刻的，你可以批判
将你的补充方案一并写入 AUDIT_REQUEST，让 Critic 统一审计。
注意：签发 ORCH 必须包含「- 状态: PENDING」行。

compact_admin.md中提到了
Awaiting CEO decision on DINOv3 storage BLOCKER for P6 full nuScenes.
P6 full nuScenes prep — DINOv3 2.1TB BLOCKER
我认为这说明我们要想在完整数据集上训练必须放弃存权重的方案了，但是我可以先等待mini上验证单类car的最佳r和p。可以在1，3gpu上先尝试调试，方案 B：更激进——直接将 DINOv3 纳入训练（unfreeze 部分层），同时增加更多适应层 ∙ 考虑到完整数据集训练较慢，且存在类别竞争问题，建议先在 nuScenes-mini 上只做 car 单类数据集验证，确认方案有效后再扩展