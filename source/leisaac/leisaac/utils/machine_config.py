"""Machine-local configuration from ``.env.local``.

Loads repository ``.env.local`` (if present), derives data paths, and resolves
GPU / Isaac capability. Safe to import early; does not require python-dotenv.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

MachineRole = Literal["training", "teleop", "deploy"]
MachineOs = Literal["linux", "windows", "raspberrypi"]
GpuBackend = Literal["nvidia", "amd", "none"]

_ENV_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
_LOADED = False


def find_repo_root(start: Path | None = None) -> Path:
    """Walk parents until ``.env.example`` or ``source/leisaac`` is found."""
    cur = (start or Path.cwd()).resolve()
    for candidate in [cur, *cur.parents]:
        if (candidate / ".env.example").is_file() or (candidate / "source" / "leisaac").is_dir():
            return candidate
    # Fallback: leisaac/utils/machine_config.py -> parents[4] == repo root
    return Path(__file__).resolve().parents[4]


def _strip_quotes(value: str) -> str:
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value


def load_dotenv_file(path: Path, *, override: bool = False) -> None:
    """Parse KEY=VALUE into ``os.environ`` without executing shell syntax."""
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = _ENV_LINE.match(line)
        if not match:
            continue
        key, value = match.group(1), _strip_quotes(match.group(2).strip())
        if override or key not in os.environ:
            os.environ[key] = value


def _run_ok(cmd: list[str]) -> bool:
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, timeout=8)
        return True
    except (OSError, subprocess.TimeoutExpired):
        return False


def _lspci_text() -> str:
    if not shutil.which("lspci"):
        return ""
    try:
        result = subprocess.run(
            ["lspci"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        return result.stdout or ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def detect_gpu_backend(configured: str | None = None) -> GpuBackend:
    """Resolve ``nvidia`` / ``amd`` / ``none`` from config or hardware."""
    vendor = (configured or os.environ.get("GPU_VENDOR", "auto")).strip().lower()
    if vendor in {"nvidia", "amd", "none"}:
        return vendor  # type: ignore[return-value]
    if vendor not in {"auto", ""}:
        # Unknown value: fall through to detection
        pass

    pci = _lspci_text().lower()
    has_nvidia_pci = "nvidia" in pci
    has_amd_pci = ("amd/ati" in pci) or ("advanced micro devices" in pci)

    nvidia_smi = shutil.which("nvidia-smi")
    rocm_smi = shutil.which("rocm-smi")

    if nvidia_smi and _run_ok(["nvidia-smi"]):
        if has_nvidia_pci:
            return "nvidia"
        if has_amd_pci and not has_nvidia_pci:
            # Stub / leftover nvidia-smi on AMD-only box
            if rocm_smi and _run_ok(["rocm-smi"]):
                return "amd"
            return "amd"
        return "nvidia"

    if rocm_smi and _run_ok(["rocm-smi"]):
        return "amd"

    if has_nvidia_pci:
        return "nvidia"
    if has_amd_pci:
        return "amd"
    return "none"


def _expand(path: str) -> str:
    return str(Path(path).expanduser())


def _derive_paths(repo_root: Path) -> dict[str, str]:
    root = os.environ.get("ROBOT_DATA_ROOT") or str(repo_root / ".local_data")
    root = _expand(root)
    os.environ.setdefault("ROBOT_DATA_ROOT", root)

    mapping = {
        "LEISAAC_ASSETS_ROOT": f"{root}/assets",
        "ROBOT_DATASETS_HDF5": f"{root}/datasets/hdf5",
        "ROBOT_DATASETS_LEROBOT": f"{root}/datasets/lerobot",
        "ROBOT_MODELS_CHECKPOINTS": f"{root}/models/checkpoints",
        "ROBOT_MODELS_DEPLOY": f"{root}/models/deploy",
        "ROBOT_LOGS": f"{root}/logs",
        "ROBOT_EXPORTS": f"{root}/exports",
    }
    resolved: dict[str, str] = {"ROBOT_DATA_ROOT": root}
    for key, default in mapping.items():
        value = _expand(os.environ[key]) if key in os.environ and os.environ[key] else default
        os.environ[key] = value
        resolved[key] = value

    os.environ.setdefault("LEROBOT_HOME", resolved["ROBOT_DATASETS_LEROBOT"])
    os.environ.setdefault("HF_HOME", f"{root}/hf_cache")
    resolved["LEROBOT_HOME"] = os.environ["LEROBOT_HOME"]
    resolved["HF_HOME"] = os.environ["HF_HOME"]
    return resolved


def _isaac_supported(gpu: GpuBackend) -> bool:
    flag = os.environ.get("ISAAC_ENABLED", "auto").strip().lower()
    if flag in {"true", "1", "yes", "on"}:
        return True
    if flag in {"false", "0", "no", "off"}:
        return False
    role = os.environ.get("MACHINE_ROLE", "training").strip().lower()
    return gpu == "nvidia" and role == "training"


@dataclass(frozen=True)
class MachineConfig:
    """Resolved machine settings for scripts and training code."""

    repo_root: Path
    machine_name: str
    machine_role: str
    machine_os: str
    gpu_vendor_config: str
    gpu_backend: GpuBackend
    torch_device: str
    gpu_smi_cmd: str
    isaac_supported: bool
    robot_data_root: str
    assets_root: str
    datasets_hdf5: str
    datasets_lerobot: str
    models_checkpoints: str
    models_deploy: str
    logs: str
    exports: str
    lerobot_repo: str
    lerobot_home: str
    hf_home: str

    def ensure_data_dirs(self) -> None:
        """Create standard data directories under ``robot_data_root``."""
        for path in (
            Path(self.assets_root) / "robots",
            Path(self.assets_root) / "scenes",
            Path(self.datasets_hdf5),
            Path(self.datasets_lerobot),
            Path(self.models_checkpoints),
            Path(self.models_deploy),
            Path(self.logs),
            Path(self.exports),
        ):
            path.mkdir(parents=True, exist_ok=True)


def ensure_machine_env(*, override: bool = False, repo_root: Path | None = None) -> MachineConfig:
    """Load ``.env.local``, derive paths / GPU flags, return typed config."""
    global _LOADED
    root = find_repo_root(repo_root)
    env_file = root / ".env.local"
    load_dotenv_file(env_file, override=override)

    os.environ.setdefault("MACHINE_ROLE", "training")
    os.environ.setdefault("MACHINE_OS", "linux")
    os.environ.setdefault("GPU_VENDOR", "auto")
    os.environ.setdefault("ISAAC_ENABLED", "auto")
    os.environ.setdefault("MACHINE_NAME", "local")

    paths = _derive_paths(root)
    gpu = detect_gpu_backend(os.environ.get("GPU_VENDOR"))
    os.environ["GPU_BACKEND"] = gpu
    isaac_ok = _isaac_supported(gpu)
    os.environ["ISAAC_SUPPORTED"] = "1" if isaac_ok else "0"

    if gpu == "nvidia":
        smi, device = "nvidia-smi", "cuda"
        os.environ.setdefault("CUDA_VISIBLE_DEVICES", "0")
    elif gpu == "amd":
        smi, device = "rocm-smi", "cuda"
        os.environ.setdefault("HIP_VISIBLE_DEVICES", "0")
    else:
        smi, device = "true", "cpu"

    os.environ["GPU_SMI_CMD"] = smi
    os.environ["TORCH_DEVICE"] = device

    cfg = MachineConfig(
        repo_root=root,
        machine_name=os.environ.get("MACHINE_NAME", "local"),
        machine_role=os.environ.get("MACHINE_ROLE", "training"),
        machine_os=os.environ.get("MACHINE_OS", "linux"),
        gpu_vendor_config=os.environ.get("GPU_VENDOR", "auto"),
        gpu_backend=gpu,
        torch_device=device,
        gpu_smi_cmd=smi,
        isaac_supported=isaac_ok,
        robot_data_root=paths["ROBOT_DATA_ROOT"],
        assets_root=paths["LEISAAC_ASSETS_ROOT"],
        datasets_hdf5=paths["ROBOT_DATASETS_HDF5"],
        datasets_lerobot=paths["ROBOT_DATASETS_LEROBOT"],
        models_checkpoints=paths["ROBOT_MODELS_CHECKPOINTS"],
        models_deploy=paths["ROBOT_MODELS_DEPLOY"],
        logs=paths["ROBOT_LOGS"],
        exports=paths["ROBOT_EXPORTS"],
        lerobot_repo=os.environ.get("LEROBOT_REPO", ""),
        lerobot_home=paths["LEROBOT_HOME"],
        hf_home=paths["HF_HOME"],
    )
    _LOADED = True
    return cfg


def get_machine_config() -> MachineConfig:
    """Return config, loading ``.env.local`` on first call."""
    return ensure_machine_env(override=False)


if __name__ == "__main__":
    config = ensure_machine_env()
    for field_name in config.__dataclass_fields__:
        print(f"{field_name}={getattr(config, field_name)}")
