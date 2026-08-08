"""
Shared Meta Marketing API helpers for the meta-ad-builder skill.

Distilled from the Ad Builder Agent deploy scripts: image/video upload,
video-processing polling, and ad creation with transient-error retry/backoff.

Credentials come from environment (load a .env first with python-dotenv):
  META_ACCESS_TOKEN   (required) — long-lived user/system token, ads_management scope
  META_AD_ACCOUNT_ID  (required) — with or without the act_ prefix
  META_API_VERSION    (optional) — Graph API version, default v23.0

**Error contract.** `upload_image`, `upload_video`, `wait_for_video_processing`
and `create_ad` each return a `(value, error)` tuple. On success `error` is
None; on failure `value` is None and `error` is the normalized dict from
`normalize_error()` below. Callers must not treat a None value as "skip and
carry on" — deploy-ad.py records the error and exits non-zero. Printing the
error and returning a bare None (the pre-2026-08-03 contract) is what made a
rejected ad look like a clean run.
"""

import base64
import json
import os
import time
from pathlib import Path

import requests

API_VERSION = os.getenv("META_API_VERSION", "v23.0")
BASE_URL = f"https://graph.facebook.com/{API_VERSION}"


def get_access_token():
    token = os.getenv("META_ACCESS_TOKEN")
    if not token:
        raise RuntimeError("META_ACCESS_TOKEN not set — see check-meta-env.sh")
    return token


def get_ad_account_id():
    acct = os.getenv("META_AD_ACCOUNT_ID")
    if not acct:
        raise RuntimeError("META_AD_ACCOUNT_ID not set — see check-meta-env.sh")
    return acct if acct.startswith("act_") else f"act_{acct}"


def normalize_error(stage, error=None, http_status=None, message=None):
    """Flatten a Meta error object into the shape results JSON persists.

    `error` is Meta's `error` dict when the API returned one; `message` covers
    local failures (missing file, timeout) that never reached the API. Both the
    code and the subcode are kept verbatim — subcodes are what actually
    identify a failure (1885183 = app in development mode, 1870227 = missing
    targeting_automation, 1487713 = video not processed).
    """
    err = error or {}
    return {
        "stage": stage,
        "http_status": http_status,
        "code": err.get("code"),
        "error_subcode": err.get("error_subcode"),
        "type": err.get("type"),
        "message": err.get("message") or message or "unknown error",
        "error_user_title": err.get("error_user_title"),
        "error_user_msg": err.get("error_user_msg"),
        "fbtrace_id": err.get("fbtrace_id"),
    }


def format_error(err):
    """One-line human rendering of a normalized error, for stdout."""
    bits = []
    if err.get("code") is not None:
        bits.append(f"code {err['code']}")
    if err.get("error_subcode") is not None:
        bits.append(f"subcode {err['error_subcode']}")
    if err.get("type"):
        bits.append(err["type"])
    prefix = f"[{', '.join(bits)}] " if bits else ""
    line = f"{prefix}{err.get('message')}"
    if err.get("error_user_msg"):
        line += f" — {err['error_user_msg']}"
    return line


def resolve_output_dir(run_slug):
    """Resolve a per-run output directory.

    Honors OUTPUT_BASE (set by the gen-ai-core workspace); otherwise writes
    under ./outputs/meta-ads/ — both are gitignored, so account-specific ad
    IDs and pulled performance data never land in version control.
    """
    base = os.getenv("OUTPUT_BASE")
    root = Path(base) if base else Path("outputs/meta-ads")
    run_dir = root / run_slug
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def upload_image(path, name=None):
    """Upload an image to /adimages (base64). Returns (image_hash, error)."""
    path = Path(path)
    if not path.exists():
        err = normalize_error("upload_image", message=f"image not found: {path}")
        print(f"  ERROR: {format_error(err)}")
        return None, err
    with open(path, "rb") as f:
        img_b64 = base64.b64encode(f.read()).decode("utf-8")
    url = f"{BASE_URL}/{get_ad_account_id()}/adimages"
    resp = requests.post(
        url,
        data={
            "access_token": get_access_token(),
            "bytes": img_b64,
            "name": (name or path.stem)[:90],
        },
        timeout=120,
    )
    data = resp.json()
    if "images" in data:
        h = list(data["images"].values())[0].get("hash")
        print(f"  Uploaded image. hash={h}")
        return h, None
    err = normalize_error("upload_image", error=data.get("error"),
                          http_status=resp.status_code,
                          message=f"unexpected /adimages response: {json.dumps(data)[:300]}")
    print(f"  ERROR uploading image: {format_error(err)}")
    return None, err


def upload_video(path):
    """Upload a video to /advideos (multipart). Returns (video_id, error)."""
    path = Path(path)
    if not path.exists():
        err = normalize_error("upload_video", message=f"video not found: {path}")
        print(f"  ERROR: {format_error(err)}")
        return None, err
    size_mb = path.stat().st_size / (1024 * 1024)
    print(f"  Uploading {path.name} ({size_mb:.1f} MB)...")
    url = f"{BASE_URL}/{get_ad_account_id()}/advideos"
    with open(path, "rb") as f:
        files = {"source": (path.name, f, "video/mp4")}
        data = {"access_token": get_access_token(), "name": path.name}
        resp = requests.post(url, data=data, files=files, timeout=900)
    try:
        result = resp.json()
    except ValueError:
        result = {}
    if "error" in result or resp.status_code != 200:
        err = normalize_error("upload_video", error=result.get("error"),
                              http_status=resp.status_code,
                              message=f"HTTP {resp.status_code}: {resp.text[:300]}")
        print(f"  ERROR uploading video: {format_error(err)}")
        return None, err
    vid = result.get("id")
    if not vid:
        err = normalize_error("upload_video", http_status=resp.status_code,
                              message=f"/advideos returned no id: {json.dumps(result)[:300]}")
        print(f"  ERROR uploading video: {format_error(err)}")
        return None, err
    print(f"  Video uploaded: {vid}")
    return vid, None


def wait_for_video_processing(video_id, max_wait=360):
    """Poll a video until processing completes. Returns (thumbnail_url, error).

    Meta rejects video-ad creation until the video is fully processed; the
    returned thumbnail is required by video_data.image_url. Both
    `processing_phase.status == complete` AND `video_status == ready` must
    hold — phase alone is not sufficient (cheatsheet §12.23).

    A timeout is not fatal on its own: the fallback `picture` is returned with
    a non-None error so the caller can decide. deploy-ad.py proceeds with the
    fallback thumbnail and lets `create_ad` be the authority on whether the
    video was really usable.
    """
    print("  Waiting for video processing...")
    url = f"{BASE_URL}/{video_id}"
    for attempt in range(max_wait // 10):
        time.sleep(10)
        resp = requests.get(url, params={
            "access_token": get_access_token(),
            "fields": "status,picture,thumbnails{uri,is_preferred}",
        })
        data = resp.json()
        if "error" in data:
            print(f"    Poll error: {data['error'].get('message', '?')}")
            continue
        status = data.get("status", {})
        phase = status.get("processing_phase", {}).get("status", "unknown")
        video_status = status.get("video_status", "unknown")
        elapsed = (attempt + 1) * 10
        print(f"    {elapsed}s: phase={phase}, video_status={video_status}")
        if phase == "complete" and video_status == "ready":
            thumbs = data.get("thumbnails", {}).get("data", [])
            preferred = next((t for t in thumbs if t.get("is_preferred")), None)
            return (preferred or {}).get("uri") or data.get("picture"), None
    err = normalize_error(
        "wait_for_video_processing",
        message=f"video {video_id} did not reach video_status=ready within {max_wait}s",
    )
    print(f"  WARNING: {format_error(err)}. Falling back to picture.")
    resp = requests.get(url, params={"access_token": get_access_token(), "fields": "picture"})
    return resp.json().get("picture"), err


def create_ad(adset_id, ad_name, creative, status="PAUSED", pixel_id=None):
    """Create an ad in an ad set. Returns (ad_id, error).

    Retries transient OAuthException errors. status defaults to PAUSED — the
    skill never launches spending ads automatically. The user reviews and
    un-pauses in Ads Manager.
    """
    url = f"{BASE_URL}/{get_ad_account_id()}/ads"
    payload = {
        "access_token": get_access_token(),
        "adset_id": adset_id,
        "name": ad_name,
        "status": status,
        "creative": json.dumps(creative),
    }
    if pixel_id:
        payload["tracking_specs"] = json.dumps([{
            "action.type": ["offsite_conversion"],
            "fb_pixel": [pixel_id],
        }])

    last_err = None
    for attempt in range(1, 5):
        resp = requests.post(url, data=payload)
        try:
            data = resp.json()
        except ValueError:
            data = {}
        if "error" not in data and data.get("id"):
            ad_id = data["id"]
            print(f"  Created ad: {ad_id} ({ad_name}) [status={status}]")
            return ad_id, None
        last_err = normalize_error(
            "create_ad", error=data.get("error"), http_status=resp.status_code,
            message=f"HTTP {resp.status_code} with no ad id: {resp.text[:300]}",
        )
        raw = data.get("error") or {}
        if raw.get("is_transient") and attempt < 4:
            backoff = min(60, 5 * (2 ** (attempt - 1)))
            print(f"  Transient error (code {raw.get('code')}). Retry {attempt}/4 in {backoff}s.")
            time.sleep(backoff)
            continue
        print(f"  ERROR creating ad: {format_error(last_err)}")
        if last_err.get("error_subcode") == 1885183:
            print("  → The Meta app is in DEVELOPMENT mode. Publish it (App Dashboard →")
            print("    toggle to Live). Allowlisting the ad account under App settings →")
            print("    Advanced → Authorized ad account IDs does NOT work around this.")
        return None, last_err
    print(f"  ERROR creating ad: {format_error(last_err)}")
    return None, last_err
