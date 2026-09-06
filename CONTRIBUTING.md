# Contributing to LeIsaac

Thanks for your interest in contributing to LeIsaac! This document describes how to report issues, propose changes, and submit pull requests.

## This fork (kevineen/leisaac)

日常の改造は **この fork だけ** に push する。公式 `LightwheelAI/leisaac` へはプルリクを出さない。公式の大きな更新は `upstream/main` から必要なときだけ取り込む。手順はリポジトリ直下の [note.txt](note.txt) を参照。

本家向けの貢献をする場合は、公式リポジトリ側の CONTRIBUTING に従う。

## Code of conduct

Be respectful and constructive. Assume good intent.

## Getting help / asking questions

- Check the project documentation: https://lightwheelai.github.io/leisaac/
- If you're unsure whether something is a bug or a usage question, open a GitHub Issue with details.

## Reporting bugs

When filing an issue, please include:

- What you expected to happen vs what happened
- Minimal steps to reproduce
- Your environment (OS, GPU, driver, Python version, Isaac Sim / IsaacLab version)
- Relevant logs and stack traces (as text)

## Proposing changes

For non-trivial changes (new features, refactors, API changes), please open an issue first to align on scope and design.

## Pull request guidelines

- Keep PRs focused: one logical change per PR.
- Write clear commit messages.
- Update documentation when behavior or usage changes.
- Describe a manual test plan in the PR.

## Style and linting

LeIsaac uses `pre-commit` for formatting and lint checks (see `.pre-commit-config.yaml` at the repo root). GitHub Actions also runs these checks on every PR/update.

It is strongly recommended to run the checks locally before opening/updating a PR.

```bash
# Install pre-commit:
pip install pre-commit
# Install the git hooks (one time per clone):
pre-commit install
# Run all hooks on all files (recommended before opening/updating a PR):
pre-commit run --all-files
```

## License

By contributing, you agree that your contributions will be licensed under the project's license (see `LICENSE`).
