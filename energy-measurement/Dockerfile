# Wheels are fetched at image build time so the measured build stage can run
# with --network none; nothing from the project is installed here.
FROM python:3.9-bookworm@sha256:ff12c273af1e1814efcd8dfdefe16a70a4d901afe94dce721ffed8a34176f285

ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# Freeze dependency resolution to the image build date so rebuilds resolve the same set.
ENV UV_EXCLUDE_NEWER=2026-09-06T00:00:00Z

RUN pip install uv==0.12.9

COPY . /workspace
WORKDIR /workspace

# Two locks: the upstream job installs the current flake8 (push.yml:26) before
# pinning it to 3.8.* (push.yml:27), so both versions must be available offline.
# setup.py is resolved from a copy so its egg-info is not written into /workspace.
# numpy<2: torch wheels below 2.3 are built against the numpy 1.x ABI.
# --only-binary: newer spacy/thinc/blis ship no cp39 wheel; the original job installed wheels.
RUN mkdir -p /wheels /tmp/meta && \
    cp setup.py README.md /tmp/meta/ && \
    printf '%s\n' 'black==22.*' 'flake8==3.8.*' 'sacrebleu' 'pip' 'setuptools' 'wheel' \
        > /wheels/extra.in && \
    printf '%s\n' 'numpy<2' > /wheels/constraints.txt && \
    uv pip compile --python-version 3.9 --generate-hashes \
        -c /wheels/constraints.txt \
        --only-binary spacy --only-binary thinc --only-binary blis \
        /tmp/meta/setup.py requirements.opt.txt /wheels/extra.in \
        -o /wheels/requirements.lock && \
    rm -rf /tmp/meta && \
    printf '%s\n' 'flake8' > /wheels/flake8-latest.in && \
    uv pip compile --python-version 3.9 --generate-hashes \
        /wheels/flake8-latest.in \
        -o /wheels/flake8-latest.lock && \
    pip download --require-hashes --no-deps -r /wheels/requirements.lock -d /wheels && \
    pip download --require-hashes --no-deps -r /wheels/flake8-latest.lock -d /wheels && \
    for p in flake8 pyflakes pycodestyle; do \
        n=$(ls /wheels/${p}-*.whl | wc -l); \
        [ "$n" -eq 2 ] || { echo "expected two $p wheels, found $n" >&2; exit 1; }; \
    done && \
    ls /wheels | wc -l

# The measured build stage runs the upstream pip commands unchanged, resolving
# only from the local wheel directory.
ENV PIP_NO_INDEX=1 PIP_FIND_LINKS=/wheels
