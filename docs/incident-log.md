# Bitácora de diagnóstico y reparaciones

Las evidencias de ejecución se guardan en [`docs/evidence/`](evidence/). El log final completo es
[`validation-20261119T235651Z.log`](evidence/validation-20261119T235651Z.log). La evidencia del estado
inicial y de la primera ejecución se conserva en [`validation-20261119T234812Z.log`](evidence/validation-20261119T234812Z.log).

El primer recorrido confirmó el arranque, la comunicación, la persistencia y el fallo controlado; terminó
con código 1 porque el script consultó el estado de salud inmediatamente después de recibir HTTP 200,
cuando Docker todavía indicaba `starting`. Se ajustó el script para esperar la transición a `healthy` y
la validación final terminó con código 0. Se conservan ambos logs para mostrar esa corrección.

## R-01 - Destino de Uvicorn

- **Síntoma observado:** el backend no cargó la aplicación aunque `docker compose up --build -d`
  devolvió estado 0 en modo detached.
- **Evidencia:** los logs del commit original contienen `Error loading ASGI app. Could not import
  module "app".` El Dockerfile ejecutaba `uvicorn app:app` y copiaba `main.py`.
- **Causa raíz:** el módulo indicado en el comando de inicio no existe dentro de la imagen.
- **Elemento modificado:** `backend/Dockerfile`.
- **Reparación:** cambiar el destino de Uvicorn a `main:app`.
- **Justificación:** importa la instancia `app` desde el archivo que sí se copia al contenedor.
- **Verificación:** en el log final `backend health=healthy`; `/api/health` devolvió
  `{"status":"ok","database":"reachable"}`.
- **Impacto:** FastAPI no inicia, por lo que el frontend no puede consumir la API.

## R-02 - Driver y conexión PostgreSQL

- **Síntoma observado:** al ejecutar el módulo existente con Uvicorn, SQLAlchemy no pudo crear el
  engine de PostgreSQL.
- **Evidencia:** al sobreescribir el destino a `main:app` en la imagen original, el proceso terminó
  con `ModuleNotFoundError: No module named 'psycopg2'`. La URL original también apuntaba a
  `localhost` y usaba `wrongpass`, mientras PostgreSQL declaraba la contraseña `rescue123`.
- **Causa raíz:** faltaba un DBAPI de PostgreSQL; además `localhost` dentro del backend apunta al
  propio contenedor y las credenciales no coincidían.
- **Elemento modificado:** `compose.yaml` y `backend/requirements.txt`.
- **Reparación:** usar `postgresql+psycopg` con el DNS de servicio `db`, parametrizar usuario,
  contraseña y base, y agregar `psycopg[binary]==3.2.3`.
- **Justificación:** Compose resuelve el nombre `db` en su red interna; Psycopg 3 provee el driver
  seleccionado explícitamente por SQLAlchemy.
- **Verificación:** el endpoint consultó `SELECT 1` y respondió `database=reachable`; las operaciones
  POST y GET terminaron correctamente a través de Nginx.
- **Impacto:** el backend no puede abrir conexiones ni leer/escribir registros.

## R-03 - Destino del proxy Nginx

- **Síntoma observado:** la configuración original tenía un destino de upstream que no identifica
  al servicio backend.
- **Evidencia:** `frontend/nginx.conf` apuntaba a `http://localhost:8000/`. La prueba final registra
  respuestas HTTP 200 de Nginx para `/api/health` y `/api/items`.
- **Causa raíz:** dentro del contenedor Nginx, `localhost` identifica al propio frontend y no al
  contenedor FastAPI.
- **Elemento modificado:** `frontend/nginx.conf`.
- **Reparación:** apuntar a `http://backend:8000/`; la barra final elimina el prefijo `/api/` y lo
  adapta a las rutas `/health` y `/items` del backend.
- **Justificación:** Compose resuelve `backend` mediante DNS interno y el servicio escucha en 8000.
- **Verificación:** Nginx sirvió la página y el flujo `/api/*` alcanzó FastAPI y PostgreSQL.
- **Impacto:** la interfaz no obtiene estado ni registros aunque los contenedores estén activos.

## R-04 - Puerto publicado del frontend

- **Síntoma observado:** la publicación inicial no coincidía con el puerto de escucha del servidor
  Nginx.
- **Evidencia:** la configuración original publicaba `8080:8080`, mientras `frontend/Dockerfile` y
  `frontend/nginx.conf` indican que Nginx escucha en 80. La salida final de `docker compose ps`
  muestra `0.0.0.0:8080->80/tcp`.
- **Causa raíz:** el puerto del lado del contenedor en `ports` debe ser el puerto interno del servidor.
- **Elemento modificado:** `compose.yaml`.
- **Reparación:** usar `${FRONTEND_PORT:-8080}:80`.
- **Justificación:** mantiene configurable el puerto del host y dirige el tráfico al listener real.
- **Verificación:** `curl http://localhost:8080/` devolvió el HTML y `/api/health` respondió desde el
  mismo puerto.
- **Impacto:** no se puede abrir el frontend desde el host o el puerto reenviado de Codespaces.

## Mejoras de arquitectura incorporadas

- **Persistencia:** volumen nombrado `postgres_data` montado en `/var/lib/postgresql/data`.
- **Configuración:** valores modificables mediante `.env`; `.env.example` documenta los parámetros
  académicos por defecto y `.gitignore` excluye `.env`.
- **Salud:** PostgreSQL utiliza `pg_isready`; backend usa una consulta HTTP a `/health`. `depends_on`
  espera a que `db` y backend estén saludables antes de iniciar los servicios dependientes.
- **Reproducibilidad:** el README documenta inicio, verificación, persistencia, fallo controlado y
  recuperación. `scripts/validate-compose.sh` repite las pruebas y guarda el log.

## Pruebas obligatorias y resultado

La ejecución final se realizó con Docker 28.1.1 y Docker Compose v2.35.1 en Codespaces.

| Prueba | Evidencia observada | Resultado |
|---|---|---|
| Configuración Compose | `docker compose config -q` | Pasa |
| Arranque limpio | `docker compose up --build -d`; servicios creados; DB y backend `healthy` | Pasa |
| Frontend y API | Página HTML servida; `/api/health` informa DB reachable; POST creó `id=2`; GET lo listó | Pasa |
| Persistencia | `id=2` siguió en PostgreSQL después de `docker compose down` y recrear contenedores | Pasa |
| Volumen | Existe `catedra-2-cloud-computing_postgres_data` | Pasa |
| Fallo controlado | `docker compose stop backend`; Nginx devolvió HTTP 504 y registró timeout del upstream | Pasa |
| Recuperación | Al iniciar backend hubo un 502 transitorio; la API volvió a HTTP 200 y el healthcheck pasó de `starting` a `healthy` | Pasa |

La recuperación se verifica por la respuesta de la API y por el estado saludable final. El script espera
la transición de Docker a `healthy` para no confundir el periodo de inicio con un fallo del servicio.
