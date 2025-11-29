#!/bin/bash +x

export PYTHONPATH=$WORKSPACE
echo "###> PYTHONPATH --> $PYTHONPATH"

echo "###> Contenido del workspace"
ls -la

echo "###> Cargando variables definidas en Jenkins"
set -a
source "$CONFIG_FILE" 2>/dev/null || true
set +a

echo "###> Variables visibles para Python (comprobación):"
env | grep _SUMA || echo "⚠ No hay variables _SUMA visibles"

echo ""
echo "###> Comprobando acceso a GitHub..."
REPO_URL="https://github.com/valdepeace/test-etl.git"
BRANCH="main"
LOCAL_REPO="./etl-repo"

if git ls-remote "$REPO_URL" -q > /dev/null 2>&1; then
  echo "✔ Conexión a GitHub OK. Actualizando código..."
  if [ ! -d "$LOCAL_REPO/.git" ]; then
    rm -rf "$LOCAL_REPO"
    git clone "$REPO_URL" "$LOCAL_REPO"
  fi
  cd "$LOCAL_REPO"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
  cd -
  SCENARIO="REMOTE_OK_UPDATED"
else
  echo "⚠ No hay acceso a GitHub. Usando copia local..."
  SCENARIO="REMOTE_DOWN_LOCAL_FALLBACK"
fi

echo "ℹ Escenario ejecutado: $SCENARIO"

echo "###> Ejecutando script principal"
exec python3.10 -u -m project.src.etl_ares