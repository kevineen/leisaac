# Trouble Shooting

## Isaac Sim does not start on Radeon / ROCm

Isaac Sim and Isaac Lab need NVIDIA + CUDA. AMD Radeon AI PRO R9700 (ROCm) cannot run them. This is expected.

- Train on this PC with conda env `lerobot-rocm` and [kevineen/lerobot](https://github.com/kevineen/lerobot) (`feat/rocm-train`).
- Collect sim data on another NVIDIA machine, NVIDIA cloud, or after swapping this PC to NVIDIA.
- Do not replace Isaac with MuJoCo inside LeIsaac. For a parallel MuJoCo route on this PC, see [note.txt — MuJoCo 調査結果](https://github.com/kevineen/leisaac/blob/feat/mujoco-feasibility-notes/note.txt).

See [Fork: training PC](/docs/getting_started/fork_training_pc) and [note.txt](https://github.com/kevineen/leisaac/blob/feat/training-pc/note.txt).

## `pip install -e "source/leisaac[lerobot]"` pulled PyPI 0.4.2

That extra is for upstream. This fork uses editable `~/robot/lerobot` in `lerobot-rocm` instead.

## Training CUDA OOM / `torchcodec` crash / missing VideoReader

- Stop llama.cpp / LM Studio if they occupy VRAM (`pgrep -af llama-server`).
- Do not install `torchcodec` on ROCm (CUDA ABI). Use `--dataset.video_backend=pyav`.
- ROCm torchvision has no `VideoReader`. Native PyAV in the lerobot fork covers that.

## Vscode debugger does not work

> related issue: [IsaacLab/issues/3305](https://github.com/isaac-sim/IsaacLab/issues/3305)

When you launch the program using VSCode Python Debugger, you may encounter the following error:

```shell
OSError: libstdc++.so.6: version `GLIBCXX_3.4.30' not found
```

Please try installing the corresponding dependencies in your conda environment:
```shell
conda install -c conda-forge gcc=12 -y
```
