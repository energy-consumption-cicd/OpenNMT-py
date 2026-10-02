# Wheels are fetched at image build time so the measured build stage can run
# with --network none; nothing from the project is installed here.
FROM python:3.8.14-bullseye@sha256:041a09359fda61a2b58cec5201560646b66e05137ce2af1cab9ceec920279b53

ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# The tag pins no versions and its CI logs expired: resolution is frozen at the
# instant of the tag commit.
ENV UV_EXCLUDE_NEWER=2022-11-03T18:14:43Z

RUN pip install uv==0.12.9

# requirements.opt.txt installs apex from git inside the measured build stage;
# local mirrors of apex, of its cutlass submodule and of the googletest submodule of cutlass keep that clone offline.
RUN mkdir -p /opt/git && \
    git clone --mirror https://github.com/NVIDIA/apex.git /opt/git/apex.git && \
    git clone --mirror https://github.com/NVIDIA/cutlass.git /opt/git/cutlass.git && \
    git clone --mirror https://github.com/google/googletest.git /opt/git/googletest.git && \
    git -C /opt/git/apex.git cat-file -e 700d6825e205732c1d6be511306ca4e595297070^{commit} && \
    git -C /opt/git/cutlass.git cat-file -e ed2ed4d667ce95e1371bd62db32b6a114e774336^{commit} && \
    git -C /opt/git/googletest.git cat-file -e 9077ec7efe5b652468ab051e93c67589d5cb8f85^{commit} && \
    git config --system url.file:///opt/git/apex.git.insteadOf https://github.com/NVIDIA/apex.git && \
    git config --system url.file:///opt/git/cutlass.git.insteadOf https://github.com/NVIDIA/cutlass.git && \
    git config --system url.file:///opt/git/googletest.git.insteadOf https://github.com/google/googletest.git && \
    git config --system protocol.file.allow always

COPY . /workspace
WORKDIR /workspace

# --python-version carries the patch: a bare 3.8 is read as 3.8.0, which excludes
# releases that require >=3.8.1.
# The apex git requirement stays out of the lock: pip --require-hashes rejects VCS
# requirements; the measured build installs it from the local mirror.
RUN mkdir -p /wheels && \
    printf '%s\n' 'flake8' 'sacrebleu' 'pip' 'setuptools' 'wheel' \
        > /wheels/extra.in && \
    [ "$(grep -c '^git+' requirements.opt.txt)" -eq 1 ] && \
    grep -v '^git+' requirements.opt.txt > /wheels/opt.in && \
    uv pip compile --python-version 3.8.14 --generate-hashes \
        setup.py /wheels/opt.in /wheels/extra.in \
        -o /wheels/requirements.lock && \
    pip download --require-hashes --no-deps -r /wheels/requirements.lock -d /wheels && \
    ls /wheels | wc -l

# The measured build stage runs the upstream pip commands unchanged, resolving
# only from the local wheel directory.
ENV PIP_NO_INDEX=1 PIP_FIND_LINKS=/wheels

# Each stage runs in its own container, so the test and train stages need the
# environment in the image; the build stage reinstalls it into a fresh venv.
RUN python -m pip install --upgrade pip && \
    pip install --upgrade setuptools && \
    pip install -e . && \
    pip install -r requirements.opt.txt && \
    pip install sacrebleu && \
    pip install flake8 && \
    if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
