FROM python:3.11-slim
RUN pip install --no-cache-dir flask requests beautifulsoup4 lxml
WORKDIR /app
COPY scraper.py .
CMD ["python", "scraper.py"]
