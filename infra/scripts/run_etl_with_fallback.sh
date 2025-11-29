#!/bin/bash
set -euo pipefail

REPO_URL="${REPO_URL:?REPO_URL no definido}"
BRANCH="${BRANCH:-main}"
LOCAL_REPO="${LOCAL_REPO:-/workspace/etl-repo}"

LOG_DIR="./etl-ares-logs"
echo "Creando directorio de logs en $LOG_DIR"
mkdir -p "$LOG_DIR"
ls -l "$LOG_DIR"
LOG_FILE="$LOG_DIR/etl-ares.log"

mkdir -p "$LOG_DIR"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') - INICIO ETL ARES ===" | tee -a "$LOG_FILE"
mkdir -p "$LOG_DIR"
echo "Repo remoto: $REPO_URL" | tee -a "$LOG_FILE"
mkdir -p "$LOG_DIR"
echo "Ruta local : $LOCAL_REPO" | tee -a "$LOG_FILE"

SCENARIO=""

echo "📡 Comprobando acceso al repositorio remoto..."
if git ls-remote "$REPO_URL" -q > /dev/null 2>&1; then
  mkdir -p "$LOG_DIR"
  echo "✔ Repositorio accesible. Actualizando..." | tee -a "$LOG_FILE"

  if [ ! -d "$LOCAL_REPO/.git" ]; then
    if [ -d "$LOCAL_REPO" ]; then
      rm -rf "$LOCAL_REPO"
    fi
    mkdir -p "$LOG_DIR"
    echo "➡ Clonando repo en $LOCAL_REPO" | tee -a "$LOG_FILE"
    git clone "$REPO_URL" "$LOCAL_REPO"
  fi

  cd "$LOCAL_REPO"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"

  SCENARIO="REMOTE_OK_UPDATED"
else
  mkdir -p "$LOG_DIR"
  echo "⚠ No hay acceso al repositorio remoto. Usando copia local..." | tee -a "$LOG_FILE"

  if [ ! -d "$LOCAL_REPO" ]; then
    mkdir -p "$LOG_DIR"
    echo "❌ No existe copia local en $LOCAL_REPO. No puedo continuar." | tee -a "$LOG_FILE"
    exit 1
  fi

  cd "$LOCAL_REPO"
  SCENARIO="REMOTE_DOWN_LOCAL_FALLBACK"
fi

mkdir -p "$LOG_DIR"
echo "ℹ Escenario ejecutado: $SCENARIO" | tee -a "$LOG_FILE"

mkdir -p "$LOG_DIR"
echo "🚀 Ejecutando ETL..." | tee -a "$LOG_FILE"
mkdir -p "$LOG_DIR"
python3 "$LOCAL_REPO/run_etl.py" "$@" | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

mkdir -p "$LOG_DIR"
echo "➡ ETL finalizado con código: $EXIT_CODE" | tee -a "$LOG_FILE"
mkdir -p "$LOG_DIR"
echo "$(date '+%Y-%m-%d %H:%M:%S') | SCENARIO=$SCENARIO | EXIT_CODE=$EXIT_CODE" >> "$LOG_FILE"
mkdir -p "$LOG_DIR"
echo "=== FIN ETL ARES ===" | tee -a "$LOG_FILE"

exit "$EXIT_CODE"
