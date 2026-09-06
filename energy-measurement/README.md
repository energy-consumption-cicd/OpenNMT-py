# Energy measurement instrumentation

## Purpose

This directory is not part of the upstream OpenNMT-py repository. It was added
to measure the energy consumption of CI/CD pipeline commands on controlled
hardware, using Intel RAPL counters. The measured construct is the energy of
the CI commands on a controlled bench, not the energy of GitHub-hosted CI in
production.

## Non-invasiveness

No original project file is created or modified. The only additions are this
directory and `.github/workflows/energy-measurement.yml`. Verify against the
upstream commit this fork is instrumented on:

```bash
git diff --stat 97111d97551c24857076a4102eabdb468b35cff4
```

## What is measured

Energy is read from the Intel RAPL counters under
`/sys/class/powercap/intel-rapl`, for four domains: package (`pkg`), cores,
uncore (reported as `gpu`, structurally zero on this bench) and DRAM (`ram`).
Counter deltas are overflow-corrected against `max_energy_range_uj`, read from
sysfs at run time rather than hardcoded.

Each run measures a 120 s idle baseline first and derives a per-second rate per
domain. Reported energy per stage is

```
net = max(raw_delta - baseline_rate * wall_time_s, 0)
```

The clamp at zero prevents a negative DRAM figure on light memory workloads;
the unclamped DRAM value is kept as the diagnostic column
`energy_ram_liquid_raw_j`. The baseline rate used in the subtraction is recorded
in every row (`baseline_rate_*_w`).

`wall_time_s` covers the whole `docker run --rm` lifecycle, including container
setup and teardown, because the RAPL reading window covers the same interval.

Per-stage CPU time is captured inside the container: file descriptor 3
preserves the workload's stderr while `time` writes to `/timing`, so the CPU
time of child processes is attributed to the stage instead of to the host
`docker` client.

The exit code of each stage container is written to
`runs/exit_codes_run_NN.txt`. It is the only rejection criterion for a run; the
measurement is kept either way.

## How to run

```bash
docker build -t opennmt-py-medicao -f energy-measurement/Dockerfile .
bash energy-measurement/run_pipeline.sh 1
```

The workflow runs the same script on a self-hosted runner, dispatched manually:

```bash
gh workflow run energy-measurement.yml -f campaign=validation   # run 0 only
gh workflow run energy-measurement.yml -f campaign=full         # warm-up + 10 runs + median
```

`full` refuses to start when `runs/` already holds a run CSV: a campaign is one
continuous session, and no earlier result is reused.

## Stages

Each stage runs in its own container from the repository root, so build
artifacts do not survive into the later stages; the image itself carries the
installed environment that `test` and `train` use (D9). Commands are copied verbatim
from the upstream workflow `.github/workflows/push.yml`, job `lint-and-tests`
(`ubuntu-latest`, Python 3.9).

| stage | upstream steps | `push.yml` lines |
|---|---|---|
| `build` | "Install dependencies": the eight `pip` commands, including the `requirements.txt` guard (a no-op, the file does not exist upstream) | 21-28 |
| `test` | "Check code with Black", "Lint with flake8", "Unit tests" | 31, 34, 37 |
| `train` | "Test vocabulary build" and "with features", "Test field/transform dump", every `train.py` step from "Test RNN training" to "Testing training with features and dynamic scoring", "Test checkpoint vocabulary update" and "with LM" | 38-343, 503-536, 537-571 |

Left out: the translation, generation and inference-engine steps (lines
344-479), the tool steps (480-502) and the `build-docs` job.

## Deviations from the upstream pipeline

| id | deviation | reason |
|---|---|---|
| D1 | Wheels are downloaded at image build time into `/wheels`, verified by `pip download --require-hashes` against locks generated with `uv pip compile --generate-hashes`. The measured `build` stage runs the upstream `pip` commands unchanged, with `PIP_NO_INDEX=1 PIP_FIND_LINKS=/wheels` set in the image. A second lock holds the current `flake8` release, so the upstream sequence "install flake8, then pin flake8==3.8.*" happens offline as it does online. | Measured containers run with `--network none`; RAPL has no network domain. |
| D2 | Dependency resolution is frozen at the image build date through `UV_EXCLUDE_NEWER=2026-09-06T00:00:00Z`, honored by `uv pip compile` (uv 0.12.9 reads the variable; no explicit `--exclude-newer` flag). | Reproducible dependency set; several unpinned dependencies have dropped Python 3.9 in their latest releases. |
| D3 | `ubuntu-latest` with `actions/setup-python` 3.9 is replaced by `python:3.9-bookworm` pinned by digest, under `docker run --privileged --network none --memory=12g --memory-swap=12g`. | Dedicated bench; Python 3.9 is end-of-life. |
| D4 | Only the three stages above are executed; translation, inference, tool and documentation steps are omitted. | Study scope. |
| D5 | The `requirements.txt` guard is kept literally although the file does not exist. | Literal fidelity to the upstream step. |
| D7 | The main lock is resolved under the constraint `numpy<2` (1.26.4 instead of 2.0.2); every other pinned package is unchanged. | `torch` wheels below 2.3 are built against the numpy 1.x ABI; `torch.from_numpy` and `Tensor.numpy()` fail under numpy 2, and both are on the `train` path (GGNN encoder, validation scoring). |
| D8 | `spacy`, `thinc` and `blis` are resolved with `--only-binary` (3.8.7, 8.3.4, 1.2.0 instead of the sdist-only 3.8.11, 8.3.9, 1.3.3). | Their newer releases publish no cp39 wheel while still declaring `>=3.9`, so an offline install would have to compile Cython extensions; the upstream job installed wheels when it ran. Every other pinned package has a wheel; `pyrouge` is the only sdist and is pure Python. |
| D9 | The image ships the environment installed by the same eight `pip` commands, and the measured `build` stage reinstalls it into a fresh `python -m venv /tmp/venv-build` placed first on `PATH`. | Each stage runs in its own container; `test` and `train` need the packages the upstream job had installed in the same runner. The venv keeps the measured install complete rather than a no-op. |

`torch` is installed from PyPI as upstream does (CUDA-enabled wheel with its
`nvidia-*` dependencies); no `+cpu` substitution is made.

## Output schema

One CSV per run, one row per stage plus a `total` row:

```
run, stage, energy_pkg_j, energy_cores_j, energy_gpu_j, energy_ram_j,
wall_time_s, user_time_s, sys_time_s, energy_ram_liquid_raw_j,
wall_time_container_s, baseline_rate_pkg_w, baseline_rate_cores_w,
baseline_rate_ram_w
```

The first nine columns are the official schema shared by every project in the
study; the remaining five are diagnostic. `baseline_rate_*_w` is the idle rate
(W) subtracted in that run, repeated in every row.

## Reproducibility notes

Bench: Intel Core i7-9700 (8 cores, no SMT), 16 GB RAM, Crucial BX500 SATA SSD,
Ubuntu 24.04 LTS, kernel 6.8.0, Docker 29.x.

Container flags: `--rm --privileged --network none --memory=12g --memory-swap=12g`.

The `test` and `train` stages inherit the upstream parallelism settings without
override (`-num_workers 0` on every training call, single process, default
torch thread count); the bench has 8 cores against 4 on a GitHub-hosted runner.
Training seeds are not set upstream and are not set here.
