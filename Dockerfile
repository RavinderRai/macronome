FROM python:3.11-slim

# Install system dependencies (including OpenCV/ultralytics requirements)
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install uv for dependency management
RUN pip install uv

# Set working directory
WORKDIR /app

# Copy dependency files first (for better Docker layer caching)
COPY pyproject.toml uv.lock ./

# Copy source code (needed for uv to read pyproject.toml properly)
COPY src/ ./src/
COPY main.py ./

# Install dependencies using uv
# This installs the package and all dependencies from pyproject.toml
RUN uv pip install --system .

# Set Python path
ENV PYTHONPATH=/app/src

# Create non-root user for security (fixes Celery warning)
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose FastAPI port (Celery doesn't need exposed port)
EXPOSE 8000

# Default command (can be overridden in docker-compose)
CMD ["python", "-m", "macronome.backend.app"]

