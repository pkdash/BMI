# QUICKSTART

Minimal copy-paste workflow.

## 1) Build image

```bash
docker build --pull --no-cache -t cfe-babelizer .
```

## 2) Run container (mount current folder)

```bash
# Linux/MacOS
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  cfe-babelizer
```

```powershell
# Windows (PowerShell)
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  cfe-babelizer
```

```cmd
:: Windows (Command Prompt)
docker run --rm -it ^
  -v "%cd%:/workspace/user" ^
  -w /workspace/user ^
  cfe-babelizer
```

## 3) Generate wrapper + patch + build

Inside container:

```bash
./regen_and_build.sh
```

This runs:

- `babelize init babel.toml`
- `./post_babelize_patch.sh`
- `uv build` in `pymt_cfe/`

Artifacts end up in:

```text
pymt_cfe/dist/
```

## 4) Test in container

```bash
cd /workspace/user/pymt_cfe
python -m pip install -e . --no-build-isolation
python -c "from pymt_cfe import CFE; print('pymt_cfe import OK')"
```

## 5) Install from tar.gz (target env)

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-cfe
source .venv-pymt-cfe/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine.)

If `pymt_cfe-*.tar.gz` is next to `install.sh`:

```bash
chmod +x install.sh
./install.sh
```

Or direct install (set CFE paths explicitly if auto-detection fails):

```bash
export CFE_ROOT=/path/to/cfe
export CFE_LIB_DIR=/path/to/cfe/build   # directory containing libcfebmi.so*
export LD_LIBRARY_PATH="$CFE_LIB_DIR:$LD_LIBRARY_PATH"

uv pip install /path/to/pymt_cfe-0.1.tar.gz
# fallback
python -m pip install /path/to/pymt_cfe-0.1.tar.gz
```

## Notes

- Wheels are architecture-specific (`aarch64` vs `x86_64`).
- If import fails with `libcfebmi.so` not found, set `LD_LIBRARY_PATH` to the CFE lib/build directory.

## Windows: CRLF line-ending fix

The shell scripts (`*.sh`) must have Unix LF line endings or bash inside the
Linux container will fail with errors like:

```
$'\r': command not found
```

**Prevention (recommended):** The repo ships a `.gitattributes` file that
forces LF for `*.sh`, `*.toml`, and `Dockerfile`. As long as you clone with a
Git client that respects `.gitattributes` (Git ≥ 2.10), no extra steps are
needed.

**One-time fix if you already have CRLF files:**

Option A — using Git:

```powershell
git config core.autocrlf false
git rm --cached -r .
git reset --hard
```

Option B — using `dos2unix` (install via [Chocolatey](https://chocolatey.org/) or WSL):

```powershell
dos2unix regen_and_build.sh post_babelize_patch.sh install.sh
```

Option C — inside the running container (quickest workaround):

```bash
sed -i 's/\r//' /workspace/user/regen_and_build.sh
sed -i 's/\r//' /workspace/user/post_babelize_patch.sh
```
