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

Exit codes:
  0  every requested ad was created (or, with --dry-run, every payload built)
  1  at least one ad failed — the per-ad Meta error is in deployment_results.json
"""

import argparse
import copy as copy_module
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

# What each enrollment actually does to a shipped creative. Printed by
# --dry-run so a reviewer sees the whole surface before approving, not just
# the JSON keys. Meta adds features over time — re-check cheatsheet §8.1.
FEATURE_NOTES = {
    "advantage_plus_creative": "umbrella enrollment for Meta's automatic creative optimization",
    "creative_stickers": "Meta draws its own stickers/text badges over the creative",
    "enhance_cta": "rewrites the CTA label; text_extraction lifts wording off the creative itself",
    "generate_cta": "generates an additional CTA surface",
    "inline_comment": "surfaces a comment inline under the ad",
    "product_extensions": "appends a product carousel (OPT_OUT here — standalone creatives)",
    "reveal_details_over_time": "animates an overlay panel over the creative during playback",
    "show_destination_blurbs": "overlays a blurb about the destination site",
    "show_summary": "overlays a generated summary panel",
    "site_extensions": "appends site links below the ad (OPT_OUT here)",
    "text_optimizations": "rewrites body/title copy; text_extraction lifts wording off the creative",
    "text_translation": "auto-translates and rewrites the approved ad copy",
    "video_auto_crop": "re-crops the video for each placement",
    "video_filtering": "applies a colour/brightness filter to the video",
    "video_uncrop": "extends/outpaints the frame to fill other aspect ratios",
}

# Features that can deface a creative with text burned into the pixels, or
# rewrite copy the user already approved. Opted OUT by default — see
# --no-burned-in-captions to restore Meta's full enrollment.
#
# Keyed by feature; the value is (customization_or_None, reason).
CAPTION_UNSAFE = {
    "video_uncrop": (None, "outpaints the frame — burned-in captions get pushed off-centre or duplicated"),
    "video_auto_crop": (None, "re-crops per placement — burned-in captions get cropped out of frame"),
    "video_filtering": (None, "recolours the frame — kills the caption stroke's contrast"),
    "creative_stickers": (None, "draws stickers on top of the burned-in captions"),
    "reveal_details_over_time": (None, "animates an overlay panel across the burned-in captions"),
    "show_summary": (None, "overlays a summary panel across the burned-in captions"),
    "show_destination_blurbs": (None, "overlays a destination blurb across the burned-in captions"),
    "text_translation": (None, "rewrites copy the user approved verbatim"),
    "enhance_cta": ("text_extraction", "would lift the burned-in caption text and reuse it as CTA wording"),
    "text_optimizations": ("text_extraction", "would lift the burned-in caption text and reuse it as ad copy"),
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
    # link_urls is sent for image ads only. The video path carries its
    # destination through object_story_spec.video_data.call_to_action instead,
    # and a live deploy confirmed the video ad resolves its link correctly
    # without it (2026-08-03). See reference/deploy-patterns.md.
    if link:
        spec["link_urls"] = [{"website_url": link}]
    return spec


def creative_features_spec(is_video, burned_in_captions):
    """Build the enrollment map, returning (spec, opt_outs).

    opt_outs is a list of (feature, customization_or_None, reason) describing
    every enrollment flipped OPT_IN → OPT_OUT for caption safety, so the
    caller can print exactly what was disabled and why.
    """
    spec = copy_module.deepcopy(
        CREATIVE_FEATURES_SPEC_VIDEO if is_video else CREATIVE_FEATURES_SPEC_BASE
    )
    opt_outs = []
    if not burned_in_captions:
        return spec, opt_outs

    for feature, (customization, reason) in CAPTION_UNSAFE.items():
        node = spec.get(feature)
        if node is None:
            continue  # e.g. the video-only features on an image creative
        if customization is None:
            if node.get("enroll_status") == "OPT_IN":
                node["enroll_status"] = "OPT_OUT"
                opt_outs.append((feature, None, reason))
        else:
            child = node.get("customizations", {}).get(customization)
            if child and child.get("enroll_status") == "OPT_IN":
                child["enroll_status"] = "OPT_OUT"
                opt_outs.append((feature, customization, reason))
    return spec, opt_outs


def degrees_of_freedom_spec(is_video, burned_in_captions):
    spec, opt_outs = creative_features_spec(is_video, burned_in_captions)
    return {
        "degrees_of_freedom_type": "USER_ENROLLED",
        "text_transformation_types": ["TEXT_LIQUIDITY"],
        "creative_features_spec": spec,
    }, opt_outs


def build_image_creative(image_hash, copy, args):
    dof, opt_outs = degrees_of_freedom_spec(False, args.burned_in_captions)
    creative = {
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
        "degrees_of_freedom_spec": dof,
        "contextual_multi_ads": {"enroll_status": "OPT_IN"},
    }
    return creative, opt_outs


def build_video_creative(video_id, thumb, copy, args):
    dof, opt_outs = degrees_of_freedom_spec(True, args.burned_in_captions)
    creative = {
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
        "degrees_of_freedom_spec": dof,
        "contextual_multi_ads": {"enroll_status": "OPT_IN"},
    }
    return creative, opt_outs


def print_creative_payload(creative):
    """Print the creative payload in full. Never truncate.

    The block a reviewer most needs to see — degrees_of_freedom_spec — sits at
    the end of the JSON, so any output cap hides exactly the wrong thing.
    """
    print("\n  --- creative payload (full) ---")
    print(json.dumps(creative, indent=2))
    print("  --- end creative payload ---")


def print_enhancements(creative, opt_outs, burned_in_captions):
    """List every Advantage+ enrollment Meta will apply, and its value."""
    dof = creative["degrees_of_freedom_spec"]
    features = dof["creative_features_spec"]
    print("\n  --- Advantage+ enhancements (degrees_of_freedom_spec) ---")
    print(f"    degrees_of_freedom_type   : {dof['degrees_of_freedom_type']}")
    print(f"    text_transformation_types : {', '.join(dof['text_transformation_types'])}")
    print(f"    creative_features_spec    : {len(features)} features")
    for name in sorted(features):
        node = features[name]
        note = FEATURE_NOTES.get(name, "")
        print(f"      {node['enroll_status']:<8} {name:<26} {note}")
        for child_name, child in (node.get("customizations") or {}).items():
            print(f"        └ {child['enroll_status']:<6} {child_name:<24} (customization)")
    print("    contextual_multi_ads      : "
          f"{creative['contextual_multi_ads']['enroll_status']}")

    if not burned_in_captions:
        print("\n    CAPTION SAFETY: OFF (--no-burned-in-captions).")
        print("    Meta's full enrollment is being sent. If this creative has text burned")
        print("    into the pixels, Meta may crop, filter or overlay across it.")
        return
    if not opt_outs:
        print("\n    CAPTION SAFETY: ON — nothing needed flipping for this creative.")
        return
    print(f"\n    CAPTION SAFETY: ON — {len(opt_outs)} enrollment(s) forced to OPT_OUT")
    print("    (creatives from this workspace carry text burned into the pixels;")
    print("     pass --no-burned-in-captions to send Meta's full enrollment instead):")
    for feature, customization, reason in opt_outs:
        label = f"{feature}.{customization}" if customization else feature
        print(f"      OPT_OUT  {label}")
        print(f"               ↳ {reason}")


def print_orphans(orphans):
    """Print assets that exist on Meta's side after a failed run, + cleanup."""
    if not orphans:
        return
    acct = meta_api.get_ad_account_id()
    print("\n" + "-" * 70)
    print("PARTIAL FAILURE — these objects were created before the failure and")
    print("still exist in your ad account. Nothing here spends money (ads are")
    print("PAUSED; uploaded assets are inert), but they are yours to clean up.")
    print("-" * 70)
    for o in orphans:
        print(f"  {o['kind']:<6} {o['id']}   ({o.get('source', '')})")
    print("\nReady-to-run cleanup (uses $META_ACCESS_TOKEN from your environment,")
    print("so no token is printed here). Review before running — this deletes:")
    print()
    for o in orphans:
        if o["kind"] == "image":
            print(f'  curl -s -X DELETE "{meta_api.BASE_URL}/{acct}/adimages'
                  f'?hash={o["id"]}&access_token=$META_ACCESS_TOKEN"')
        else:
            print(f'  curl -s -X DELETE "{meta_api.BASE_URL}/{o["id"]}'
                  f'?access_token=$META_ACCESS_TOKEN"')
    print()
    print("Deletion is NOT automatic: this script will not delete objects in a")
    print("live ad account on your behalf. Copy the lines you want.")


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
    parser.add_argument(
        "--burned-in-captions", action=argparse.BooleanOptionalAction, default=True,
        help="Treat the creative as carrying text burned into the pixels and opt out of the "
             "Advantage+ features that would crop, filter or overlay across it, plus "
             "text_translation (default: on). --no-burned-in-captions sends Meta's full enrollment.",
    )
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
    print(f"  caption safety: {'ON' if args.burned_in_captions else 'OFF'}")
    if args.dry_run:
        print("  (DRY RUN — no API calls)")
    print("=" * 70)

    results = {"adset_id": args.adset_id, "dry_run": args.dry_run,
               "burned_in_captions": args.burned_in_captions,
               "ads": [], "failures": [], "orphans": []}
    orphans = results["orphans"]
    missing_files = False

    for img in args.image:
        name = f"{args.name_prefix} - {Path(img).stem} (image)"
        print(f"\nIMAGE: {img}")
        if args.dry_run:
            if not Path(img).exists():
                print(f"  ERROR: missing file: {img}")
                missing_files = True
            creative, opt_outs = build_image_creative("dry_run_hash", copy, args)
            print_creative_payload(creative)
            print_enhancements(creative, opt_outs, args.burned_in_captions)
            results["ads"].append({"ad_name": name, "type": "image", "ad_id": "dry_run"})
            continue
        img_hash, err = meta_api.upload_image(img, name)
        if err:
            results["failures"].append({"ad_name": name, "type": "image",
                                        "creative_path": img, "error": err})
            continue
        orphans.append({"kind": "image", "id": img_hash, "source": img})
        time.sleep(0.5)
        creative, opt_outs = build_image_creative(img_hash, copy, args)
        ad_id, err = meta_api.create_ad(args.adset_id, name, creative, pixel_id=args.pixel_id)
        if err:
            results["failures"].append({"ad_name": name, "type": "image",
                                        "creative_path": img, "image_hash": img_hash,
                                        "error": err})
            continue
        orphans[-1] = {**orphans[-1], "attached_to_ad": ad_id}
        results["ads"].append({"ad_name": name, "type": "image",
                               "image_hash": img_hash, "ad_id": ad_id})

    for vid_path in args.video:
        name = f"{args.name_prefix} - {Path(vid_path).stem} (video)"
        print(f"\nVIDEO: {vid_path}")
        if args.dry_run:
            if not Path(vid_path).exists():
                print(f"  ERROR: missing file: {vid_path}")
                missing_files = True
            creative, opt_outs = build_video_creative("dry_run_video", "dry_run_thumb", copy, args)
            print_creative_payload(creative)
            print_enhancements(creative, opt_outs, args.burned_in_captions)
            results["ads"].append({"ad_name": name, "type": "video", "ad_id": "dry_run"})
            continue
        vid, err = meta_api.upload_video(vid_path)
        if err:
            results["failures"].append({"ad_name": name, "type": "video",
                                        "creative_path": vid_path, "error": err})
            continue
        orphans.append({"kind": "video", "id": vid, "source": vid_path})
        # A processing timeout is not fatal on its own — create_ad is the
        # authority on whether the video was usable. The warning is kept.
        thumb, poll_err = meta_api.wait_for_video_processing(vid)
        creative, opt_outs = build_video_creative(vid, thumb or "", copy, args)
        ad_id, err = meta_api.create_ad(args.adset_id, name, creative, pixel_id=args.pixel_id)
        if err:
            failure = {"ad_name": name, "type": "video", "creative_path": vid_path,
                       "video_id": vid, "error": err}
            if poll_err:
                failure["video_processing_warning"] = poll_err
            results["failures"].append(failure)
            continue
        orphans[-1] = {**orphans[-1], "attached_to_ad": ad_id}
        results["ads"].append({"ad_name": name, "type": "video",
                               "video_id": vid, "thumbnail_url": thumb, "ad_id": ad_id})

    created = [a for a in results["ads"] if a["ad_id"] not in ("dry_run", None)]
    failed = results["failures"]
    requested = len(args.image) + len(args.video)
    # Only assets that never made it onto an ad are orphans worth cleaning up.
    results["orphans"] = [o for o in orphans if "attached_to_ad" not in o]
    results["summary"] = {"requested": requested, "created": len(created),
                          "failed": len(failed)}

    run_slug = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    out_dir = meta_api.resolve_output_dir(run_slug)
    out_file = out_dir / "deployment_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    print("\n" + "=" * 70)
    if args.dry_run:
        if missing_files:
            print(f"DRY RUN FAILED. {len(results['ads'])} payload(s) built, but at least one "
                  "creative file is missing.")
            print(f"Results: {out_file}")
            print("=" * 70)
            sys.exit(1)
        print(f"DRY RUN complete. {len(results['ads'])} ad(s) would be created (PAUSED).")
        print(f"Results: {out_file}")
        print("=" * 70)
        return

    if failed:
        print(f"FAILED. {len(failed)} of {requested} ad(s) were NOT created.")
        for f_ in failed:
            print(f"  ✗ {f_['ad_name']}")
            print(f"      {meta_api.format_error(f_['error'])}")
            if f_["error"].get("fbtrace_id"):
                print(f"      fbtrace_id: {f_['error']['fbtrace_id']}")
    if created:
        print(f"{len(created)} ad(s) created PAUSED. Review in Meta Ads Manager.")
        for a in created:
            print(f"  ✓ {a['ad_id']}  {a['ad_name']}")
    elif not failed:
        print("Nothing to do — no creatives were processed.")

    print_orphans(results["orphans"])

    print(f"\nResults: {out_file}")
    print("=" * 70)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
