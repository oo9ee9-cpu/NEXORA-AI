import os
import re
import sqlite3
from pathlib import Path
from typing import Optional

import httpx
from cryptography.fernet import Fernet, InvalidToken
from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.getenv("NEXORA_DB_PATH", str(ROOT / "nexora.db")))
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "")
MASTER_KEY = os.getenv("NEXORA_MASTER_KEY", "")

app = FastAPI(title="NEXORA AI API", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH"],
    allow_headers=["Content-Type", "X-Admin-Password"],
)

def db():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con

def cipher():
    if not MASTER_KEY:
        raise HTTPException(503, "NEXORA_MASTER_KEY is not configured on the server")
    try:
        return Fernet(MASTER_KEY.encode())
    except Exception as exc:
        raise HTTPException(500, "NEXORA_MASTER_KEY must be a valid Fernet key") from exc

def init_db():
    with db() as con:
        con.executescript("""
        CREATE TABLE IF NOT EXISTS cells (
          id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL,
          name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          instructions TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS providers (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          base_url TEXT NOT NULL, model TEXT NOT NULL, encrypted_key TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1, priority INTEGER NOT NULL DEFAULT 100
        );
        CREATE TABLE IF NOT EXISTS knowledge (
          id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
          content TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'manual'
        );
        CREATE TABLE IF NOT EXISTS audit (
          id INTEGER PRIMARY KEY AUTOINCREMENT, event TEXT NOT NULL,
          detail TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        count = con.execute("SELECT COUNT(*) FROM cells").fetchone()[0]
        if count == 0:
            con.executemany(
                "INSERT INTO cells(number,name,description,instructions,enabled) VALUES(?,?,?,?,1)",
                [
                    ("01", "خلية المحادثة", "تنسيق الحوار والردود", "أجب بوضوح وباللغة التي يستخدمها المستخدم."),
                    ("02", "خلية المعرفة", "البحث في المعرفة الداخلية", "قدّم المعرفة الداخلية قبل استدعاء أي نموذج."),
                    ("03", "خلية البحث", "تجهيز البحث الخارجي", "تحقق من المصادر عند تفعيل موفر بحث."),
                    ("04", "خلية المطوّر", "مساعدة تطوير البرمجيات", "حلل المتطلبات واكتب تغييرات آمنة قابلة للاختبار."),
                ],
            )

init_db()

def require_admin(password: Optional[str]):
    if not ADMIN_PASSWORD:
        raise HTTPException(503, "ADMIN_PASSWORD is not configured on the server")
    if password != ADMIN_PASSWORD:
        raise HTTPException(401, "Admin password is missing or incorrect")

def audit(event: str, detail: str = ""):
    with db() as con:
        con.execute("INSERT INTO audit(event,detail) VALUES(?,?)", (event, detail[:500]))

class ProviderIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    base_url: str = Field(min_length=8, max_length=500)
    model: str = Field(min_length=1, max_length=200)
    api_key: str = Field(min_length=1, max_length=4000)
    enabled: bool = True
    priority: int = 100

class KnowledgeIn(BaseModel):
    title: str = Field(min_length=1, max_length=250)
    content: str = Field(min_length=1, max_length=200000)

class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=12000)

@app.get("/health")
def health():
    with db() as con:
        return {
            "ok": True,
            "service": "NEXORA AI API",
            "version": "0.2.0",
            "cells": con.execute("SELECT COUNT(*) FROM cells").fetchone()[0],
            "providers_enabled": con.execute("SELECT COUNT(*) FROM providers WHERE enabled=1").fetchone()[0],
            "knowledge_items": con.execute("SELECT COUNT(*) FROM knowledge").fetchone()[0],
        }

@app.get("/api/cells")
def list_cells():
    with db() as con:
        rows = con.execute("SELECT * FROM cells ORDER BY number").fetchall()
        return {"cells": [dict(r) | {"enabled": bool(r["enabled"])} for r in rows]}

@app.patch("/api/cells/{cell_id}")
def update_cell(cell_id: int, body: dict, x_admin_password: Optional[str] = Header(default=None)):
    require_admin(x_admin_password)
    allowed = {"enabled", "name", "description", "instructions"}
    updates = {k: v for k, v in body.items() if k in allowed}
    if not updates:
        raise HTTPException(400, "No supported fields supplied")
    if "enabled" in updates:
        updates["enabled"] = int(bool(updates["enabled"]))
    sql = ", ".join(f"{k}=?" for k in updates)
    with db() as con:
        cur = con.execute(f"UPDATE cells SET {sql} WHERE id=?", (*updates.values(), cell_id))
        if cur.rowcount == 0:
            raise HTTPException(404, "Cell not found")
    audit("cell_updated", str(cell_id))
    return {"ok": True}

@app.get("/api/admin/providers")
def list_providers(x_admin_password: Optional[str] = Header(default=None)):
    require_admin(x_admin_password)
    with db() as con:
        rows = con.execute("SELECT id,name,base_url,model,enabled,priority,encrypted_key FROM providers ORDER BY priority,id").fetchall()
        return {"providers": [
            {"id": r["id"], "name": r["name"], "base_url": r["base_url"],
             "model": r["model"], "enabled": bool(r["enabled"]),
             "priority": r["priority"], "key_configured": bool(r["encrypted_key"])}
            for r in rows
        ]}

@app.post("/api/admin/providers")
def add_provider(body: ProviderIn, x_admin_password: Optional[str] = Header(default=None)):
    require_admin(x_admin_password)
    encrypted = cipher().encrypt(body.api_key.encode()).decode()
    with db() as con:
        cur = con.execute(
            "INSERT INTO providers(name,base_url,model,encrypted_key,enabled,priority) VALUES(?,?,?,?,?,?)",
            (body.name, body.base_url.rstrip("/"), body.model, encrypted, int(body.enabled), body.priority),
        )
        provider_id = cur.lastrowid
    audit("provider_added", body.name)
    return {"ok": True, "id": provider_id}

@app.patch("/api/admin/providers/{provider_id}")
def toggle_provider(provider_id: int, body: dict, x_admin_password: Optional[str] = Header(default=None)):
    require_admin(x_admin_password)
    if "enabled" not in body:
        raise HTTPException(400, "enabled field required")
    with db() as con:
        cur = con.execute("UPDATE providers SET enabled=? WHERE id=?", (int(bool(body["enabled"])), provider_id))
        if not cur.rowcount:
            raise HTTPException(404, "Provider not found")
    audit("provider_toggled", str(provider_id))
    return {"ok": True}

@app.post("/api/admin/knowledge")
def add_knowledge(body: KnowledgeIn, x_admin_password: Optional[str] = Header(default=None)):
    require_admin(x_admin_password)
    with db() as con:
        cur = con.execute("INSERT INTO knowledge(title,content,source) VALUES(?,?,?)",
                          (body.title, body.content, "manual"))
        item_id = cur.lastrowid
    audit("knowledge_added", body.title)
    return {"ok": True, "id": item_id}

@app.post("/api/admin/knowledge/upload")
async def upload_knowledge(file: UploadFile = File(...), x_admin_password: Optional[str] = Header(default=None)):
    require_admin(x_admin_password)
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(415, "Only PDF files are accepted")
    raw = await file.read()
    if len(raw) > 15 * 1024 * 1024:
        raise HTTPException(413, "PDF exceeds 15 MB")
    try:
        from io import BytesIO
        reader = PdfReader(BytesIO(raw))
        text = "\n".join(page.extract_text() or "" for page in reader.pages)
    except Exception as exc:
        raise HTTPException(422, "Unable to extract text from this PDF") from exc
    if not text.strip():
        raise HTTPException(422, "No selectable text found in PDF")
    with db() as con:
        cur = con.execute("INSERT INTO knowledge(title,content,source) VALUES(?,?,?)",
                          (file.filename, text[:200000], "pdf"))
        item_id = cur.lastrowid
    audit("pdf_uploaded", file.filename)
    return {"ok": True, "id": item_id, "characters": len(text)}

def find_knowledge(question: str):
    words = {w for w in re.findall(r"[\w\u0600-\u06FF]+", question.lower()) if len(w) > 2}
    if not words:
        return None
    with db() as con:
        rows = con.execute("SELECT title,content FROM knowledge").fetchall()
    scored = []
    for row in rows:
        text = (row["title"] + " " + row["content"]).lower()
        hits = sum(1 for w in words if w in text)
        score = hits / max(1, len(words))
        if score >= 0.45:
            scored.append((score, row["title"], row["content"]))
    if not scored:
        return None
    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[0][1], scored[0][2]

async def ask_provider(question: str):
    with db() as con:
        rows = con.execute("SELECT * FROM providers WHERE enabled=1 ORDER BY priority,id").fetchall()
    errors = []
    for row in rows:
        try:
            key = cipher().decrypt(row["encrypted_key"].encode()).decode()
            url = row["base_url"].rstrip("/")
            if not url.endswith("/chat/completions"):
                url += "/chat/completions"
            async with httpx.AsyncClient(timeout=50) as client:
                response = await client.post(
                    url,
                    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                    json={"model": row["model"], "messages": [
                        {"role": "system", "content": "You are NEXORA AI. Answer helpfully, honestly, and in the user's language."},
                        {"role": "user", "content": question},
                    ]},
                )
            response.raise_for_status()
            data = response.json()
            answer = data["choices"][0]["message"]["content"]
            audit("chat_provider", row["name"])
            return answer, row["name"]
        except (httpx.HTTPError, KeyError, IndexError, ValueError, InvalidToken) as exc:
            errors.append(f"{row['name']}: {type(exc).__name__}")
    if errors:
        raise HTTPException(502, "All configured AI providers failed: " + "; ".join(errors))
    raise HTTPException(503, "No enabled AI provider. Add an OpenAI-compatible provider in the admin panel.")

@app.post("/api/chat")
async def chat(body: ChatIn):
    local = find_knowledge(body.message)
    if local:
        title, content = local
        answer = f"وجدت المعلومة في قاعدة المعرفة الداخلية ({title}):\n\n{content[:7000]}"
        audit("chat_knowledge_hit", title)
        return {"answer": answer, "source": "internal_knowledge", "provider": None}
    answer, provider = await ask_provider(body.message)
    return {"answer": answer, "source": "provider", "provider": provider}

@app.get("/api/admin/audit")
def get_audit(x_admin_password: Optional[str] = Header(default=None)):
    require_admin(x_admin_password)
    with db() as con:
        rows = con.execute("SELECT * FROM audit ORDER BY id DESC LIMIT 100").fetchall()
        return {"events": [dict(r) for r in rows]}
