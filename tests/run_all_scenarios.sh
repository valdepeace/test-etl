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
