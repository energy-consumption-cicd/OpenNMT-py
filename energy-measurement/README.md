# Energy measurement instrumentation (release 3.3.0)

## Purpose

This directory is not part of the upstream OpenNMT-py repository. It was added
to measure the energy consumption of CI/CD pipeline commands on controlled
hardware, using Intel RAPL counters. The measured construct is the energy of
the CI commands on a controlled bench, not the energy of GitHub-hosted CI in
production.

## Non-invasiveness

No original project file is created or modified. The only additions are this
directory and `.github/workflows/energy-measurement.yml`. This branch is the
upstream tag `v3.3.0` (`3afced5689b8d5c3acc441aca50b2893b33dc97d`) plus one
instrumentation commit; verify with:

```bash
git diff --stat v3.3.0 release-3.3.0
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

From the root of a clone of branch `release-3.3.0` (the Dockerfile copies the tree):

```bash
docker build -t opennmt-py-measurement-3.3.0 -f energy-measurement/Dockerfile .
bash energy-measurement/run_pipeline.sh 1
```

The workflow runs the same script on a self-hosted runner, dispatched manually:

```bash
gh workflow run energy-measurement.yml --ref release-3.3.0 -f campaign=validation   # run 0 only
gh workflow run energy-measurement.yml --ref release-3.3.0 -f campaign=full         # warm-up + 10 runs + median
```

`full` refuses to start when `runs/` already holds a run CSV: a campaign is one
continuous session, and no earlier result is reused.

## Stages

Each stage runs in its own container from the repository root, so build
artifacts do not survive into the later stages; the image itself carries the
installed environment that `test` and `train` use (D9). Commands are copied verbatim
from the upstream workflow `.github/workflows/push.yml` at the tag, job
`lint-and-tests` (`ubuntu-latest`, Python 3.8).

| stage | upstream steps | `push.yml` lines |
|---|---|---|
| `build` | "Install dependencies": the eight `pip` commands, including the `requirements.txt` guard (a no-op, the file does not exist upstream) | 21-28 |
| `test` | "Check code with Black", "Lint with flake8", "Unit tests" | 31, 34, 37 |
| `train` | "Test vocabulary build" and "with features", "Test field/transform dump", every `train.py` step from "Test RNN training" to "Testing training with features and dynamic scoring", "Test checkpoint vocabulary update" and "with LM" | 38-286, 416-449, 450-484 |

Left out: the translation and generation steps (lines
287-392), the tool steps (393-415) and the `build-docs` job.

## Deviations from the upstream pipeline

| id | deviation | reason |
|---|---|---|
| D1 | Wheels are downloaded at image build time into `/wheels`, verified by `pip download --require-hashes` against locks generated with `uv pip compile --generate-hashes`. The measured `build` stage runs the upstream `pip` commands unchanged, with `PIP_NO_INDEX=1 PIP_FIND_LINKS=/wheels` set in the image. A second lock holds the current `flake8` release, so the upstream sequence "install flake8, then pin flake8==3.8.*" happens offline as it does online. | Measured containers run with `--network none`; RAPL has no network domain. |
| D2 | Dependency resolution is frozen at the instant of the tag commit through `UV_EXCLUDE_NEWER=2023-06-22T11:02:13Z`, honored by `uv pip compile` (uv 0.12.9 reads the variable; no explicit `--exclude-newer` flag), with `--python-version 3.8.17`. | The tag pins no versions and its CI logs expired. |
| D3 | `ubuntu-latest` with `actions/setup-python` 3.8 is replaced by `python:3.8.17-bookworm` pinned by digest, under `docker run --privileged --network none --memory=12g --memory-swap=12g`. | Dedicated bench; 3.8.17 is the latest 3.8 release that `actions/python-versions` lists before the tag commit. |
| D4 | Only the three stages above are executed; translation, inference, tool and documentation steps are omitted. | Study scope. |
| D5 | The `requirements.txt` guard is kept literally although the file does not exist. | Literal fidelity to the upstream step. |
| D9 | The image ships the environment installed by the same eight `pip` commands, and the measured `build` stage reinstalls it into a fresh `python -m venv /tmp/venv-build` placed first on `PATH`. | Each stage runs in its own container; `test` and `train` need the packages the upstream job had installed in the same runner. The venv keeps the measured install complete rather than a no-op. |
| D10 | `requirements.opt.txt` installs `apex` from `git+https://github.com/NVIDIA/apex.git@700d6825e205732c1d6be511306ca4e595297070`. The image holds mirrors of that repository, of its `cutlass` submodule and of the `googletest` submodule of `cutlass`, and a system git configuration (`url.<mirror>.insteadOf`, `protocol.file.allow always`) redirects both URLs to them; the clone, the checkout, the submodule update, the package build and the install still run inside the measured `build` stage. The lock of D1 is computed over a copy of `requirements.opt.txt` without that line; the upstream file is not modified. | Measured containers run with `--network none`; `pip --require-hashes` rejects version-control requirements. |

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

Two sidecars per stage sit next to the CSV: `swap_run_NN_<stage>.txt` (host
`pswpin` and `pswpout` from `/proc/vmstat`) and `temp_run_NN_<stage>.txt`
(hwmon `coretemp`, `Package id 0`). Both are read immediately before and after
the stage's RAPL window, never inside it.

## Reproducibility notes

Bench: Intel Core i7-9700 (8 cores, no SMT), 16 GB RAM, Crucial BX500 SATA SSD,
Ubuntu 24.04 LTS, kernel 6.8.0, Docker 29.x.

Container flags: `--rm --privileged --network none --memory=12g --memory-swap=12g`.

The `test` and `train` stages inherit the upstream parallelism settings without
override (`-num_workers 0` on every training call, single process, default
torch thread count); the bench has 8 cores against 4 on a GitHub-hosted runner.
Training seeds are not set upstream and are not set here.
