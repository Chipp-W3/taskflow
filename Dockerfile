# ---- Build stage: install deps into an isolated venv ----
FROM python:3.12-slim-bookworm AS builder

WORKDIR /app

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ---- Runtime stage: minimal image, no build tools, non-root user ----
FROM python:3.12-slim-bookworm AS runtime

RUN groupadd --gid 1000 app \
    && useradd --uid 1000 --gid app --shell /usr/sbin/nologin --no-create-home app

# Base image ships its own pip/setuptools (live install + ensurepip's bundled wheel),
# unused here (app only runs from /opt/venv) and known to carry CVEs
# (GHSA-6v7p-g79w-8964, CVE-2025-47273) — drop them entirely.
RUN rm -rf /usr/local/lib/python3.12/site-packages/pip* \
           /usr/local/lib/python3.12/site-packages/setuptools* \
           /usr/local/lib/python3.12/site-packages/wheel* \
           /usr/local/lib/python3.12/ensurepip \
           /usr/local/bin/pip*

COPY --from=builder /opt/venv /opt/venv

# The venv's own pip (used only to install requirements.txt during build) also
# vendors msgpack/setuptools and is never invoked at runtime — drop it too.
RUN rm -rf /opt/venv/lib/python3.12/site-packages/pip \
           /opt/venv/lib/python3.12/site-packages/pip-*.dist-info \
           /opt/venv/bin/pip*

WORKDIR /app
COPY --chown=app:app main.py .

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
