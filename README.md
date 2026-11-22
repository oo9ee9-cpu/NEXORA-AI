# NEXORA AI

NEXORA AI is an Android Flutter client plus a Python API backend.

## Current implementation

- Arabic Flutter client with chat, cell status controls, provider administration and knowledge entry.
- FastAPI backend with SQLite persistence.
- Internal knowledge lookup is attempted before an AI provider call.
- OpenAI-compatible chat-completions providers with priority fallback.
- Provider API keys are encrypted at rest using Fernet.
- PDF text extraction (selectable-text PDFs; scanned PDFs need OCR, not included yet).
- GitHub Actions workflow builds a release APK artifact.

## Backend deployment

Deploy the `backend/` directory as a persistent Docker service. The service must have persistent storage mounted at `/data`.

Set these environment variables on the hosting service:

- `ADMIN_PASSWORD`: long unique administrator password.
- `NEXORA_MASTER_KEY`: Fernet key generated using `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`.
- `NEXORA_DB_PATH=/data/nexora.db`
- `CORS_ORIGINS=*` (restrict to trusted origins if a web admin is later added).

Run locally with:

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

The Android app's Settings screen requires the public HTTPS backend URL and admin password. Do not put provider keys in the APK.

## Add an AI provider

In the app, open Administration → Add API provider. Enter an OpenAI-compatible base URL (for example a provider URL ending in `/v1`), model ID, and API key. The backend encrypts the key before storing it. The provider must support `POST /chat/completions`.

## Important scope

This is a working first backend/mobile vertical slice, not yet the complete multi-agent platform described in the product brief. Web search, autonomous GitHub code editing, multi-user authentication/roles, OCR, embeddings/vector retrieval, and production deployment still need implementation. The APK build does not provision or host the backend.
