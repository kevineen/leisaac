# Fork: training PC (kevineen)

このページは **kevineen/leisaac** 向けの運用です。公式ドキュメントの NVIDIA 手順はそのまま残してあり、こちらが学習 PC（Radeon AI PRO R9700 / ROCm）の上書きです。詳細コマンドはリポジトリ直下の [note.txt](https://github.com/kevineen/leisaac/blob/feat/mujoco-feasibility-notes/note.txt) を正本とします。

## 何が動いて、何が動かないか

| 作業 | この PC (R9700) | NVIDIA 機 / クラウド / 差し替え後 |
|------|-----------------|-----------------------------------|
| Isaac Sim / Isaac Lab | 不可 | 可 |
| HDF5 収集・`isaaclab2lerobot*` | 不可 | 可 |
| `lerobot-train` (ACT / SmolVLA / diffusion など) | 可（`lerobot-rocm`） | CUDA でも可 |
| ROS2 + MuJoCo（SO-101 並行ルート） | 可（`~/robot/so101_ros2_ws`） | — |
| 実機テレオペ / ROS2 推論 | ラズパイ4（Jazzy） | — |

MuJoCo などへのシミュレータ**置き換えはしません**（LeIsaac の USD・Isaac タスク・変換経路を守るため）。R9700 上の MuJoCo / ROS2 は **別パイプライン**とし、詳細は [note.txt の「ROS2 並行パイプライン」](https://github.com/kevineen/leisaac/blob/feat/mujoco-feasibility-notes/note.txt) と [so101_ros2_ws](https://github.com/kevineen/so101_ros2_ws) を参照。

## 環境

```text
Miniconda
  leisaac       Python 3.11 … Isaac 用。R9700 では CUDA / isaacsim を入れない
  lerobot-rocm  Python 3.12 … 学習。kevineen/lerobot (feat/rocm-train) を editable

micromamba
  ros-jazzy     ROS 2 Jazzy（RoboStack）。~/robot/so101_ros2_ws 用。lerobot-rocm と混ぜない
```

マシン固有パスは `.env.example` をコピーした `.env.local`（git 外）と `source scripts/env/load_env.sh`。

## 学習（この PC）

```bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate lerobot-rocm
source ~/robot/leisaac/scripts/env/load_env.sh
export TORCH_BLAS_PREFER_HIPBLASLT=0
# llama.cpp と同時に回さない

lerobot-train \
  --policy.type=act \
  --policy.device=cuda \
  --policy.push_to_hub=false \
  --dataset.repo_id=lerobot/pusht \
  --dataset.video_backend=pyav \
  --output_dir=/mnt/shared_hdd/robot/models/checkpoints/act-rocm \
  --steps=50 --eval_freq=0 --wandb.enable=false
```

ROCm でも PyTorch のデバイス名は `cuda` です。動画は **torchcodec を入れない**（PyAV）。groot は **flash-attn を入れない**（SDPA）。

確認済みスモーク: ACT / SmolVLA / diffusion。pi0 は `google/paligemma-3b-pt-224` が gated（HF ログインが先）。

関連: [kevineen/lerobot](https://github.com/kevineen/lerobot) の `docs/ROCM.md`。

## ROS2 + MuJoCo（並行・この PC）

```bash
source ~/robot/so101_ros2_ws/scripts/env.sh
./scripts/bringup_mujoco_sim.sh
# 別ターミナル: record → convert → train_act_lerobot_rocm.sh
```

Pi4 は Ubuntu 24.04 + Jazzy（`scripts/pi4_install_jazzy.sh`）。重い推論は PC の `policy_server` + Pi async。

## Isaac（別機 or 差し替え後）

1. **推奨:** NVIDIA 機またはクラウドで Sim 収集 → LeRobot Dataset を共有 HDD / rsync / Hub でこの PC へ。学習はこちら。
2. **この PC を NVIDIA に差し替えたあと:** `nvidia-smi` が通ってから `leisaac` env に CUDA / isaacsim / IsaacLab を入れる。手順は note.txt の「B: Isaac Sim」。

クラウドの一例: [NVIDIA Brev](/docs/cloud_simulation/nvidia_brev)。

## Git

- push 先は `origin`（kevineen/leisaac）のみ。
- 公式へ PR しない。`upstream` は大幅更新の取り込み専用。
