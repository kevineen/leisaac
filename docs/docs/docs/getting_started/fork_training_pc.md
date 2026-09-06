# Fork: training PC (kevineen)

このページは **kevineen/leisaac** 向けの運用です。公式ドキュメントの NVIDIA 手順はそのまま残してあり、こちらが学習 PC（Radeon AI PRO R9700 / ROCm）の上書きです。詳細コマンドはリポジトリ直下の [note.txt](https://github.com/kevineen/leisaac/blob/feat/training-pc/note.txt) を正本とします。

## 何が動いて、何が動かないか

| 作業 | この PC (R9700) | NVIDIA 機 / クラウド / 差し替え後 |
|------|-----------------|-----------------------------------|
| Isaac Sim / Isaac Lab | 不可 | 可 |
| HDF5 収集・`isaaclab2lerobot*` | 不可 | 可 |
| `lerobot-train` (ACT / SmolVLA / diffusion など) | 可（`lerobot-rocm`） | CUDA でも可 |
| 実機テレオペ | ラズパイ4 | — |

MuJoCo などへのシミュレータ置き換えはしません。LeIsaac の価値（USD・Isaac タスク・変換経路）を落とすためです。

## 環境

```text
Miniconda
  leisaac       Python 3.11 … Isaac 用。R9700 では CUDA / isaacsim を入れない
  lerobot-rocm  Python 3.12 … 学習。kevineen/lerobot (feat/rocm-train) を editable
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

## Isaac（別機 or 差し替え後）

1. **推奨:** NVIDIA 機またはクラウドで Sim 収集 → LeRobot Dataset を共有 HDD / rsync / Hub でこの PC へ。学習はこちら。
2. **この PC を NVIDIA に差し替えたあと:** `nvidia-smi` が通ってから `leisaac` env に CUDA / isaacsim / IsaacLab を入れる。手順は note.txt の「B: Isaac Sim」。

クラウドの一例: [NVIDIA Brev](/docs/cloud_simulation/nvidia_brev)。

## Git

- push 先は `origin`（kevineen/leisaac）のみ。
- 公式へ PR しない。`upstream` は大幅更新の取り込み専用。
