#!/usr/bin/env python3
"""
Deploy finished creatives as Meta ads — one parameterized tool that replaces
the ~15 hardcoded deploy_*.py scripts in the original Ad Builder Agent.

Each --image / --video becomes one ad in the target ad set, using a
multi-variant asset_feed_spec (TEXT_LIQUIDITY) so Meta rotates the supplied
body / title / description copy. Every ad is created PAUSED — review and
un-pause in Ads Manager.

Usage:
  python deploy-ad.py --adset-id 123 --copy-file copy.json --link https://x.com \\
      --image creative.png
  python deploy-ad.py --adset-id 123 --copy-file copy.json --link https://x.com \\
      --video a.mp4 --video b.mp4 --cta SIGN_UP
  python deploy-ad.py --dry-run --adset-id 123 --copy-file copy.json \\
      --link https://x.com --image creative.png

copy-file JSON shape (titles/descriptions may be plain strings or {"text": ...}):
  { "bodies": ["..."], "titles": ["..."], "descriptions": ["..."] }

Required env (load via .env): META_ACCESS_TOKEN, META_AD_ACCOUNT_ID.
page-id / ig-user-id / pixel-id default to META_PAGE_ID / META_IG_USER_ID /
META_PIXEL_ID env vars if the flags are omitted.
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent / "lib"))

load_dotenv()

import meta_api  # noqa: E402  (import after load_dotenv so env is populated)

# Advantage+ creative enhancements — enrolls the ad in Meta's automatic
# creative optimization. Mirrors the spec proven across the Ad Builder Agent.
CREATIVE_FEATURES_SPEC_BASE = {
    "advantage_plus_creative": {"enroll_status": "OPT_IN"},
    "creative_stickers": {"enroll_status": "OPT_IN"},
    "enhance_cta": {
        "enroll_status": "OPT_IN",
        "customizations": {"text_extraction": {"enroll_status": "OPT_IN"}},
    },
    "generate_cta": {"enroll_status": "OPT_IN"},
    "inline_comment": {"enroll_status": "OPT_IN"},
    "product_extensions": {
        "enroll_status": "OPT_OUT",
        "customizations": {"pe_carousel": {"enroll_status": "OPT_OUT"}},
    },
    "reveal_details_over_time": {"enroll_status": "OPT_IN"},
    "show_destination_blurbs": {"enroll_status": "OPT_IN"},
    "show_summary": {"enroll_status": "OPT_IN"},
    "site_extensions": {"enroll_status": "OPT_OUT"},
    "text_optimizations": {
        "enroll_status": "OPT_IN",
        "customizations": {"text_extraction": {"enroll_status": "OPT_IN"}},
    },
    "text_translation": {"enroll_status": "OPT_IN"},
}

CREATIVE_FEATURES_SPEC_VIDEO = {
    **CREATIVE_FEATURES_SPEC_BASE,
    "video_auto_crop": {"enroll_status": "OPT_IN"},
    "video_filtering": {"enroll_status": "OPT_IN"},
    "video_uncrop": {"enroll_status": "OPT_IN"},
}


def load_copy(copy_path):
    """Read the copy JSON and normalize titles/descriptions to {"text": ...}."""
    with open(copy_path) as f:
        data = json.load(f)
    bodies = data.get("bodies") or []
    if not bodies:
        raise SystemExit(f"copy-file {copy_path} has no 'bodies'")

    def as_text_objs(items):
        out = []
        for it in items or []:
            out.append(it if isinstance(it, dict) else {"text": str(it)})
        return out

    return {
        "bodies": [{"text": b} for b in bodies],
        "titles": as_text_objs(data.get("titles")),
        "descriptions": as_text_objs(data.get("descriptions")),
    }


def asset_feed_spec(copy, cta, link=None):
    spec = {
        "optimization_type": "DEGREES_OF_FREEDOM",
        "bodies": copy["bodies"],
        "titles": copy["titles"],
        "descriptions": copy["descriptions"],
        "call_to_action_types": [cta],
    }
    if link:
        spec["link_urls"] = [{"website_url": link}]
    return spec


def degrees_of_freedom_spec(is_video):
    return {
        "degrees_of_freedom_type": "USER_ENROLLED",
        "text_transformation_types": ["TEXT_LIQUIDITY"],
        "creative_features_spec": (
            CREATIVE_FEATURES_SPEC_VIDEO if is_video else CREATIVE_FEATURES_SPEC_BASE
        ),
    }


def build_image_creative(image_hash, copy, args):
    return {
        "object_story_spec": {
            "page_id": args.page_id,
            **({"instagram_user_id": args.ig_user_id} if args.ig_user_id else {}),
            "link_data": {
                "link": args.link,
                "image_hash": image_hash,
                "call_to_action": {"type": args.cta, "value": {"link": args.link}},
            },
        },
        "asset_feed_spec": asset_feed_spec(copy, args.cta, link=args.link),
        "degrees_of_freedom_spec": degrees_of_freedom_spec(is_video=False),
        "contextual_multi_ads": {"enroll_status": "OPT_IN"},
    }


def build_video_creative(video_id, thumb, copy, args):
    return {
        "object_story_spec": {
            "page_id": args.page_id,
            **({"instagram_user_id": args.ig_user_id} if args.ig_user_id else {}),
            "video_data": {
                "video_id": video_id,
                "image_url": thumb,
                "call_to_action": {"type": args.cta, "value": {"link": args.link}},
            },
        },
        "asset_feed_spec": asset_feed_spec(copy, args.cta),
        "degrees_of_freedom_spec": degrees_of_freedom_spec(is_video=True),
        "contextual_multi_ads": {"enroll_status": "OPT_IN"},
    }


def main():
    parser = argparse.ArgumentParser(description="Deploy finished creatives as Meta ads")
    parser.add_argument("--adset-id", required=True, help="Target ad set ID")
    parser.add_argument("--image", action="append", default=[], help="Image creative path (repeatable)")
    parser.add_argument("--video", action="append", default=[], help="Video creative path (repeatable)")
    parser.add_argument("--copy-file", required=True, help="JSON with bodies/titles/descriptions")
    parser.add_argument("--link", required=True, help="Destination URL")
    parser.add_argument("--cta", default="LEARN_MORE", help="Call-to-action type (default LEARN_MORE)")
    parser.add_argument("--page-id", default=os.getenv("META_PAGE_ID"), help="Facebook Page ID")
    parser.add_argument("--ig-user-id", default=os.getenv("META_IG_USER_ID"), help="Instagram user ID")
    parser.add_argument("--pixel-id", default=os.getenv("META_PIXEL_ID"), help="Meta Pixel ID for tracking")
    parser.add_argument("--name-prefix", default="meta-ad-builder", help="Ad name prefix")
    parser.add_argument("--dry-run", action="store_true", help="Print payloads, make no API calls")
    args = parser.parse_args()

    if not args.image and not args.video:
        raise SystemExit("Provide at least one --image or --video")
    if not args.page_id:
        raise SystemExit("--page-id (or META_PAGE_ID env) is required")
    if not args.dry_run:
        # Surfaces missing-credential errors before any upload.
        meta_api.get_access_token()
        meta_api.get_ad_account_id()

    copy = load_copy(args.copy_file)
    print("=" * 70)
    print(f"DEPLOY → ad set {args.adset_id}")
    print(f"  copy: {len(copy['bodies'])} bodies, {len(copy['titles'])} titles, "
          f"{len(copy['descriptions'])} descriptions")
    print(f"  creatives: {len(args.image)} image(s), {len(args.video)} video(s)")
    print(f"  cta={args.cta}  link={args.link}")
    if args.dry_run:
        print("  (DRY RUN — no API calls)")
    print("=" * 70)

    results = {"adset_id": args.adset_id, "dry_run": args.dry_run, "ads": []}

    for img in args.image:
        name = f"{args.name_prefix} - {Path(img).stem} (image)"
        print(f"\nIMAGE: {img}")
        if args.dry_run:
            if not Path(img).exists():
                print(f"  WARNING: missing file: {img}")
            creative = build_image_creative("dry_run_hash", copy, args)
            print(json.dumps(creative, indent=2)[:1500])
            results["ads"].append({"ad_name": name, "type": "image", "ad_id": "dry_run"})
            continue
        img_hash = meta_api.upload_image(img, name)
        if not img_hash:
            continue
        time.sleep(0.5)
        creative = build_image_creative(img_hash, copy, args)
        ad_id = meta_api.create_ad(args.adset_id, name, creative, pixel_id=args.pixel_id)
        if ad_id:
            results["ads"].append({"ad_name": name, "type": "image",
                                   "image_hash": img_hash, "ad_id": ad_id})

    for vid_path in args.video:
        name = f"{args.name_prefix} - {Path(vid_path).stem} (video)"
        print(f"\nVIDEO: {vid_path}")
        if args.dry_run:
            if not Path(vid_path).exists():
                print(f"  WARNING: missing file: {vid_path}")
            creative = build_video_creative("dry_run_video", "dry_run_thumb", copy, args)
            print(json.dumps(creative, indent=2)[:1500])
            results["ads"].append({"ad_name": name, "type": "video", "ad_id": "dry_run"})
            continue
        vid = meta_api.upload_video(vid_path)
        if not vid:
            continue
        thumb = meta_api.wait_for_video_processing(vid) or ""
        creative = build_video_creative(vid, thumb, copy, args)
        ad_id = meta_api.create_ad(args.adset_id, name, creative, pixel_id=args.pixel_id)
        if ad_id:
            results["ads"].append({"ad_name": name, "type": "video",
                                   "video_id": vid, "thumbnail_url": thumb, "ad_id": ad_id})

    run_slug = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    out_dir = meta_api.resolve_output_dir(run_slug)
    out_file = out_dir / "deployment_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    created = [a for a in results["ads"] if a["ad_id"] not in ("dry_run", None)]
    print("\n" + "=" * 70)
    if args.dry_run:
        print(f"DRY RUN complete. {len(results['ads'])} ad(s) would be created (PAUSED).")
    else:
        print(f"DONE. {len(created)} ad(s) created PAUSED. Review in Meta Ads Manager.")
    print(f"Results: {out_file}")
    print("=" * 70)


if __name__ == "__main__":
    main()
