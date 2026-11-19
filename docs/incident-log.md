# Bitácora de diagnóstico y reparaciones

Completar en el Codespace durante el diagnóstico. No registrar una salida que no se haya observado. Guardar la salida relevante de comandos y capturas en `docs/evidence/` si se incorporan al repositorio.

## R-01 - Comando de inicio del backend

- **Síntoma observado:** completar con el estado y mensaje real de `docker compose logs backend`.
- **Evidencia:** el Dockerfile apunta a `app:app`, mientras que el módulo entregado se llama `main.py`. Capturar también la salida de Compose.
- **Causa raíz:** el destino de Uvicorn no coincide con el módulo Python disponible en `/app`.
- **Elemento modificado:** `backend/Dockerfile`.
- **Reparación:** iniciar `main:app`.
- **Justificación:** importa la instancia `app` desde el módulo copiado al contenedor.
- **Verificación:** completar con el backend `healthy` y una respuesta HTTP de `/api/health`.
- **Impacto:** el backend no inicia, por lo que frontend y base de datos no pueden completar el flujo.

## R-02 - URL y driver de PostgreSQL

- **Síntoma observado:** completar con el error real del backend al iniciar o consultar la base.
- **Evidencia:** la URL original usa `localhost` y una contraseña distinta de la declarada en PostgreSQL; `requirements.txt` no incluye el driver.
- **Causa raíz:** dentro del backend, `localhost` apunta al propio contenedor; además, el usuario y la contraseña deben coincidir y SQLAlchemy necesita un DBAPI de PostgreSQL instalado.
- **Elemento modificado:** `compose.yaml` y `backend/requirements.txt`.
- **Reparación:** utilizar el nombre DNS del servicio `db`, externalizar los parámetros y añadir Psycopg 3.
- **Justificación:** Compose resuelve `db` en la red del proyecto y Psycopg implementa el DBAPI PostgreSQL seleccionado por SQLAlchemy.
- **Verificación:** completar con `/api/health` indicando que la base está reachable y con una operación CRUD.
- **Impacto:** el backend no puede iniciar la tabla ni leer o escribir registros.

## R-03 - Proxy de Nginx al backend

- **Síntoma observado:** completar con la respuesta real obtenida desde la interfaz o `/api/health` antes de la corrección.
- **Evidencia:** `frontend/nginx.conf` reenvía a `localhost:8000`.
- **Causa raíz:** dentro del contenedor Nginx, `localhost` identifica al frontend, no al servicio backend.
- **Elemento modificado:** `frontend/nginx.conf`.
- **Reparación:** reenviar a `backend:8000`.
- **Justificación:** Compose provee DNS interno usando el nombre del servicio y el puerto de escucha interno.
- **Verificación:** completar con la respuesta de `/api/health` y la carga de registros desde la interfaz.
- **Impacto:** el frontend no alcanza la API aunque ambos contenedores estén ejecutándose.

## R-04 - Puerto publicado del frontend

- **Síntoma observado:** completar con el resultado real al abrir el puerto reenviado del Codespace.
- **Evidencia:** Compose publicaba `8080:8080`, mientras que el Nginx incluido escucha en el puerto 80.
- **Causa raíz:** el puerto de destino de Compose no coincide con el puerto interno de Nginx.
- **Elemento modificado:** `compose.yaml`.
- **Reparación:** publicar el puerto configurable del host hacia el puerto 80 del contenedor.
- **Justificación:** el lado derecho del mapeo debe corresponder al puerto donde Nginx escucha dentro del contenedor.
- **Verificación:** completar con la página cargada desde el puerto reenviado.
- **Impacto:** no se puede acceder al frontend desde el host o Codespaces.

## Mejoras de arquitectura obligatorias

Registrar evidencia posterior de cada elemento: volumen nombrado `postgres_data`, variables configurables, healthchecks funcionales y procedimiento reproducible del README. También documentar las pruebas de persistencia, detención de un servicio y recuperación.
