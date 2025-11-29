<<<<<<< HEAD
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# tests/run_all_scenarios.sh
# Script de pruebas para verificar los distintos escenarios del script de fallback
# Genera logs en tests/logs/

SRCPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="$SRCPATH/tests/logs"
TMPBASE="$SRCPATH/tests/tmp"

REPO_URL_DEFAULT="https://github.com/valdepeace/test-etl.git"
BRANCH_DEFAULT="main"

mkdir -p "$LOGDIR"
mkdir -p "$TMPBASE"

run_fallback_and_run_module() {
    local REPO_URL="$1"
    local BRANCH="$2"
    local LOCAL_REPO="$3"
    local LOGFILE="$4"

    echo "---- Ejecutando escenario: REPO_URL=$REPO_URL LOCAL_REPO=$LOCAL_REPO" | tee -a "$LOGFILE"

    # Parámetros para reintentos
    local MAX_RETRIES=3
    local RETRY_DELAY=2

    local success=false
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        if git ls-remote "$REPO_URL" -q > /dev/null 2>&1; then
            success=true
            break
        fi
        echo "Intento $attempt/$MAX_RETRIES fallido. Esperando ${RETRY_DELAY}s..." | tee -a "$LOGFILE"
        attempt=$((attempt + 1))
        sleep "$RETRY_DELAY"
    done

    local update_ok=true
    if [ "$success" = true ]; then
        echo "Conexión a GitHub OK. Intentando actualizar código..." | tee -a "$LOGFILE"
        if [ ! -d "$LOCAL_REPO/.git" ]; then
            if [ ! -d "$LOCAL_REPO" ] || [ -z "$(ls -A "$LOCAL_REPO" 2>/dev/null)" ]; then
                git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$LOCAL_REPO" >> "$LOGFILE" 2>&1 || update_ok=false
            else
                tmpdir="$(mktemp -d /tmp/etl_clone.XXXXXX)"
                echo "Local existe y no es repo git. Clonando en $tmpdir" | tee -a "$LOGFILE"
                if git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$tmpdir" >> "$LOGFILE" 2>&1; then
                    if mv -T "$tmpdir" "$LOCAL_REPO" 2>/dev/null; then
                        echo "Reemplazado $LOCAL_REPO con clon limpio" | tee -a "$LOGFILE"
                    else
                        echo "No se pudo mover $tmpdir -> $LOCAL_REPO (perm). Manteniendo copia local existente." | tee -a "$LOGFILE"
                        rm -rf "$tmpdir" || true
                        update_ok=false
                    fi
                else
                    echo "Clonado en tmp falló; manteniendo copia local existente si la hay." | tee -a "$LOGFILE"
                    rm -rf "$tmpdir" || true
                    update_ok=false
                fi
            fi
        else
            (cd "$LOCAL_REPO" && git fetch --prune origin) >> "$LOGFILE" 2>&1 || update_ok=false
            if [ "$update_ok" = true ]; then
                if git -C "$LOCAL_REPO" rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
                    git -C "$LOCAL_REPO" checkout "$BRANCH" >> "$LOGFILE" 2>&1 || git -C "$LOCAL_REPO" checkout -b "$BRANCH" "origin/$BRANCH" >> "$LOGFILE" 2>&1 || update_ok=false
                else
                    echo "La rama remota origin/$BRANCH no existe." | tee -a "$LOGFILE"
                    update_ok=false
                fi
            fi
            if [ "$update_ok" = true ]; then
                if [ -n "$(git -C "$LOCAL_REPO" status --porcelain)" ]; then
                    echo "Cambios locales detectados. Forzando reset a origin/$BRANCH" | tee -a "$LOGFILE"
                    git -C "$LOCAL_REPO" reset --hard "origin/$BRANCH" >> "$LOGFILE" 2>&1 || update_ok=false
                else
                    git -C "$LOCAL_REPO" pull --ff-only origin "$BRANCH" >> "$LOGFILE" 2>&1 || git -C "$LOCAL_REPO" reset --hard "origin/$BRANCH" >> "$LOGFILE" 2>&1 || update_ok=false
                fi
            fi
        fi
    else
        echo "No hay acceso a GitHub; se usará copia local si está disponible." | tee -a "$LOGFILE"
        update_ok=false
    fi

    if [ "$update_ok" = true ]; then
        echo "SCENARIO=REMOTE_OK_UPDATED" | tee -a "$LOGFILE"
    else
        echo "SCENARIO=REMOTE_DOWN_LOCAL_FALLBACK" | tee -a "$LOGFILE"
    fi

    # Detección PYTHONPATH (buscar project/__init__.py hasta 3 niveles)
    PROJECT_INIT_PATH="$(find "$LOCAL_REPO" -maxdepth 3 -type f -name '__init__.py' -path '*/project/__init__.py' -print -quit 2>/dev/null || true)"
    if [ -n "$PROJECT_INIT_PATH" ]; then
        PROJECT_PARENT="$(dirname "$PROJECT_INIT_PATH")/.."
        PROJECT_PARENT="$(cd "$PROJECT_PARENT" 2>/dev/null && pwd || echo "$LOCAL_REPO")"
        export PYTHONPATH="$PROJECT_PARENT"
        echo "PYTHONPATH detectado y exportado: $PYTHONPATH" | tee -a "$LOGFILE"
    else
        export PYTHONPATH="$LOCAL_REPO"
        echo "PYTHONPATH fallback: $PYTHONPATH" | tee -a "$LOGFILE"
    fi

    echo "Contenido de PYTHONPATH:" >> "$LOGFILE"
    ls -la "$PYTHONPATH" >> "$LOGFILE" 2>&1 || true

    # Ejecutar el módulo Python y capturar salida
    echo "Ejecutando: python3 -u -m project.src.etl_ares" | tee -a "$LOGFILE"
    (python3 -u -m project.src.etl_ares >> "$LOGFILE" 2>&1) || echo "El módulo devolvió código distinto de 0 (ver log)." | tee -a "$LOGFILE"
    echo "---- Fin escenario" | tee -a "$LOGFILE"
}

echo "Iniciando pruebas en: $SRCPATH" 

# Escenario 1: Remote OK (clonar desde remoto a un tmp LOCAL_REPO limpio)
LOCAL1="$TMPBASE/local_remote_ok"
rm -rf "$LOCAL1" || true
LOG1="$LOGDIR/01_remote_ok.log"
run_fallback_and_run_module "$REPO_URL_DEFAULT" "$BRANCH_DEFAULT" "$LOCAL1" "$LOG1"

# Escenario 2: Remote down -> usar copia local existente
LOCAL2="$TMPBASE/local_remote_down"
rm -rf "$LOCAL2" || true
mkdir -p "$LOCAL2"
# Copiar una copia del repo local (si existe en repo principal) para simular fallback
if [ -d "$SRCPATH/etl/etl-repo" ]; then
    cp -a "$SRCPATH/etl/etl-repo/." "$LOCAL2/" || true
fi
LOG2="$LOGDIR/02_remote_down_local_fallback.log"
run_fallback_and_run_module "https://invalid.example.invalid/repo.git" "$BRANCH_DEFAULT" "$LOCAL2" "$LOG2"

# Escenario 3: Cambios locales detectados (forzar reset)
LOCAL3="$TMPBASE/local_with_changes"
rm -rf "$LOCAL3" || true
git clone --depth 1 -b "$BRANCH_DEFAULT" "$REPO_URL_DEFAULT" "$LOCAL3" >> "$LOGDIR/03_local_changes_setup.log" 2>&1 || true
# Crear cambios locales
echo "dummy change" > "$LOCAL3/LOCAL_CHANGE.txt"
LOG3="$LOGDIR/03_local_changes.log"
run_fallback_and_run_module "$REPO_URL_DEFAULT" "$BRANCH_DEFAULT" "$LOCAL3" "$LOG3"

# Escenario 4: Repo anidado (nested) -> comprobación PYTHONPATH
LOCAL4="$TMPBASE/local_nested_repo"
rm -rf "$LOCAL4" || true
mkdir -p "$LOCAL4/etl-repo"
# Si hay proyecto en el repo principal, copiarlo dentro para simular nested
# Considerar estructuras anidadas (etl/etl-repo/project) o (etl/etl-repo/etl-repo/project)
if [ -d "$SRCPATH/etl/etl-repo/project" ]; then
    cp -a "$SRCPATH/etl/etl-repo/project" "$LOCAL4/etl-repo/" || true
elif [ -d "$SRCPATH/etl/etl-repo/etl-repo/project" ]; then
    cp -a "$SRCPATH/etl/etl-repo/etl-repo/project" "$LOCAL4/etl-repo/" || true
fi
LOG4="$LOGDIR/04_nested_repo.log"
run_fallback_and_run_module "https://invalid.example.invalid/repo.git" "$BRANCH_DEFAULT" "$LOCAL4" "$LOG4"

echo "\nPruebas completadas. Logs generados en: $LOGDIR" 
ls -la "$LOGDIR"

echo "Resumen rápido (últimas líneas de cada log):"
for f in "$LOGDIR"/*.log; do
    echo "---- $f ----"
    tail -n 20 "$f" || true
done

echo "Script de pruebas finalizado." 
=======
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="$ROOT_DIR/tests/logs"
mkdir -p "$LOGDIR"

run_and_log() {
    local name="$1"; shift
    local logfile="$LOGDIR/$(printf "%02d_%s.log" "$RANDOM" "$name")"
    echo "--- Escenario: $name ---" | tee "$logfile"
    echo "PWD: $(pwd)" | tee -a "$logfile"
    echo "PYTHONPATH: ${PYTHONPATH:-<none>}" | tee -a "$logfile"
    if python3 - <<'PY' 2>/dev/null
try:
    import importlib
    importlib.import_module('project.src.etl_ares')
    print('MODULE_OK')
except Exception as e:
    print('MODULE_FAIL', e)
    raise SystemExit(2)
PY
    then
        echo "Ejecutando módulo con -m (project.src.etl_ares)" | tee -a "$logfile"
        python3 -u -m project.src.etl_ares 2>&1 | tee -a "$logfile"
    else
        echo "Import fallback: ejecutando run_etl.py" | tee -a "$logfile"
        python3 "$ROOT_DIR/run_etl.py" 2>&1 | tee -a "$logfile"
    fi
    echo "--- Fin escenario: $name ---" | tee -a "$logfile"
}

echo "Ejecutando escenarios de prueba..."

pushd "$ROOT_DIR" >/dev/null

# 1) Remote OK (suponiendo que el repo está sano localmente)
run_and_log "01_remote_ok"

# 2) Remote down, fallback local (simulado: no git check performed here)
run_and_log "02_remote_down_local_fallback"

# 3) Local changes scenario: tocar un archivo para simular cambios y ejecutar
touch project/README_SIMULATED_LOCAL_CHANGE || true
run_and_log "03_local_changes"
rm -f project/README_SIMULATED_LOCAL_CHANGE || true

# 4) Nested repo scenario: si existe etl-repo/etl-repo/project, mover temporal y re-ejecutar
if [ -d "$ROOT_DIR/etl-repo/etl-repo/project" ]; then
    tmpnest="$(mktemp -d)"
    cp -a "$ROOT_DIR/etl-repo/etl-repo/project" "$tmpnest/project"
    mkdir -p nested_back
    mv "$ROOT_DIR/project" nested_back/ || true
    mv "$tmpnest/project" "$ROOT_DIR/project" || true
    run_and_log "04_nested_repo"
    # restore
    mv nested_back/project "$ROOT_DIR/project" || true
    rm -rf "$tmpnest" nested_back || true
else
    run_and_log "04_nested_repo_skipped"
fi

popd >/dev/null

echo "Tests completados. Logs en: $LOGDIR"
>>>>>>> a172bad5827b4dd8d40bf61054593a1066c8cd89
