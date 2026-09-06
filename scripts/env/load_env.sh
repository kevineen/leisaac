#!/usr/bin/env bash
# Load machine-local settings from .env.local and derive paths / GPU helpers.
#
# Usage:
#   cd ~/robot/leisaac
#   source scripts/env/load_env.sh
#   leisaac_env_info          # show resolved config
#   leisaac_gpu_smi           # nvidia-smi or rocm-smi
#   leisaac_require_isaac     # exit 1 if Isaac not supported on this GPU
#   leisaac_use_data_root /mnt/other/robot   # switch drive for this shell
#
# Permanent path changes: edit .env.local (ROBOT_DATA_ROOT=...).
# Do not use `VAR=value source ...` — bash may discard the prefix after source.
#
# Windows (Git Bash / WSL): same script works if paths use forward slashes.

# Prevent nested "source" from resetting when already loaded with --force
_LEISAAC_ENV_FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  _LEISAAC_ENV_FORCE=1
fi

# Keys explicitly present in .env.local (individual path overrides)
_LEISAAC_DOTENV_KEYS=""

_leisaac_find_repo_root() {
  local start dir
  start="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  dir="$start"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.env.example" || -d "$dir/source/leisaac" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "$start"
}

LEISAAC_REPO_ROOT="$(_leisaac_find_repo_root)"
export LEISAAC_REPO_ROOT

_leisaac_dotenv_has() {
  [[ " ${_LEISAAC_DOTENV_KEYS} " == *" $1 "* ]]
}

_leisaac_load_dotenv() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  _LEISAAC_DOTENV_KEYS=""
  # KEY=VALUE lines only; ignore comments / blanks. Do not eval.
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      # Strip optional surrounding quotes
      if [[ "$val" =~ ^\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
      elif [[ "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi
      _LEISAAC_DOTENV_KEYS="${_LEISAAC_DOTENV_KEYS} ${key}"
      # Do not override already-exported vars unless --force
      if [[ "$_LEISAAC_ENV_FORCE" -eq 1 ]] || [[ ! -v "$key" ]]; then
        export "$key=$val"
      fi
    fi
  done <"$file"
  return 0
}

_leisaac_detect_gpu() {
  # Prefer explicit GPU_VENDOR if not auto
  local vendor="${GPU_VENDOR:-auto}"
  vendor="$(echo "$vendor" | tr '[:upper:]' '[:lower:]')"
  if [[ "$vendor" != "auto" ]]; then
    echo "$vendor"
    return 0
  fi

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    # Some AMD systems still have nvidia-smi stub; prefer PCI class if only AMD VGA
    if command -v lspci >/dev/null 2>&1; then
      local pci
      pci="$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' || true)"
      if echo "$pci" | grep -qi 'NVIDIA' && ! echo "$pci" | grep -qi 'AMD/ATI'; then
        echo "nvidia"
        return 0
      fi
      if echo "$pci" | grep -qi 'NVIDIA'; then
        # Both present: prefer NVIDIA for Isaac if driver works
        echo "nvidia"
        return 0
      fi
      if echo "$pci" | grep -qi 'AMD/ATI\|Advanced Micro Devices'; then
        echo "amd"
        return 0
      fi
    fi
    echo "nvidia"
    return 0
  fi

  if command -v rocm-smi >/dev/null 2>&1 && rocm-smi >/dev/null 2>&1; then
    echo "amd"
    return 0
  fi

  if command -v lspci >/dev/null 2>&1; then
    local pci
    pci="$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' || true)"
    if echo "$pci" | grep -qi 'NVIDIA'; then
      echo "nvidia"
      return 0
    fi
    if echo "$pci" | grep -qi 'AMD/ATI\|Advanced Micro Devices'; then
      echo "amd"
      return 0
    fi
  fi

  echo "none"
}

_leisaac_set_path_default() {
  # $1=VAR $2=default — keep value if it was explicitly set in .env.local
  local var="$1"
  local default="$2"
  if _leisaac_dotenv_has "$var"; then
    # Expand ~ on explicit override
    local cur="${!var:-}"
    cur="${cur/#\~/$HOME}"
    export "$var=$cur"
  else
    export "$var=$default"
  fi
}

_leisaac_derive_paths() {
  local root="${ROBOT_DATA_ROOT:-}"
  if [[ -z "$root" ]]; then
    root="${LEISAAC_REPO_ROOT}/.local_data"
  fi

  # Expand ~ if present
  root="${root/#\~/$HOME}"
  export ROBOT_DATA_ROOT="$root"

  _leisaac_set_path_default LEISAAC_ASSETS_ROOT "$root/assets"
  _leisaac_set_path_default ROBOT_DATASETS_HDF5 "$root/datasets/hdf5"
  _leisaac_set_path_default ROBOT_DATASETS_LEROBOT "$root/datasets/lerobot"
  _leisaac_set_path_default ROBOT_MODELS_CHECKPOINTS "$root/models/checkpoints"
  _leisaac_set_path_default ROBOT_MODELS_DEPLOY "$root/models/deploy"
  _leisaac_set_path_default ROBOT_LOGS "$root/logs"
  _leisaac_set_path_default ROBOT_EXPORTS "$root/exports"

  if _leisaac_dotenv_has LEROBOT_HOME; then
    local lh="${LEROBOT_HOME/#\~/$HOME}"
    export LEROBOT_HOME="$lh"
  else
    export LEROBOT_HOME="$ROBOT_DATASETS_LEROBOT"
  fi
  if _leisaac_dotenv_has HF_HOME; then
    local hf="${HF_HOME/#\~/$HOME}"
    export HF_HOME="$hf"
  else
    export HF_HOME="$root/hf_cache"
  fi
}

_leisaac_apply_gpu() {
  export GPU_VENDOR_DETECTED="$(_leisaac_detect_gpu)"
  # Keep GPU_VENDOR as configured intent; expose resolved value separately
  export GPU_BACKEND="$GPU_VENDOR_DETECTED"

  case "$GPU_BACKEND" in
    nvidia)
      export GPU_SMI_CMD="nvidia-smi"
      export TORCH_DEVICE="cuda"
      export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
      ;;
    amd)
      export GPU_SMI_CMD="rocm-smi"
      export TORCH_DEVICE="cuda" # ROCm uses cuda device API in PyTorch
      # Prefer HIP visibility if user has not set it
      export HIP_VISIBLE_DEVICES="${HIP_VISIBLE_DEVICES:-0}"
      ;;
    *)
      export GPU_SMI_CMD="true"
      export TORCH_DEVICE="cpu"
      ;;
  esac

  local isaac_flag
  isaac_flag="$(echo "${ISAAC_ENABLED:-auto}" | tr '[:upper:]' '[:lower:]')"
  case "$isaac_flag" in
    true|1|yes|on)
      export ISAAC_SUPPORTED=1
      ;;
    false|0|no|off)
      export ISAAC_SUPPORTED=0
      ;;
    *)
      if [[ "$GPU_BACKEND" == "nvidia" && "${MACHINE_ROLE:-training}" == "training" ]]; then
        export ISAAC_SUPPORTED=1
      else
        export ISAAC_SUPPORTED=0
      fi
      ;;
  esac
}

# --- public helpers ---------------------------------------------------------

leisaac_gpu_smi() {
  case "${GPU_BACKEND:-none}" in
    nvidia)
      nvidia-smi "$@"
      ;;
    amd)
      rocm-smi "$@"
      ;;
    *)
      echo "No GPU backend (GPU_BACKEND=${GPU_BACKEND:-unset})" >&2
      return 1
      ;;
  esac
}

leisaac_require_isaac() {
  if [[ "${ISAAC_SUPPORTED:-0}" != "1" ]]; then
    cat >&2 <<EOF
Isaac Sim / Isaac Lab is not enabled on this machine.
  MACHINE_ROLE=${MACHINE_ROLE:-?}
  GPU_BACKEND=${GPU_BACKEND:-?}
  ISAAC_ENABLED=${ISAAC_ENABLED:-?}
  ISAAC_SUPPORTED=${ISAAC_SUPPORTED:-0}

NVIDIA GPU + MACHINE_ROLE=training が必要です（現状は AMD の場合保留）。
EOF
    return 1
  fi
  return 0
}

leisaac_use_data_root() {
  # Switch ROBOT_DATA_ROOT for this shell and refresh derived paths.
  if [[ -z "${1:-}" ]]; then
    echo "Usage: leisaac_use_data_root /path/to/robot_data" >&2
    return 1
  fi
  export ROBOT_DATA_ROOT="${1/#\~/$HOME}"
  # Ignore previous per-path dotenv overrides so the new root wins for this session
  _LEISAAC_DOTENV_KEYS=""
  _leisaac_derive_paths
  echo "ROBOT_DATA_ROOT=$ROBOT_DATA_ROOT"
  echo "LEISAAC_ASSETS_ROOT=$LEISAAC_ASSETS_ROOT"
}

leisaac_mkdir_data() {
  mkdir -p \
    "$LEISAAC_ASSETS_ROOT/robots" \
    "$LEISAAC_ASSETS_ROOT/scenes" \
    "$ROBOT_DATASETS_HDF5" \
    "$ROBOT_DATASETS_LEROBOT" \
    "$ROBOT_MODELS_CHECKPOINTS" \
    "$ROBOT_MODELS_DEPLOY" \
    "$ROBOT_LOGS" \
    "$ROBOT_EXPORTS"
  echo "Ensured data dirs under $ROBOT_DATA_ROOT"
}

leisaac_env_info() {
  cat <<EOF
=== LeIsaac machine env ===
MACHINE_NAME=${MACHINE_NAME:-}
MACHINE_ROLE=${MACHINE_ROLE:-}
MACHINE_OS=${MACHINE_OS:-}
GPU_VENDOR(config)=${GPU_VENDOR:-}
GPU_BACKEND(resolved)=${GPU_BACKEND:-}
GPU_SMI_CMD=${GPU_SMI_CMD:-}
TORCH_DEVICE=${TORCH_DEVICE:-}
ISAAC_SUPPORTED=${ISAAC_SUPPORTED:-}
LEISAAC_REPO_ROOT=${LEISAAC_REPO_ROOT:-}
ROBOT_DATA_ROOT=${ROBOT_DATA_ROOT:-}
LEISAAC_ASSETS_ROOT=${LEISAAC_ASSETS_ROOT:-}
ROBOT_DATASETS_HDF5=${ROBOT_DATASETS_HDF5:-}
ROBOT_DATASETS_LEROBOT=${ROBOT_DATASETS_LEROBOT:-}
ROBOT_MODELS_CHECKPOINTS=${ROBOT_MODELS_CHECKPOINTS:-}
ROBOT_MODELS_DEPLOY=${ROBOT_MODELS_DEPLOY:-}
LEROBOT_REPO=${LEROBOT_REPO:-}
LEROBOT_HOME=${LEROBOT_HOME:-}
HF_HOME=${HF_HOME:-}
EOF
}

# --- main -------------------------------------------------------------------

if [[ ! -f "$LEISAAC_REPO_ROOT/.env.local" ]]; then
  echo "[leisaac env] WARN: $LEISAAC_REPO_ROOT/.env.local がありません。" >&2
  echo "  cp $LEISAAC_REPO_ROOT/.env.example $LEISAAC_REPO_ROOT/.env.local して編集してください。" >&2
else
  _leisaac_load_dotenv "$LEISAAC_REPO_ROOT/.env.local"
fi

# Defaults if still unset
export MACHINE_ROLE="${MACHINE_ROLE:-training}"
export MACHINE_OS="${MACHINE_OS:-linux}"
export GPU_VENDOR="${GPU_VENDOR:-auto}"
export ISAAC_ENABLED="${ISAAC_ENABLED:-auto}"

_leisaac_derive_paths
_leisaac_apply_gpu

# Quiet by default when sourced; pass --verbose to print
if [[ "${1:-}" == "--verbose" || "${2:-}" == "--verbose" ]]; then
  leisaac_env_info
fi
