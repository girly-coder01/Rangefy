FROM python:3.11-slim
WORKDIR /app
COPY pyproject.toml requirements.txt ./
RUN pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.txt
COPY . .
RUN pip install --no-cache-dir --no-deps -e .
EXPOSE 8000
CMD ["uvicorn", "src.server.app:app", "--host", "0.0.0.0", "--port", "8000"]
