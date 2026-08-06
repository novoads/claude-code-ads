#!/usr/bin/env python3
"""
Generate one or more standalone Meta ad creatives via Novoads' POST /v1/images
with Nano Banana Pro (nano-banana-pro).

Brand contract: this script REFUSES to use any model other than `nano-banana-pro`.
The sibling `chatgpt-image-ad/scripts/generate_image.py` handles ChatGPT Image 2.

There is one Nano Banana model on this API. The older nano-banana-2, nano-banana-edit
and legacy nano-banana variants do not exist here, so there is no variant to choose
and no inpainting mode to route to.

Novoads generates images synchronously — the POST blocks for the render (typically
60-90 seconds) and returns the finished images. There is nothing to poll.

Output contract:
  stdout: one JSON object per generated image, one per line
          {"variant": int, "path": str, "job_id": str,
           "width": int, "height": int, "prompt": str,
           "aspect_ratio": str, "model": str, "credits_charged": float}
  stderr: human-readable progress + errors
  exit:   0 on success; 1 if the generation failed; 2 on bad args.

Stdlib only. No requests, no python-dotenv.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE_URL_DEFAULT = "https://api.novoads.ai"  # host only; this script appends /v1/...
# Nano Banana Pro's aspect-ratio grid — the full set. It accepts four ratios
# gpt-image-2 does not: 3:2, 3:4, 4:3, 5:4.
ALLOWED_RATIOS = {"1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"}
LOCKED_MODEL = "nano-banana-pro"
# referenceAssetIds maxItems for nano-banana-pro — the caps are PER MODEL (gpt-image-2: 4,
# reve-2.1: 8). Verified against spec 2.7.0 on 2026-08-04 — re-check: ./scripts/verify-image-caps.sh
MAX_REFS = 14
MAX_IMAGES = 4  # numImages enum: 1, 2, 3, 4
MAX_PROMPT_CHARS = 4000  # nano-banana-pro prompt ceiling; the API 400s above it
MIN_DIMENSION = 1024
# The render happens inside the POST, typically 60-90s. Leave generous headroom.
GENERATE_TIMEOUT_S = 300

NO_CHROME_SUFFIX = (
    "\n\n[NO PLATFORM CHROME] Render only the standalone ad creative (the static image uploaded to Meta), "
    "not a screenshot of how it displays in-feed. Exclude: iOS device chrome (status bar, home indicator); "
    "platform brand-row above the ad (avatar + handle + Sponsored / Saved label); post body / caption text; "
    "link-card footer (URL + headline + button); engagement rows (likes / comments / shares counts, "
    "Followed-by, View comments); action buttons (Like / Comment / Share / Save); comment input boxes; "
    "platform tab/nav bars (Instagram, Facebook, Twitter); Story chrome (progress bars, story header, "
    "swipe-up arrows). Just the standalone image."
)

SAFE_ZONE_SUFFIX = (
    "\n\n[EDGE-SAFE] All text, headlines, CTAs, table headers, sign/board content, product wordmarks, and "
    "key focal subjects must fit within the central 84% of the canvas (~8% padding from every edge). "
    "Backgrounds and divider lines may bleed; text and focal elements may NOT touch or extend off any edge. "
    "If a tall focal subject doesn't fit at the requested aspect ratio, scale it DOWN — never crop a "
    "headline, never let text run off-frame, never cut off the top/bottom of a sign, board, or product."
)

GLYPH_SAFETY_SUFFIX = (
    "\n\n[TEXT FIDELITY] Inside body-text blocks (chat bubbles, message threads, comment text, ChatGPT "
    "responses, dense paragraphs): plain words only — NO emoji, NO unicode glyphs, NO special characters "
    "mid-sentence. Emoji OK in headlines and short large-text positions where the prompt explicitly calls "
    "for them. Render the EXACT count of conversation elements the prompt specifies — do not invent "
    "additional comments, messages, replies, or responses."
)

# Novoads POST /v1/uploads accepts exactly these image types. GIF is not among them.
MEDIA_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
}


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def load_env(env_path: Path) -> dict:
    """Parse a .env file into a dict. No external deps."""
    if not env_path.exists():
        raise SystemExit(f"error: .env not found at {env_path}")
    out: dict[str, str] = {}
    for raw in env_path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def auth_header(env: dict) -> str:
    """Build the Authorization header value. Novoads uses Bearer auth."""
    key = env.get("NOVOADS_API_KEY") or os.environ.get("NOVOADS_API_KEY")
    if not key:
        raise SystemExit(
            "error: NOVOADS_API_KEY not set in .env (or shell environment). "
            "Run ./scripts/setup.sh, or create a key at "
            "https://novoads.ai/dashboard/settings?tab=api"
        )
    return f"Bearer {key}"


def slugify(text: str, max_len: int = 40) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:max_len] or "image"


def _api_error(e: urllib.error.HTTPError, url: str) -> RuntimeError:
    """Turn a Novoads error envelope into a message worth reading."""
    raw = e.read().decode("utf-8", errors="replace")
    try:
        err = json.loads(raw).get("error", {})
    except json.JSONDecodeError:
        # Not our envelope at all -> it never reached the application. The one
        # that bites: Cloudflare's bot rule refusing the default urllib UA.
        if "1010" in raw:
            return RuntimeError(
                f"HTTP {e.code} on {url}: Cloudflare error 1010 — the edge refused "
                f"this client, NOT your API key. This is a User-Agent problem: "
                f"send a non-default one (see USER_AGENT above) or use curl. Do not "
                f"regenerate the key or check the subscription."
            )
        return RuntimeError(f"HTTP {e.code} on {url}: {raw}")
    code = err.get("code", "?")
    msg = err.get("message", raw)
    details = err.get("details")
    hint = ""
    if isinstance(details, dict):
        reason = details.get("reason")
        if reason:
            hint = f" (reason: {reason}"
            if details.get("retryAfterSeconds"):
                hint += f", retry after {details['retryAfterSeconds']}s"
            hint += ")"
        elif details.get("issues"):
            hint = f" (issues: {json.dumps(details['issues'])[:300]})"
    return RuntimeError(f"HTTP {e.code} {code} on {url}: {msg}{hint}")


# api.novoads.ai sits behind Cloudflare, whose bot rule 403s the default
# "Python-urllib/x.y" User-Agent with a bare `error code: 1010` page — no JSON
# envelope, no requestId, and it reads exactly like a revoked key or a lapsed
# plan. Any non-default UA clears it (verified 2026-08-02). The presigned PUT is
# NOT affected: it goes to R2, not to the API zone, and its signed headers are
# sent verbatim on purpose.
USER_AGENT = "novoads-claude-code/1.0"


def http_post_json(url: str, headers: dict, body: dict, timeout: int = 60) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={**headers, "User-Agent": USER_AGENT},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise _api_error(e, url) from e


def http_put_file(upload_url: str, file_path: Path, headers: dict, timeout: int = 300) -> None:
    """PUT raw bytes to a presigned URL, echoing the signed headers byte for byte.

    Both Content-Type and Content-Length are part of the URL's signature — storage
    returns 403 if either differs from what was signed, so we send the server's
    `headers` object verbatim rather than letting urllib infer anything.
    """
    data = file_path.read_bytes()
    req = urllib.request.Request(upload_url, data=data, method="PUT", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status >= 300:
                raise RuntimeError(f"presigned PUT failed: HTTP {resp.status}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:300]
        raise RuntimeError(
            f"presigned PUT failed: HTTP {e.code}. The signed headers must be sent "
            f"exactly as returned by POST /v1/uploads. Response: {body}"
        ) from e


def http_download(url: str, dest: Path, timeout: int = 120) -> None:
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp, dest.open("wb") as out:
        while chunk := resp.read(64 * 1024):
            out.write(chunk)


def probe_dimensions(path: Path) -> tuple[int, int]:
    """Return (width, height) for a PNG/JPEG/WebP using stdlib only — cross-platform.

    Reads the file header bytes directly so we don't need ImageMagick, sips
    (macOS), or Pillow. Returns (0, 0) on any error.
    """
    try:
        with path.open("rb") as f:
            header = f.read(32)
        if len(header) < 24:
            return 0, 0
        # PNG: signature 89 50 4E 47 0D 0A 1A 0A, then IHDR chunk:
        # [4B length][4B "IHDR"][4B width BE][4B height BE]...
        if header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR":
            w = int.from_bytes(header[16:20], "big")
            h = int.from_bytes(header[20:24], "big")
            return w, h
        # JPEG: walk SOF markers to find dimensions. SOFn = 0xFFC0..0xFFCF
        # (excluding 0xFFC4 DHT, 0xFFC8 reserved, 0xFFCC DAC).
        if header[:2] == b"\xff\xd8":
            with path.open("rb") as f:
                data = f.read()
            i = 2
            while i < len(data) - 8:
                if data[i] != 0xFF:
                    i += 1
                    continue
                marker = data[i + 1]
                if marker in (0xD8, 0xD9):  # SOI / EOI
                    i += 2
                    continue
                if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                    h = int.from_bytes(data[i + 5:i + 7], "big")
                    w = int.from_bytes(data[i + 7:i + 9], "big")
                    return w, h
                seg_len = int.from_bytes(data[i + 2:i + 4], "big")
                i += 2 + seg_len
            return 0, 0
        # WebP (VP8/VP8L/VP8X): "RIFF????WEBP"
        if header[:4] == b"RIFF" and header[8:12] == b"WEBP":
            chunk = header[12:16]
            if chunk == b"VP8X" and len(header) >= 30:
                # VP8X: width-1 (3B LE) at offset 24, height-1 at offset 27
                w = int.from_bytes(header[24:27], "little") + 1
                h = int.from_bytes(header[27:30], "little") + 1
                return w, h
            if chunk == b"VP8 ":
                with path.open("rb") as f:
                    data = f.read(40)
                if len(data) >= 30:
                    w = int.from_bytes(data[26:28], "little") & 0x3FFF
                    h = int.from_bytes(data[28:30], "little") & 0x3FFF
                    return w, h
            if chunk == b"VP8L":
                with path.open("rb") as f:
                    data = f.read(25)
                if len(data) >= 25 and data[20] == 0x2F:
                    b0, b1, b2, b3 = data[21], data[22], data[23], data[24]
                    w = ((b1 & 0x3F) << 8 | b0) + 1
                    h = ((b3 & 0x0F) << 10 | b2 << 2 | (b1 >> 6)) + 1
                    return w, h
        return 0, 0
    except Exception as e:  # noqa: BLE001
        log(f"warn: could not probe dimensions for {path}: {e}")
        return 0, 0


def upload_reference(local_path: Path, base_url: str, auth_hdr: str) -> str:
    """Upload a local image via POST /v1/uploads. Returns a durable assetId.

    The assetId keeps working across later calls, so callers should cache it rather
    than re-uploading the same file per variant.
    """
    if not local_path.exists():
        raise SystemExit(f"error: image not found: {local_path}")
    mime = MEDIA_TYPES.get(local_path.suffix.lower())
    if not mime:
        raise SystemExit(
            f"error: unsupported image extension '{local_path.suffix}' for {local_path}. "
            f"Novoads uploads accept: {sorted(MEDIA_TYPES)}"
        )
    size = local_path.stat().st_size
    resp = http_post_json(
        f"{base_url}/v1/uploads",
        {
            "Authorization": auth_hdr,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        {"contentType": mime, "sizeBytes": size},
    )
    asset_id = resp.get("assetId")
    upload_url = resp.get("uploadUrl")
    signed_headers = resp.get("headers") or {}
    if not asset_id or not upload_url:
        raise RuntimeError(f"uploads response missing fields: {resp}")
    max_bytes = resp.get("maxBytes")
    if max_bytes and size > max_bytes:
        raise SystemExit(
            f"error: {local_path.name} is {size} bytes; the upload endpoint caps at {max_bytes}."
        )
    http_put_file(upload_url, local_path, signed_headers)
    return asset_id


def build_prompt(prompt: str, allow_chrome: bool, no_safe_zone: bool) -> str:
    final = prompt
    if not allow_chrome:
        final += NO_CHROME_SUFFIX
    if not no_safe_zone:
        final += SAFE_ZONE_SUFFIX
    final += GLYPH_SAFETY_SUFFIX
    return final


def generate(
    prompt: str,
    aspect_ratio: str,
    num_images: int,
    ref_asset_ids: list[str],
    product_id: str | None,
    base_url: str,
    auth_hdr: str,
) -> dict:
    """One synchronous POST /v1/images. Returns the finished ImageJob."""
    body: dict = {
        "model": LOCKED_MODEL,
        "prompt": prompt,
        "aspectRatio": aspect_ratio,
        "numImages": num_images,
    }
    if ref_asset_ids:
        body["referenceAssetIds"] = ref_asset_ids
    if product_id:
        body["productId"] = product_id

    headers = {
        "Authorization": auth_hdr,
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    return http_post_json(
        f"{base_url}/v1/images", headers, body, timeout=GENERATE_TIMEOUT_S
    )


def main() -> int:
    p = argparse.ArgumentParser(
        description="Generate nano-banana-pro image(s) via Novoads. Brand contract: nano-banana-pro only.",
    )
    p.add_argument("--prompt", required=True, help="Image prompt (post-rewrite).")
    p.add_argument(
        "--aspect-ratio",
        required=True,
        choices=sorted(ALLOWED_RATIOS),
        help="Canvas ratio. The API defaults to 1:1 if omitted, which is rarely the ad you want.",
    )
    p.add_argument(
        "--n",
        type=int,
        default=1,
        help=f"How many images, 1-{MAX_IMAGES}. Sent as numImages in ONE call. Charged per image.",
    )
    p.add_argument(
        "--out",
        type=Path,
        default=Path("./generated"),
        help="Output directory for PNGs.",
    )
    p.add_argument(
        "--image-ref",
        type=Path,
        action="append",
        default=[],
        metavar="PATH",
        help=(
            f"Reference image path (PNG/JPG/WEBP). Repeatable, max {MAX_REFS}. "
            "Uploaded once each; order is preserved and may be addressed positionally "
            "by the prompt."
        ),
    )
    p.add_argument(
        "--model",
        default=LOCKED_MODEL,
        help=f"Locked to {LOCKED_MODEL} by brand contract.",
    )
    p.add_argument(
        "--env-file",
        type=Path,
        default=Path(".env"),
        help="Path to .env (default: ./.env).",
    )
    p.add_argument(
        "--product-id",
        help="Novoads productId (defaults to PRODUCT_ID env / .env). "
             "Organizational only — it does not influence what is generated.",
    )
    p.add_argument(
        "--base-url",
        default=None,
        help=f"Novoads API host, no /v1 (default: {BASE_URL_DEFAULT} or NOVOADS_BASE_URL).",
    )
    p.add_argument(
        "--allow-chrome",
        action="store_true",
        help="Allow platform/screenshot UI in the output. Default is to strip all such UI.",
    )
    p.add_argument(
        "--no-safe-zone",
        action="store_true",
        help="Skip the edge-safe suffix. Use only if you genuinely need text to bleed.",
    )
    args = p.parse_args()

    if args.model != LOCKED_MODEL:
        log(
            f"error: brand contract violation — model must be '{LOCKED_MODEL}', got '{args.model}'. "
            f"This skill is locked to Nano Banana Pro. For ChatGPT Image 2, use the "
            f"chatgpt-image-ad skill instead."
        )
        return 2

    if not (1 <= args.n <= MAX_IMAGES):
        log(f"error: --n must be 1..{MAX_IMAGES} (got {args.n})")
        return 2

    if len(args.image_ref) > MAX_REFS:
        log(
            f"error: too many --image-ref ({len(args.image_ref)}); the cap is {MAX_REFS} "
            f"on {LOCKED_MODEL}"
        )
        return 2

    final_prompt = build_prompt(args.prompt, args.allow_chrome, args.no_safe_zone)
    if len(final_prompt) > MAX_PROMPT_CHARS:
        overflow = len(final_prompt) - MAX_PROMPT_CHARS
        suffix_chars = len(final_prompt) - len(args.prompt)
        log(
            f"error: prompt is {len(final_prompt)} characters after the always-on safety "
            f"suffixes; {LOCKED_MODEL} caps at {MAX_PROMPT_CHARS}. Trim about {overflow} "
            f"characters from --prompt (the suffixes add ~"
            f"{suffix_chars}). Your --prompt must be <= "
            f"{MAX_PROMPT_CHARS - suffix_chars} characters with the current flags."
        )
        return 2

    env = load_env(args.env_file)
    auth_hdr = auth_header(env)
    base_url = (
        args.base_url
        or env.get("NOVOADS_BASE_URL")
        or os.environ.get("NOVOADS_BASE_URL")
        or BASE_URL_DEFAULT
    ).rstrip("/")
    product_id = args.product_id or env.get("PRODUCT_ID") or os.environ.get("PRODUCT_ID")

    args.out.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    slug = slugify(args.prompt)

    chrome_state = "allowed" if args.allow_chrome else "stripped"
    log(
        f"generating {args.n} image(s) model={LOCKED_MODEL} aspect={args.aspect_ratio} "
        f"chrome={chrome_state} refs={len(args.image_ref)} -> {args.out}/"
    )

    ref_asset_ids: list[str] = []
    if args.image_ref:
        log(f"uploading {len(args.image_ref)} reference image(s)…")
        for ref in args.image_ref:
            ref_asset_ids.append(upload_reference(ref, base_url, auth_hdr))

    log(f"submitting (this blocks for the render, typically 60-90s)…")
    try:
        job = generate(
            final_prompt, args.aspect_ratio, args.n, ref_asset_ids,
            product_id, base_url, auth_hdr,
        )
    except Exception as e:  # noqa: BLE001
        log(f"generation FAILED — {e}")
        return 1

    job_id = job.get("jobId", "")
    credits = job.get("creditsCharged")
    images = job.get("images") or []
    if not images:
        log(f"generation returned no images (status={job.get('status')}, jobId={job_id})")
        return 1

    log(f"jobId={job_id} status={job.get('status')} images={len(images)} credits={credits}")

    results: list[dict] = []
    for i, img in enumerate(images, start=1):
        dest = args.out / f"{ts}-{slug}-v{i}.png"
        log(f"image {i}: downloading -> {dest.name}")
        http_download(img["url"], dest)
        w = img.get("width") or 0
        h = img.get("height") or 0
        if not (w and h):
            w, h = probe_dimensions(dest)
        if w and h and (w < MIN_DIMENSION or h < MIN_DIMENSION):
            log(
                f"image {i}: WARNING {w}x{h} is below the {MIN_DIMENSION}x{MIN_DIMENSION} "
                f"floor. Regenerate or upscale."
            )
        results.append({
            "variant": i,
            "path": str(dest),
            "job_id": job_id,
            "width": w,
            "height": h,
            "prompt": args.prompt,
            "aspect_ratio": args.aspect_ratio,
            "model": job.get("model", LOCKED_MODEL),
            "credits_charged": credits,
        })

    for r in results:
        print(json.dumps(r), flush=True)

    log(f"all {len(results)} image(s) succeeded — {credits} credits charged for this call")
    return 0


if __name__ == "__main__":
    sys.exit(main())
