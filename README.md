# ACI606 - Docker Rescue Challenge

Aplicación de tres servicios: frontend Nginx, API FastAPI y PostgreSQL, definida mediante Docker Compose.

## Requisitos

- Docker con Docker Compose v2 (`docker compose`).
- GitHub Codespaces utiliza el dev container de `.devcontainer/devcontainer.json`.

En Codespaces, confirme las herramientas antes de iniciar:

```bash
docker --version
docker compose version
```

## Configuración

Compose incluye valores por defecto para que un Codespace recién creado pueda arrancar con el comando de la evaluación. Para cambiar parámetros, copie `.env.example` a `.env` y edite sus valores. `.env` está excluido de Git.

Los valores de ejemplo son solo para desarrollo académico; no sirven como credenciales de producción.

## Iniciar y verificar

Desde la raíz del repositorio:

```bash
docker compose up --build -d
docker compose ps
docker compose config
docker compose logs --tail=100
```

Los servicios `db` y `backend` deben mostrar estado `healthy`; el frontend publica el puerto indicado por `FRONTEND_PORT` (por defecto, 8080). En Codespaces, abra el puerto reenviado 8080 desde la pestaña **Ports**.

La interfaz web permite consultar y crear registros. También se puede verificar la API a través del proxy de Nginx:

```bash
curl http://localhost:8080/api/health
curl -X POST http://localhost:8080/api/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"registro de prueba"}'
curl http://localhost:8080/api/items
```

Si el puerto cambia en `.env`, reemplace `8080` en los comandos por el valor de `FRONTEND_PORT`.

## Validación completa

Para repetir las pruebas de comunicación, persistencia, fallo controlado y recuperación en Codespaces:

```bash
bash scripts/validate-compose.sh
```

El script registra las salidas en `docs/evidence/validation-<fecha>.log`. Al terminar deja los servicios
levantados para poder revisar la aplicación; use `docker compose down` cuando termine la demostración.
Después de capturar la evidencia inicial, se pueden repetir solo las pruebas funcionales con
`SKIP_BASELINE=1 bash scripts/validate-compose.sh`.

## Diagnóstico

```bash
docker compose ps -a
docker compose logs db
docker compose logs backend
docker compose logs frontend
docker compose config
docker network ls
docker volume ls
```

Cada incidencia debe quedar registrada en [`docs/incident-log.md`](docs/incident-log.md) con síntoma, evidencia del Codespace, causa raíz, archivo y cambio aplicado, justificación, verificación e impacto.

## Persistencia

PostgreSQL almacena los datos en el volumen nombrado `postgres_data`. Para recrear contenedores y verificar que los registros sobreviven:

```bash
docker compose down
docker compose up --build -d
curl http://localhost:8080/api/items
```

`docker compose down` conserva el volumen. Para borrar deliberadamente los datos y volver al estado vacío, use `docker compose down -v`.

## Fallo controlado y recuperación

```bash
docker compose stop backend
docker compose ps -a
docker compose logs backend
curl http://localhost:8080/api/health
docker compose start backend
docker compose ps
curl http://localhost:8080/api/health
```

Al detener el backend, Nginx deja de obtener respuestas de la API. La interfaz y los endpoints `/api/*` vuelven a funcionar cuando el backend recupera su estado `healthy`.

## Detener y recrear

```bash
docker compose down
docker compose up --build -d
docker compose ps
```

La arquitectura está descrita en [`docs/architecture.mmd`](docs/architecture.mmd). La bitácora técnica y sus evidencias se completan durante la ejecución del diagnóstico en Codespaces.
