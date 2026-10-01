# QUICKSTART

Minimal copy-paste workflow.

## 1) Build image

```bash
docker build --pull --no-cache -t topmodel-babelizer .
```

## 2) Run container (mount current folder)

```bash
# Linux/MacOS
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  topmodel-babelizer
```

```powershell
# Windows (PowerShell)
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  topmodel-babelizer
```

```cmd
:: Windows (Command Prompt)
docker run --rm -it ^
  -v "%cd%:/workspace/user" ^
  -w /workspace/user ^
  topmodel-babelizer
```

## 3) Generate wrapper + patch + build

Inside container:

```bash
./regen_and_build.sh
```

This runs:

- `babelize init babel.toml`
- `./post_babelize_patch.sh`
- `uv build` in `pymt_topmodel/`

Artifacts end up in:

```text
pymt_topmodel/dist/
```

## 4) Test in container

```bash
cd /workspace/user/pymt_topmodel
python -m pip install -e . --no-build-isolation
python -c "from pymt_topmodel import TOPMODEL; print('pymt_topmodel import OK')"
```

## 5) Install from tar.gz (target env)

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-topmodel
source .venv-pymt-topmodel/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine.)

If `pymt_topmodel-*.tar.gz` is next to `install.sh`:

```bash
chmod +x install.sh
./install.sh
```

Or direct install (set TOPMODEL paths explicitly if auto-detection fails):

```bash
export TOPMODEL_ROOT=/path/to/topmodel
export TOPMODEL_LIB_DIR=/path/to/topmodel/build   # directory containing libtopmodelbmi.so*
export LD_LIBRARY_PATH="$TOPMODEL_LIB_DIR:$LD_LIBRARY_PATH"

uv pip install /path/to/pymt_topmodel-0.1.tar.gz
# fallback
python -m pip install /path/to/pymt_topmodel-0.1.tar.gz
```

## Notes

- Wheels are architecture-specific (`aarch64` vs `x86_64`).
- If import fails with `libtopmodelbmi.so` not found, set `LD_LIBRARY_PATH` to the TOPMODEL lib/build directory.

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
sed -i 's/\r//' /workspace/user/install.sh
```
