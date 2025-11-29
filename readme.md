(PoC) Resiliencia ETL con fallback GitHub → Local
===============================================

Resumen
-------
Esta PoC demuestra cómo ejecutar un ETL de forma resiliente desde Jenkins: si el repositorio remoto (GitHub) está accesible se usa/actualiza desde allí; si no, se ejecuta una copia local "congelada" montada como volumen en el contenedor de Jenkins.

Estructura relevante
--------------------
- `infra/docker-compose.yml` : compose principal usado para levantar Jenkins.
- `etl/infra/docker-compose.yml` : copy / alternativo (contenía pruebas durante la PoC).
- `etl/etl-repo/run_etl.py` : script ETL de prueba (este es el código que Jenkins ejecuta en fallback).
- `etl/infra/scripts/run_etl_with_fallback.sh` : script bash utilizado para pruebas locales (comprobación git + fallback + logs).
- `Jenkinsfile` : pipeline de ejemplo (opcional si usas Multibranch).

Qué hemos hecho
---------------
1. Script de comprobación y fallback
	 - Partimos de un script bash simple que: comprueba `git ls-remote` al `REPO_URL`, si responde actualiza/clona en `LOCAL_REPO` y ejecuta el ETL; si no responde, usa `LOCAL_REPO` (copia local).
	 - Mejoras realizadas:
		 - Rutas de `LOCAL_REPO` ajustadas para que apunten a `/workspace/etl-repo` (ruta dentro del contenedor).
		 - Creación robusta de directorio de logs (`./etl-ares-logs`) antes de cada escritura.
		 - Protección ante `git clone` cuando ya existe un directorio no-git (se elimina y vuelve a clonar).
		 - Ejecución del ETL usando la ruta `$LOCAL_REPO/run_etl.py` para evitar errores de path.
		 - Añadidas líneas de depuración para verificar creación de logs y escenario ejecutado.

2. Docker Compose
	 - `infra/docker-compose.yml` actualizado para montar el repo local en el contenedor Jenkins como:

	 - desde WSL: `/mnt/e/workspace/trustme/sumapositiva/pfs/poc-jenkins-etl/etl/etl-repo:/workspace/etl-repo`
	 - o usando ruta relativa (configurada finalmente): `../etl/etl-repo:/workspace/etl-repo` (resuelta desde `infra/`).

	 - El objetivo es que, cuando GitHub no esté disponible, el contenedor Jenkins tenga accesible la copia local montada en `/workspace/etl-repo`.

3. Jenkins
	 - Recomendación de configuración del Job (Freestyle): dejar "Origen del código fuente" en `Ninguno` y en "Build Steps" poner el script / bloque shell que contiene la lógica de fallback; así Jenkins no falla en el checkout si GitHub está caído.
	 - Alternativa: usar `Pipeline` con `Jenkinsfile` en el repo si quieres gestión por SCM; pero entonces Jenkins intentará el checkout y fallará si GitHub no está accesible.

Comandos clave para reproducir
-----------------------------
1) Levantar Jenkins (desde WSL preferible):

```bash
cd /mnt/e/workspace/trustme/sumapositiva/pfs/poc-jenkins-etl/infra
docker compose down
docker compose up -d --build
```

2) Comprobar que el bind-mount está activo (host → contenedor):

```bash
# en el host (WSL):
ls -la /mnt/e/workspace/trustme/sumapositiva/pfs/poc-jenkins-etl/etl/etl-repo

# listar dentro del contenedor:
docker exec -it etl-jenkins bash -c "ls -la /workspace/etl-repo"

# inspeccionar mounts si necesitas ver la fuente exacta:
docker inspect --format '{{json .Mounts}}' etl-jenkins
```

3) Ejecutar el job de Jenkins (si lo has creado como Freestyle): pega en "Execute shell" el bloque:

```bash
REPO_URL="https://github.com/valdepeace/test-etl.git"
BRANCH="main"
LOCAL_REPO="/workspace/etl-repo"

echo "Comprobando acceso a GitHub..."
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
echo "Ejecutando ETL..."
python3 "$LOCAL_REPO/run_etl.py"

```

Notas sobre problemas comunes y soluciones
----------------------------------------
- Volume vacío dentro del contenedor: normalmente causado por que la ruta host no coincide con la ruta que montas, o por permisos/compartición de la unidad en Docker Desktop. En entornos WSL, monta la ruta WSL (`/mnt/e/...`) o usa la ruta relativa desde la carpeta donde ejecutas `docker compose`.
- Si usas Docker Desktop en Windows, asegúrate de que la unidad (E:) está compartida en Settings → Resources → File Sharing o que la integración con WSL está habilitada.
- Si el host path no existía en el momento del `docker compose up`, Docker puede crear un directorio vacío como destino del bind mount; comprueba que el host path existe y contiene archivos antes de levantar el contenedor.
- Para depurar: crea un `testfile.txt` en el host y verifica que aparece dentro del contenedor.

Archivos modificados / creados
-----------------------------
- `etl/infra/scripts/run_etl_with_fallback.sh` — script con comprobación git, fallback y logs (mejorado durante la PoC).
- `infra/docker-compose.yml` — actualizado para montar `../etl/etl-repo:/workspace/etl-repo`.
- `etl/etl-repo/run_etl.py` — script ETL de prueba creado para la PoC.
- `readme.md` (este archivo) — documentación de la PoC.

Próximos pasos sugeridos
-----------------------
- Validar el montaje reiniciando el contenedor y comprobando `ls -la /workspace/etl-repo` dentro del contenedor.
- Añadir tests automáticos simples que verifiquen que el script se ejecuta correctamente en ambos escenarios (remote OK / remote down).
- Si deseas, puedo generar un `requirements.txt` y un entorno virtual para el ETL real, o añadir parametrización YAML para múltiples ETLs (ares, babilonia, ...).

Contacto
-------
Si quieres que aplique cambios concretos (por ejemplo: variables env en Jenkins, añadir artifact frozen tar.gz como tercera vía, o convertir el script en un contenedor independiente), dime cuál y lo implemento.

Script para el Dashboard de Jenkins
----------------------------------
Si vas a crear un job tipo *Freestyle* en la interfaz de Jenkins (sin configurar SCM), pega el siguiente bloque en el paso **Execute shell** del job. El script hace la comprobación de GitHub, aplica el fallback local si hace falta, exporta `PYTHONPATH` y ejecuta el módulo `project.src.etl_ares`.

```bash
#!/bin/bash -x

REPO_URL="https://github.com/valdepeace/test-etl.git"
BRANCH="main"
LOCAL_REPO="/workspace/etl-repo"
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5}

# Cargar variables definidas por Jenkins desde un archivo opcional
# Jenkins puede escribir aquí parámetros o env vars que quieras pasar al script.
CONFIG_FILE="${CONFIG_FILE:-/workspace/jenkins_env.sh}"
echo "###> Cargando variables definidas en Jenkins desde $CONFIG_FILE"
# Exporta todas las variables definidas en el fichero para que estén disponibles para el resto del script
set -a
source "$CONFIG_FILE" 2>/dev/null || true
set +a

echo "###> Variables visibles para Python (comprobación):"
env | grep _SUMA || echo "⚠ No hay variables _SUMA visibles"

echo "Comprobando acceso a GitHub..."
success=false
attempt=1
while [ $attempt -le $MAX_RETRIES ]; do
    if git ls-remote "$REPO_URL" -q > /dev/null 2>&1; then
        success=true
        break
    fi
    echo "Intento $attempt/$MAX_RETRIES fallido. Esperando ${RETRY_DELAY}s..."
    attempt=$((attempt + 1))
    sleep "$RETRY_DELAY"
done

if [ "$success" = true ]; then
    echo "✔ Conexión a GitHub OK. Intentando actualizar código..."
    update_ok=true
    if [ ! -d "$LOCAL_REPO/.git" ]; then
        if [ ! -d "$LOCAL_REPO" ] || [ -z "$(ls -A "$LOCAL_REPO" 2>/dev/null)" ]; then
            # directorio ausente o vacío -> clonamos directamente
            git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$LOCAL_REPO" || update_ok=false
        else
            tmpdir="$(mktemp -d /tmp/etl_clone.XXXXXX)"
            echo "⚠ $LOCAL_REPO existe y no es repo git (o está poblado). Intentando clonar en $tmpdir"
            if git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$tmpdir"; then
                if mv -T "$tmpdir" "$LOCAL_REPO" 2>/dev/null; then
                    echo "✔ Reemplazado $LOCAL_REPO con clon limpio"
                else
                    echo "⚠ No se pudo mover $tmpdir -> $LOCAL_REPO (perm). Manteniendo copia local existente."
                    rm -rf "$tmpdir" || true
                    update_ok=false
                fi
            else
                echo "⚠ Clonado en tmp falló; manteniendo copia local existente si la hay."
                rm -rf "$tmpdir" || true
                update_ok=false
            fi
        fi
    else
        cd "$LOCAL_REPO" || update_ok=false
        if [ "$update_ok" = true ]; then
            git fetch --prune origin || update_ok=false
        fi
        if [ "$update_ok" = true ]; then
            if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
                git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH" || update_ok=false
            else
                echo "⚠ La rama remota origin/$BRANCH no existe. No se actualiza."
                update_ok=false
            fi
        fi
        if [ "$update_ok" = true ]; then
            if [ -n "$(git status --porcelain)" ]; then
                echo "⚠ Cambios locales detectados en $LOCAL_REPO. Forzando reset a origin/$BRANCH"
                git reset --hard "origin/$BRANCH" || update_ok=false
            else
                git pull --ff-only origin "$BRANCH" || git reset --hard "origin/$BRANCH" || update_ok=false
            fi
        fi
        cd - >/dev/null || true
    fi

    if [ "$update_ok" = true ]; then
        SCENARIO="REMOTE_OK_UPDATED"
    else
        echo "⚠ Falló la actualización desde remoto; se usará la copia local si está disponible."
        SCENARIO="REMOTE_DOWN_LOCAL_FALLBACK"
    fi
else
    echo "⚠ No hay acceso a GitHub tras $MAX_RETRIES intentos. Usando copia local..."
    SCENARIO="REMOTE_DOWN_LOCAL_FALLBACK"
fi

echo "ℹ Escenario ejecutado: $SCENARIO"

# Detectar la ubicación del paquete 'project' dentro de `LOCAL_REPO` y exportar PYTHONPATH
# Busca el primer `project/__init__.py` hasta 3 niveles de profundidad y establece su padre como PYTHONPATH
# Detección robusta de la ubicación del paquete 'project'
# 1) Buscar un directorio llamado 'project' (hasta 6 niveles)
# 2) Si no hay directorio, buscar 'project/__init__.py' (hasta 6 niveles)
# 3) Comprobar rutas anidadas comunes (p.ej. 'etl-repo/project')
# 4) Fallback a LOCAL_REPO
PROJECT_DIR="$(find "$LOCAL_REPO" -maxdepth 6 -type d -name project -print -quit 2>/dev/null || true)"
if [ -n "$PROJECT_DIR" ]; then
    PROJECT_PARENT="$(cd "$(dirname "$PROJECT_DIR")" 2>/dev/null && pwd || echo "$LOCAL_REPO")"
    export PYTHONPATH="$PROJECT_PARENT"
    echo "PYTHONPATH detectado y exportado (project dir): $PYTHONPATH"
else
    PROJECT_INIT_PATH="$(find "$LOCAL_REPO" -maxdepth 6 -type f -name '__init__.py' -path '*/project/__init__.py' -print -quit 2>/dev/null || true)"
    if [ -n "$PROJECT_INIT_PATH" ]; then
        PROJECT_PARENT="$(dirname "$PROJECT_INIT_PATH")/.."
        PROJECT_PARENT="$(cd "$PROJECT_PARENT" 2>/dev/null && pwd || echo "$LOCAL_REPO")"
        export PYTHONPATH="$PROJECT_PARENT"
        echo "PYTHONPATH detectado y exportado (via __init__.py): $PYTHONPATH"
    elif [ -d "$LOCAL_REPO/etl-repo/project" ]; then
        PROJECT_PARENT="$(cd "$LOCAL_REPO/etl-repo" 2>/dev/null && pwd || echo "$LOCAL_REPO")"
        export PYTHONPATH="$PROJECT_PARENT"
        echo "PYTHONPATH detectado en nested etl-repo: $PYTHONPATH"
    else
        export PYTHONPATH="$LOCAL_REPO"
        echo "PYTHONPATH fallback: $PYTHONPATH"
    fi
fi

ls -la "$PYTHONPATH" || true

# Ejecutar el módulo Python en modo verboso
exec python3 -u -m project.src.etl_ares
