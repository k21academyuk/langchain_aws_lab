#!/usr/bin/env bash
#
# Agentic AI on AWS - Healthcare Administration Lab
# One-time environment setup for an Amazon SageMaker Studio JupyterLab space.
#
#   cd ~/agentic-ai-healthcare-lab
#   bash setup_sagemaker.sh
#
# Creates a virtual environment on the space's PERSISTENT home volume, installs
# the dependencies, registers a Jupyter kernel, and downloads the sample document.
# Run it once per space, not once per session.

set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${LAB_DIR}/.venv"
KERNEL_NAME="agentic-lab"
KERNEL_DISPLAY="Python (agentic-lab)"
DATA_DIR="${LAB_DIR}/data"
PDF_PATH="${DATA_DIR}/medicare-and-you.pdf"
PDF_URL="https://www.medicare.gov/publications/10050-medicare-and-you.pdf"

echo "=============================================================="
echo " Agentic AI on AWS - Healthcare Lab setup"
echo " Lab directory: ${LAB_DIR}"
echo "=============================================================="

# ---------------------------------------------------------------------------
# 1. Python version check
#    CrewAI supports 3.10 - 3.13. Failing here with a clear message is much
#    kinder than failing 400 lines into a pip resolution.
# ---------------------------------------------------------------------------
PY_BIN="${PY_BIN:-python3}"
PY_MAJOR=$("${PY_BIN}" -c 'import sys; print(sys.version_info[0])')
PY_MINOR=$("${PY_BIN}" -c 'import sys; print(sys.version_info[1])')

echo ""
echo "[1/5] Checking Python version ..."
echo "      Found Python ${PY_MAJOR}.${PY_MINOR} at $(command -v "${PY_BIN}")"

if [ "${PY_MAJOR}" -ne 3 ] || [ "${PY_MINOR}" -lt 10 ] || [ "${PY_MINOR}" -gt 13 ]; then
  echo ""
  echo "ERROR: this lab needs Python 3.10 - 3.13 (CrewAI's supported range)."
  echo "       You have ${PY_MAJOR}.${PY_MINOR}."
  echo ""
  echo "       Fix: pick a SageMaker Distribution image that ships a supported"
  echo "       version, or point this script at another interpreter:"
  echo "           PY_BIN=python3.12 bash setup_sagemaker.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Disk space check
#    The CrewAI + ChromaDB dependency tree does not fit in the 5 GB default.
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Checking available disk space ..."
AVAIL_KB=$(df -Pk "${LAB_DIR}" | awk 'NR==2 {print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
echo "      ${AVAIL_GB} GB available on this volume"

if [ "${AVAIL_GB}" -lt 8 ]; then
  echo ""
  echo "WARNING: less than 8 GB free. The install will probably fail with"
  echo "         'No space left on device'."
  echo ""
  echo "         Fix: stop the space, edit it to at least 20 GB of storage,"
  echo "         start it again, and re-run this script."
  echo ""
  read -r -p "         Continue anyway? [y/N] " REPLY
  case "${REPLY}" in
    [yY]*) echo "         Continuing ..." ;;
    *) echo "         Stopped."; exit 1 ;;
  esac
fi

# ---------------------------------------------------------------------------
# 3. Virtual environment
#    It MUST live under the home directory. Packages installed into the image's
#    own Python are discarded when the space restarts; the home directory is on
#    a persistent EBS volume and survives.
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Creating the virtual environment ..."

if [ -d "${VENV_DIR}" ]; then
  echo "      ${VENV_DIR} already exists - reusing it."
  echo "      (Delete it and re-run this script for a clean rebuild.)"
else
  "${PY_BIN}" -m venv "${VENV_DIR}"
  echo "      Created ${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --quiet --upgrade pip setuptools wheel

# ---------------------------------------------------------------------------
# 4. Dependencies and kernel
#    Expect five to ten minutes. CrewAI and ChromaDB both pull large trees.
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Installing dependencies (this takes 5-10 minutes) ..."
python -m pip install --quiet -r "${LAB_DIR}/requirements.txt"
echo "      Dependencies installed."

echo "      Registering the Jupyter kernel ..."
python -m ipykernel install --user \
  --name "${KERNEL_NAME}" \
  --display-name "${KERNEL_DISPLAY}" >/dev/null
echo "      Kernel registered as '${KERNEL_DISPLAY}'"

# ---------------------------------------------------------------------------
# 5. Sample document for the RAG notebook
#    The Medicare & You handbook is a US Government work in the public domain,
#    published by the Centers for Medicare & Medicaid Services.
# ---------------------------------------------------------------------------
echo ""
echo "[5/5] Fetching the sample document ..."
mkdir -p "${DATA_DIR}"

if [ -f "${PDF_PATH}" ] && [ "$(stat -c%s "${PDF_PATH}" 2>/dev/null || echo 0)" -gt 1000000 ]; then
  echo "      Already present: ${PDF_PATH}"
else
  if curl -fsSL --retry 3 --max-time 180 \
       -A "Mozilla/5.0 (agentic-ai-lab)" \
       -o "${PDF_PATH}" "${PDF_URL}"; then
    echo "      Downloaded to ${PDF_PATH}"
  else
    rm -f "${PDF_PATH}"
    echo ""
    echo "      Download failed - this is not fatal."
    echo "      Notebook 3 will try again, or you can download it manually from:"
    echo "          ${PDF_URL}"
    echo "      and upload it to ${DATA_DIR}/medicare-and-you.pdf"
  fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

==============================================================
 Setup complete.

 Next steps:
   1. Open 1-LangChain-Architecture.ipynb
   2. Click the kernel name in the top-right corner
   3. Choose "${KERNEL_DISPLAY}"
   4. Run cell 1.1 - it should print your SageMaker execution role
   5. Run cell 1.2 - it confirms the role can reach Amazon Bedrock

 There is no .env file and no access key. The notebooks authenticate
 through this space's IAM execution role.

 If "${KERNEL_DISPLAY}" is not in the kernel list, refresh the
 browser tab - JupyterLab caches the set of available kernels.
==============================================================
EOF
