# One Dockerfile for both apps:  docker build --build-arg APP=app1 -t app1 apps/
# Multi-stage: build wheels with compilers, ship only the runtime.

FROM python:3.12-slim AS build
# google-cloud-profiler has a C extension -> needs a compiler at build time only
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

FROM python:3.12-slim
ARG APP
ARG VERSION=dev
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    SERVICE_NAME=${APP} \
    SERVICE_VERSION=${VERSION} \
    PORT=8080

COPY --from=build /wheels /wheels
RUN pip install --no-cache-dir /wheels/* && rm -rf /wheels

WORKDIR /srv
COPY common/ ./common/
COPY ${APP}/main.py ./main.py

# Non-root user with a fixed UID (matches runAsUser in the pod securityContext)
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
USER 10001

EXPOSE 8080
# gunicorn: 2 workers x 4 threads; --preload is NOT used so the profiler starts per worker.
# No gunicorn access log: the app writes structured (JSON) access logs itself.
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --timeout 30 main:app"]
