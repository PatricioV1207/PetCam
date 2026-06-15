import os
import subprocess
import time
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

RECORDINGS_DIR = os.getenv("RECORDINGS_DIR", "/opt/petcam/data/recordings")
PLAYBACK_CACHE_DIR = os.getenv("PLAYBACK_CACHE_DIR", "/opt/petcam/data/playback-cache")
PLAYBACK_REMUX_ENABLED = os.getenv("PLAYBACK_REMUX_ENABLED", "true").lower() in ("true", "1", "yes")
LIVE_HLS_URL = os.getenv("LIVE_HLS_URL", "http://localhost:8888/cam/index.m3u8")

app = FastAPI(title="PetCam")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

VALID_EXTENSIONS = {".mp4", ".m4s", ".m4v", ".mov"}


def get_recordings_dir() -> Path:
    d = Path(RECORDINGS_DIR).resolve()
    d.mkdir(parents=True, exist_ok=True)
    return d


def get_playback_cache_dir() -> Path:
    d = Path(PLAYBACK_CACHE_DIR).resolve()
    d.mkdir(parents=True, exist_ok=True)
    return d


def resolve_safe_path(base_dir: Path, relative_path: str) -> Path:
    requested = (base_dir / relative_path).resolve()
    try:
        requested.relative_to(base_dir)
    except ValueError:
        raise HTTPException(status_code=403, detail="Access denied")
    return requested


@app.get("/health")
async def health():
    rec_dir = get_recordings_dir()
    exists = rec_dir.is_dir()
    if exists:
        try:
            disk = os.statvfs(str(rec_dir))
            total = disk.f_frsize * disk.f_blocks
            free = disk.f_frsize * disk.f_bfree
            used = total - free
        except Exception:
            total = used = free = 0
    else:
        total = used = free = 0

    return {
        "status": "ok",
        "timestamp": time.time(),
        "recordings_dir": {
            "path": str(rec_dir),
            "exists": exists,
        },
        "storage": {
            "total_bytes": total,
            "used_bytes": used,
            "free_bytes": free,
            "percent_used": round(used / total * 100, 1) if total else 0,
        },
        "live_hls_url": LIVE_HLS_URL,
        "playback_cache_dir": str(get_playback_cache_dir()),
    }


@app.get("/api/recordings")
async def list_recordings():
    rec_dir = get_recordings_dir()
    if not rec_dir.is_dir():
        return {"recordings": []}

    recordings = []
    for f in rec_dir.rglob("*"):
        if f.suffix.lower() in VALID_EXTENSIONS and f.is_file():
            rel = str(f.relative_to(rec_dir))
            st = f.stat()
            recordings.append({
                "filename": f.name,
                "relative_path": rel,
                "size_bytes": st.st_size,
                "modified_time": st.st_mtime,
                "play_url": f"/api/recordings/file/{rel}",
                "playable_url": f"/api/recordings/playable/{rel}",
            })

    recordings.sort(key=lambda r: r["modified_time"], reverse=True)
    return {"recordings": recordings}


@app.get("/api/recordings/file/{relative_path:path}")
async def serve_recording(relative_path: str):
    rec_dir = get_recordings_dir()
    requested = resolve_safe_path(rec_dir, relative_path)

    if not requested.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(requested)


@app.get("/api/recordings/playable/{relative_path:path}")
async def serve_playable_recording(relative_path: str):
    rec_dir = get_recordings_dir()
    original = resolve_safe_path(rec_dir, relative_path)

    if not original.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    if not PLAYBACK_REMUX_ENABLED:
        return FileResponse(original)

    cache_dir = get_playback_cache_dir()
    cache_file = cache_dir / relative_path

    if cache_file.is_file() and original.stat().st_mtime <= cache_file.stat().st_mtime:
        return FileResponse(cache_file, media_type="video/mp4")

    cache_file.parent.mkdir(parents=True, exist_ok=True)

    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(original),
             "-c", "copy", "-movflags", "+faststart",
             str(cache_file)],
            capture_output=True,
            timeout=120,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"Remux failed: {e.stderr.decode(errors='replace')}")
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Remux timed out")

    return FileResponse(cache_file, media_type="video/mp4")


static_dir = Path(__file__).parent / "static"
if static_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="static")
