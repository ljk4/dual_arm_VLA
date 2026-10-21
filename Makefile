SHELL := /bin/bash
ROOT := $(CURDIR)

TASK ?= handover_block
CONFIG ?= demo_clean
EPISODES ?= 50
SEED ?= 0
GPU ?= 0
EVAL_CONFIG ?= demo_clean
EVAL_EPISODES ?= 100

.PHONY: help check collect prepare train eval

help:  ## 显示可用目标
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

check:  ## 环境自检（GPU / torch / sapien / curobo / 资产）
	bash scripts/00_check_env.sh

collect:  ## 自采数据: make collect TASK=handover_block EPISODES=50
	bash scripts/03_collect_data.sh $(TASK) $(CONFIG) $(EPISODES) $(GPU)

prepare:  ## 映射 XPolicyLab 目录并预处理 ACT 数据
	bash scripts/04_prepare_act.sh $(TASK) $(CONFIG)

train:  ## ACT 训练: make train TASK=handover_block SEED=0
	bash scripts/05_train_act.sh $(TASK) $(SEED) $(GPU)

eval:  ## ACT 评估: make eval TASK=handover_block EVAL_CONFIG=demo_clean
	bash scripts/06_eval_act.sh $(TASK) $(EVAL_CONFIG) $(SEED) \
		RoboTwin-$(TASK)-arx_x5-joint-$(SEED) $(EVAL_EPISODES)
