# CoinScan Recognition & Valuation Backend

Production-grade Python FastAPI backend providing:
- Image quality validation (blur, glare, resolution, brightness)
- Multi-sided coin analysis (Front + Reverse + Edge)
- Multimodal Vision AI extraction (Gemini 2.0/1.5 Flash, GPT-4o mini)
- Numista API v3 catalogue verification & attribution
- Multi-signal evidence aggregation & contradiction scoring
- Live metal spot melt & collector valuation
- Multi-currency FX conversion with caching

## Quick Start (Local Development)

### 1. Setup Virtual Environment
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure Environment
```bash
cp .env.example .env
# Edit .env and supply your GEMINI_API_KEY / NUMISTA_API_KEY (optional for mock testing)
```

### 3. Run Server
```bash
uvicorn backend.app.main:app --host 0.0.0.0 --port 8080 --reload
```

### 4. Health Check
```bash
curl http://127.0.0.1:8080/health
```

### 5. API Documentation
Open `http://127.0.0.1:8080/docs` in your browser for the interactive Swagger UI.

### 6. Run Tests
```bash
pytest backend/tests -v
```
