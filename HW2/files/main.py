from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from datetime import datetime, timezone, timedelta
import httpx, logging, socket, os

CLICKHOUSE = os.getenv("CLICKHOUSE_URL", "http://localhost:8123")
TZ = timezone(timedelta(hours=3))
HOST = socket.gethostname()

logging.basicConfig(level=logging.INFO, format=f"%(asctime)s [{HOST}] %(message)s")
log = logging.getLogger(__name__)
app = FastAPI()


class LogEntry(BaseModel):
    level: str = "INFO"
    message: str
    source: str = "unknown"
    timestamp: str = None


class LogBatch(BaseModel):
    logs: list[LogEntry]


def esc(s):
    return s.replace("'", "''")


def now():
    return datetime.now(TZ).strftime("%Y-%m-%d %H:%M:%S")


@app.get("/")
def index():
    return {"status": "ok", "host": HOST}


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.post("/write_log")
async def write_log(entry: LogEntry, req: Request):
    ip = req.headers.get("X-Real-IP", req.client.host)
    ts = entry.timestamp or now()
    q = f"INSERT INTO default.logs VALUES ('{ts}', '{esc(entry.level)}', '{esc(entry.message)}', '{esc(entry.source)}')"

    async with httpx.AsyncClient() as c:
        r = await c.post(CLICKHOUSE, content=q)
        if r.status_code != 200:
            raise HTTPException(500, r.text)

    log.info(f"[{ip}] {entry.level}: {entry.message[:50]}")
    return {"status": "ok", "host": HOST}


@app.post("/write_logs")
async def write_logs(batch: LogBatch, req: Request):
    ip = req.headers.get("X-Real-IP", req.client.host)
    vals = [
        f"('{e.timestamp or now()}', '{esc(e.level)}', '{esc(e.message)}', '{esc(e.source)}')"
        for e in batch.logs
    ]

    async with httpx.AsyncClient() as c:
        r = await c.post(
            CLICKHOUSE, content=f"INSERT INTO default.logs VALUES {','.join(vals)}"
        )
        if r.status_code != 200:
            raise HTTPException(500, r.text)

    log.info(f"[{ip}] Saved {len(batch.logs)} logs")
    return {"status": "ok", "count": len(batch.logs), "host": HOST}


@app.get("/logs")
async def get_logs(limit: int = 100):
    async with httpx.AsyncClient() as c:
        r = await c.get(
            CLICKHOUSE,
            params={
                "query": f"SELECT * FROM default.logs ORDER BY timestamp DESC LIMIT {limit} FORMAT JSON"
            },
        )
        if r.status_code != 200:
            raise HTTPException(500, r.text)
        return r.json()
