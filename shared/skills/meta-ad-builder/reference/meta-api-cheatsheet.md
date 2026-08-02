# Meta Marketing API — Master Cheat Sheet

> Everything you need to know to programmatically create and manage campaigns, ad sets, ads, and creative assets on Meta (Facebook/Instagram) via the Graph API. Distilled from a production codebase that has launched thousands of ads.

**Base URL:** `https://graph.facebook.com/{API_VERSION}`

**Current recommended versions:** `v24.0` (general), `v23.0` (ASC+ campaigns, DSA queries, OAuth)

**Auth header:** `Authorization: Bearer {ACCESS_TOKEN}`

---

## Table of Contents

1. [Authentication & OAuth](#1-authentication--oauth)
2. [Account Management](#2-account-management)
3. [Campaigns](#3-campaigns)
4. [Ad Sets](#4-ad-sets)
5. [Ads](#5-ads)
6. [Creative Assets (Images & Videos)](#6-creative-assets-images--videos)
7. [Ad Insights & Reporting](#7-ad-insights--reporting)
8. [Advantage+ Creative Enhancements](#8-advantage-creative-enhancements)
9. [Batch API](#9-batch-api)
10. [Copying Existing Objects](#10-copying-existing-objects)
11. [Error Handling & Retries](#11-error-handling--retries)
12. [Gotchas & Hard-Won Lessons](#12-gotchas--hard-won-lessons)
13. [Enum Reference](#13-enum-reference)
14. [Ad Library API (ads_archive)](#14-ad-library-api-ads_archive)

---

## 1. Authentication & OAuth

### 1.1 OAuth Login (Facebook Login for Business)

Redirect the user to Meta's OAuth dialog:

```
https://www.facebook.com/v23.0/dialog/oauth
  ?client_id={META_APP_ID}
  &redirect_uri={REDIRECT_URI}
  &response_type=code
  &code_challenge={CODE_CHALLENGE}
  &code_challenge_method=S256
  &state={RANDOM_STATE}
  &scope=ads_management,ads_read,business_management,pages_read_engagement
```

**PKCE flow:** Generate a 128-char random `code_verifier`, SHA-256 hash it for `code_challenge`. Store both `code_verifier` and `state` in HTTP-only cookies (10-min TTL).

### 1.2 Token Exchange (Code → Access Token)

```
POST https://graph.facebook.com/v23.0/oauth/access_token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code={AUTH_CODE}
&client_id={META_APP_ID}
&client_secret={META_APP_SECRET}
&redirect_uri={REDIRECT_URI}
&code_verifier={CODE_VERIFIER}
```

**Response:**
```json
{
  "access_token": "EAAx...",
  "expires_in": 5184000
}
```

### 1.3 Exchange for Long-Lived Token

If `expires_in` is missing or short, exchange for a long-lived token (~60 days):

```
GET https://graph.facebook.com/v23.0/oauth/access_token
  ?grant_type=fb_exchange_token
  &client_id={META_APP_ID}
  &client_secret={META_APP_SECRET}
  &fb_exchange_token={SHORT_LIVED_TOKEN}
```

**Key detail:** If the token is already long-lived, Meta returns error code `190` with subcode `463`. This is not a real error — the token is fine.

### 1.4 Token Inspection / Debug

```
GET https://graph.facebook.com/debug_token
  ?input_token={TOKEN_TO_INSPECT}
  &access_token={APP_ID}|{APP_SECRET}
```

Returns `app_id`, `user_id`, `scopes`, `expires_at`, and `type`.

### 1.5 Token Refresh Strategy

Meta tokens from Facebook Login for Business don't have refresh tokens. The strategy:
- Exchange short-lived → long-lived (~60 days) on first connect
- Periodically check `expires_at`, re-exchange within 7 days of expiry
- If token is expired, user must re-authenticate (no silent refresh)

---

## 2. Account Management

### 2.1 Fetch User's Ad Accounts

```
GET /me/adaccounts
  ?fields=account_id,name,currency,timezone_name,account_status
  &limit=100
```

### 2.2 Fetch User's Pages

```
GET /me/accounts
  ?fields=id,name,access_token,category
```

### 2.3 Fetch User's Businesses

```
GET /me/businesses
  ?fields=id,name,primary_page
```

### 2.4 Fetch User Profile

```
GET /me
  ?fields=id,name,email
```

### 2.5 Ad Account ID Format

All ad account endpoints require the `act_` prefix:
```
act_1234567890
```

Always normalize:
```typescript
function normalizeAccountId(id: string): string {
  return id.startsWith("act_") ? id : `act_${id}`;
}
```

---

## 3. Campaigns

### 3.1 Create a Campaign

```
POST /act_{ACCOUNT_ID}/campaigns
Authorization: Bearer {TOKEN}
Content-Type: application/json

{
  "name": "My Campaign",
  "objective": "OUTCOME_SALES",
  "status": "PAUSED",
  "special_ad_categories": [],
  "daily_budget": 10000,
  "pacing_type": ["standard"],
  "bid_strategy": "LOWEST_COST_WITHOUT_CAP"
}
```

### 3.2 Campaign Objectives

| Human-Readable | API Value |
|---|---|
| Sales | `OUTCOME_SALES` |
| Leads | `OUTCOME_LEADS` |
| Traffic | `OUTCOME_TRAFFIC` |

### 3.3 Campaign Types & Their Payloads

**ADV+ Budget (Advantage+ Campaign Budget / CBO):**
```json
{
  "daily_budget": 10000,
  "pacing_type": ["standard"],
  "bid_strategy": "LOWEST_COST_WITHOUT_CAP"
}
```
Budget is in **cents** (10000 = $100.00).

**ABO (Ad Set Budget Optimization):**
- Do NOT include `daily_budget`, `pacing_type`, or `bid_strategy` at campaign level
- Budget is set at the ad set level instead

**ASC+ (Advantage Shopping Campaign+):**
```json
{
  "smart_promotion_type": "AUTOMATED_SHOPPING_ADS"
}
```
- Use API version `v23.0` (deprecated in v24.0+)
- Do NOT include `is_adset_budget_sharing_enabled`

### 3.4 Adset Budget Sharing

For non-ASC+ campaigns, `is_adset_budget_sharing_enabled` must **always** be explicitly set:
```json
{
  "is_adset_budget_sharing_enabled": true,
  "bid_strategy": "LOWEST_COST_WITHOUT_CAP"
}
```
When enabling budget sharing, `bid_strategy` is also required.

### 3.5 Special Ad Categories

**Always required** (even if empty):
```json
{
  "special_ad_categories": []
}
```

Valid values: `HOUSING`, `EMPLOYMENT`, `CREDIT`, `ISSUES_ELECTIONS_POLITICS`

With country restrictions:
```json
{
  "special_ad_categories": ["HOUSING"],
  "special_ad_category_country": ["US", "CA"]
}
```
Only include `special_ad_category_country` when it has values — explicitly `delete` it otherwise.

> `special_ad_category` (singular) is deprecated since API v7.0+. Always use the plural array.

### 3.6 Campaign Status

| Human-Readable | API Value |
|---|---|
| Active | `ACTIVE` |
| Paused | `PAUSED` |

### 3.7 Fetch Existing Campaigns

```
GET /act_{ACCOUNT_ID}/campaigns
  ?fields=name,id
  &filtering=[{"field":"spend","operator":"GREATER_THAN","value":0}]
  &time_range={"since":"2026-02-01","until":"2026-03-23"}
  &access_token={TOKEN}
```

Supports pagination via `data.paging.next`.

Alternative filter for recently created:
```json
[{"field": "created_time", "operator": "GREATER_THAN", "value": "2026-03-16T00:00:00Z"}]
```

### 3.8 Fetch Campaigns with Status Filter

```
GET /act_{ACCOUNT_ID}/campaigns
  ?fields=id,name,objective,status,daily_budget,lifetime_budget
  &filtering=[{"field":"effective_status","operator":"IN","value":["ACTIVE","PAUSED"]}]
  &limit=100
```

---

## 4. Ad Sets

### 4.1 Create an Ad Set

```
POST /act_{ACCOUNT_ID}/adsets
Authorization: Bearer {TOKEN}
Content-Type: application/json

{
  "name": "My Ad Set",
  "campaign_id": "120200...",
  "billing_event": "IMPRESSIONS",
  "optimization_goal": "OFFSITE_CONVERSIONS",
  "status": "ACTIVE",
  "bid_strategy": "LOWEST_COST_WITHOUT_CAP",
  "pacing_type": ["standard"],
  "daily_budget": 5000,
  "promoted_object": {
    "pixel_id": "123456789",
    "custom_event_type": "PURCHASE"
  },
  "targeting": { ... },
  "attribution_spec": [{ ... }],
  "start_time": "2026-04-01T00:00:00-0400",
  "end_time": "2026-04-30T23:59:59-0400"
}
```

### 4.2 Targeting Object — Full Structure

```json
{
  "geo_locations": {
    "countries": ["US"],
    "regions": [{"key": "3847"}],
    "cities": [{"key": "2420587", "name": "New York", "region": "New York"}],
    "zips": [{"key": "US:10001"}],
    "location_types": ["home", "recent"]
  },
  "excluded_geo_locations": {
    "regions": [{"key": "3886"}],
    "cities": [{"key": "2512345"}],
    "zips": [{"key": "US:90210"}],
    "location_types": ["home", "recent"]
  },
  "age_min": 25,
  "age_max": 55,
  "genders": [1],
  "interests": [{"id": "6003139266461"}],
  "custom_audiences": [{"id": "23850..."}],
  "excluded_custom_audiences": [{"id": "23850..."}],
  "publisher_platforms": ["facebook", "instagram"],
  "facebook_positions": ["feed", "story", "facebook_reels", "right_hand_column", "search", "marketplace", "video_feeds", "instream_video"],
  "instagram_positions": ["stream", "story", "reels", "explore", "explore_home", "profile_feed", "ig_search", "profile_reels"],
  "messenger_positions": ["story"],
  "audience_network_positions": ["classic"],
  "device_platforms": ["mobile", "desktop"],
  "user_os": ["iOS"],
  "targeting_automation": {
    "advantage_audience": 1,
    "individual_setting": {
      "age": 1,
      "gender": 1
    }
  }
}
```

### 4.3 Geo Targeting Priority

When multiple geo types are specified:
- `cities`, `regions`, and `zips` can be **combined**
- `countries` is only used when **none** of cities/regions/zips are specified
- Always include `location_types: ["home", "recent"]` when using cities, regions, or zips

### 4.4 Advantage+ Audience (Targeting Automation)

```json
// Enabled
"targeting_automation": {
  "advantage_audience": 1,
  "individual_setting": { "age": 1, "gender": 1 }
}

// Disabled (must be explicit)
"targeting_automation": {
  "advantage_audience": 0
}
```

**For ASC+ campaigns:** `targeting_automation` must be **completely omitted** from the payload.

### 4.5 Gender Codes

| Gender | Code |
|---|---|
| All | omit field |
| Male | `1` |
| Female | `2` |

### 4.6 Promoted Object

```json
{
  "pixel_id": "123456789",
  "custom_event_type": "PURCHASE",
  "custom_event_str": "my_custom_event"
}
```

`custom_event_str` is optional — used for custom conversion events.

### 4.7 Attribution Spec

Format: parse as `[{...}]`

### 4.8 Incremental Attribution

```json
{
  "is_incremental_attribution_enabled": true
}
```

Only include when enabled. Omit the field entirely when using standard attribution.

### 4.9 Daily Spend Controls

```json
{
  "daily_min_spend_target": 500,
  "daily_spend_cap": 5000
}
```

Values are in **cents**. Input dollars × 100.

### 4.10 Daily Budget on Ad Sets

Only set `daily_budget` on the ad set when the campaign type is **NOT** "ADV+ Budget" (CBO). CBO campaigns manage budget at the campaign level.

### 4.11 DSA Beneficiary & Payor (EU Compliance)

Required when targeting EU countries:
```json
{
  "dsa_beneficiary": "Company Name",
  "dsa_payor": "Company Name"
}
```

EU countries requiring DSA: AT, BE, BG, HR, CY, CZ, DK, EE, FI, FR, DE, GR, HU, IE, IT, LV, LT, LU, MT, NL, PL, PT, RO, SK, SI, ES, SE

**Fetching DSA info from Meta (fallback strategy):**
1. Try account defaults: `GET /act_{ID}?fields=default_dsa_beneficiary,default_dsa_payor`
2. Try existing ad set in same campaign: `GET /{CAMPAIGN_ID}/adsets?fields=dsa_beneficiary,dsa_payor&limit=1`
3. Try any ad set in account: `GET /act_{ID}/adsets?fields=dsa_beneficiary,dsa_payor&limit=1`

### 4.12 Fetch Existing Ad Sets

```
GET /act_{ACCOUNT_ID}/adsets
  ?fields=name,id,account_id,campaign_id,created_time
  &filtering=[{"field":"spend","operator":"GREATER_THAN","value":1}]
  &access_token={TOKEN}
```

Also supports `created_time` filtering for recently created ad sets.

### 4.13 Fetch Ad Sets for a Campaign

```
GET /{CAMPAIGN_ID}/adsets
  ?fields=id,name,status,daily_budget,optimization_goal
  &limit=100
```

---

## 5. Ads

### 5.1 Create an Ad

```
POST /act_{ACCOUNT_ID}/ads
Authorization: Bearer {TOKEN}
Content-Type: application/json

{
  "adset_id": "120200...",
  "account_id": "710640...",
  "name": "My Ad Name",
  "status": "ACTIVE",
  "creative": { ... },
  "url_tags": "utm_source=facebook&utm_medium=paid",
  "tracking_specs": [
    {
      "action.type": ["offsite_conversion"],
      "fb_pixel": ["123456789"]
    }
  ],
  "adlabels": [
    { "name": "My Ad Name" }
  ]
}
```

### 5.2 Ad Status Values

`ACTIVE`, `PAUSED`, `ARCHIVED`

### 5.3 Creative Object — Video Ad (Single Variation)

```json
{
  "object_story_spec": {
    "page_id": "123456789",
    "instagram_user_id": "987654321",
    "threads_user_id": "111222333",
    "video_data": {
      "video_id": "120200...",
      "title": "Headline Text",
      "message": "Body/post text",
      "link_description": "Description below headline",
      "image_url": "https://...",
      "call_to_action": {
        "type": "SHOP_NOW",
        "value": {
          "link": "https://example.com",
          "link_caption": "example.com"
        }
      }
    }
  },
  "degrees_of_freedom_spec": {
    "degrees_of_freedom_type": "USER_ENROLLED",
    "creative_features_spec": { ... }
  },
  "contextual_multi_ads": { "enroll_status": "OPT_OUT" },
  "url_tags": "utm_source=facebook"
}
```

### 5.4 Creative Object — Image Ad (Single Variation)

```json
{
  "object_story_spec": {
    "page_id": "123456789",
    "instagram_user_id": "987654321",
    "link_data": {
      "image_hash": "9f495644042f7f00f52ab72422a9f3fc",
      "link": "https://example.com",
      "name": "Headline Text",
      "message": "Body/post text",
      "description": "Link description",
      "call_to_action": {
        "type": "LEARN_MORE",
        "value": {
          "link": "https://example.com",
          "link_caption": "example.com"
        }
      }
    }
  },
  "degrees_of_freedom_spec": {
    "degrees_of_freedom_type": "USER_ENROLLED",
    "creative_features_spec": { ... }
  },
  "contextual_multi_ads": { "enroll_status": "OPT_OUT" },
  "url_tags": "utm_source=facebook"
}
```

### 5.5 Creative Object — Multi-Variation (Flexible Ads / Text Liquidity)

When you have multiple headlines or body texts:

```json
{
  "object_story_spec": {
    "page_id": "123456789",
    "instagram_user_id": "987654321",
    "video_data": {
      "video_id": "120200...",
      "image_url": "https://...",
      "call_to_action": {
        "type": "SHOP_NOW",
        "value": { "link": "https://example.com" }
      }
    }
  },
  "degrees_of_freedom_spec": {
    "degrees_of_freedom_type": "USER_ENROLLED",
    "text_transformation_types": ["TEXT_LIQUIDITY"],
    "creative_features_spec": { ... }
  },
  "asset_feed_spec": {
    "optimization_type": "DEGREES_OF_FREEDOM",
    "titles": [
      { "text": "Headline 1" },
      { "text": "Headline 2" },
      { "text": "Headline 3" }
    ],
    "bodies": [
      { "text": "Body 1" },
      { "text": "Body 2" }
    ],
    "descriptions": [
      { "text": "Description text" }
    ],
    "call_to_action_types": ["SHOP_NOW"]
  },
  "contextual_multi_ads": { "enroll_status": "OPT_OUT" },
  "url_tags": "utm_source=facebook"
}
```

### 5.6 Creative Object — Existing Post Reference

```json
{
  "object_story_id": "PAGE_ID_POST_ID",
  "contextual_multi_ads": { "enroll_status": "OPT_OUT" },
  "url_tags": "utm_source=facebook"
}
```

### 5.7 Asset Customization (Placement-Specific Creatives)

Used when different assets target different placements (feeds vs. stories/reels vs. right column):

```json
{
  "object_story_spec": {
    "page_id": "123456789",
    "instagram_user_id": "987654321",
    "threads_user_id": "111222333"
  },
  "asset_feed_spec": {
    "optimization_type": "PLACEMENT",
    "ad_formats": ["AUTOMATIC_FORMAT"],
    "titles": [
      { "text": "Headline", "adlabels": [{"name": "placement_asset_titles"}] }
    ],
    "bodies": [
      { "text": "Body text", "adlabels": [{"name": "placement_asset_bodies"}] }
    ],
    "descriptions": [{ "text": "Description" }],
    "call_to_action_types": ["SHOP_NOW"],
    "images": [
      { "hash": "abc123...", "adlabels": [{"name": "placement_right_column_asset"}] }
    ],
    "videos": [
      {
        "video_id": 120200123,
        "thumbnail_url": "https://...",
        "adlabels": [{"name": "placement_feeds_asset"}]
      },
      {
        "video_id": 120200456,
        "thumbnail_url": "https://...",
        "adlabels": [{"name": "placement_stories_reels_asset"}]
      }
    ],
    "link_urls": [
      {
        "website_url": "https://example.com",
        "display_url": "example.com"
      }
    ],
    "asset_customization_rules": [
      {
        "customization_spec": {
          "publisher_platforms": ["facebook", "instagram", "threads"],
          "facebook_positions": ["feed", "biz_disco_feed", "profile_feed", "video_feeds", "instream_video", "marketplace", "notification"],
          "instagram_positions": ["stream", "ig_search", "explore", "explore_home", "profile_feed"],
          "threads_positions": ["feed"]
        },
        "priority": 1,
        "video_label": {"name": "placement_feeds_asset"},
        "title_label": {"name": "placement_asset_titles"},
        "body_label": {"name": "placement_asset_bodies"}
      },
      {
        "customization_spec": {
          "publisher_platforms": ["facebook", "instagram", "messenger"],
          "facebook_positions": ["story", "facebook_reels"],
          "instagram_positions": ["story", "reels", "profile_reels", "ig_search"],
          "messenger_positions": ["story"]
        },
        "priority": 2,
        "video_label": {"name": "placement_stories_reels_asset"},
        "title_label": {"name": "placement_asset_titles"},
        "body_label": {"name": "placement_asset_bodies"}
      },
      {
        "customization_spec": {
          "publisher_platforms": ["facebook"],
          "facebook_positions": ["right_hand_column", "search"]
        },
        "priority": 3,
        "image_label": {"name": "placement_right_column_asset"},
        "title_label": {"name": "placement_asset_titles"},
        "body_label": {"name": "placement_asset_bodies"}
      }
    ]
  },
  "degrees_of_freedom_spec": {
    "creative_features_spec": { ... }
  },
  "contextual_multi_ads": { "enroll_status": "OPT_OUT" },
  "url_tags": "utm_source=facebook"
}
```

**Rules for asset customization:**
- Meta requires **at least 2** `asset_customization_rules`
- If a placement-specific asset is missing, the main `asset_id` is used as fallback
- For images, use `image_label`; for videos, use `video_label`
- If the same asset is used for multiple placements, merge the adlabels onto one entry (Meta rejects duplicate asset values in the arrays)
- `video_id` in the `videos` array must be a **number** (parseInt), not a string

### 5.8 Multi Advertiser Ads (contextual_multi_ads)

```json
// Opt in
"contextual_multi_ads": { "enroll_status": "OPT_IN" }

// Opt out
"contextual_multi_ads": { "enroll_status": "OPT_OUT" }
```

### 5.9 Fetching an Ad's Creative Details

```
GET /{AD_ID}
  ?fields=creative{object_story_spec,asset_feed_spec,degrees_of_freedom_spec,contextual_multi_ads,url_tags}
```

For read-only analysis with more fields:
```
GET /{AD_ID}
  ?fields=name,creative{id,name,title,body,image_url,thumbnail_url,object_story_spec,asset_feed_spec,call_to_action_type,effective_object_story_id}
```

### 5.10 Fetching a Creative's Enhancement Spec

```
GET /{CREATIVE_ID}
  ?fields=degrees_of_freedom_spec
```

Response:
```json
{
  "degrees_of_freedom_spec": {
    "creative_features_spec": {
      "image_animation": { "enroll_status": "OPT_IN" },
      "text_optimizations": {
        "enroll_status": "OPT_IN",
        "customizations": {
          "text_extraction": { "enroll_status": "OPT_IN" }
        }
      }
    }
  }
}
```

### 5.11 Fetch Ads for an Ad Set

```
GET /{AD_SET_ID}/ads
  ?fields=id,name,status,creative{id,name}
  &limit=100
```

### 5.12 Fetching an Existing Post's Copy

```
GET /{STORY_ID}
  ?fields=message,story
```

Where `STORY_ID` = `effective_object_story_id` from the creative.

---

## 6. Creative Assets (Images & Videos)

### 6.1 Upload Image (Base64)

```
POST /act_{ACCOUNT_ID}/adimages
Content-Type: application/x-www-form-urlencoded

bytes={BASE64_IMAGE_DATA}
&name=my-image.jpg
&access_token={TOKEN}
```

**Response:**
```json
{
  "images": {
    "my-image.jpg": {
      "hash": "9f495644042f7f00f52ab72422a9f3fc",
      "url": "https://scontent..."
    }
  }
}
```

**Max image size:** 30MB

The `hash` is your `image_hash` / `asset_id` for image ads. It's a 32-character hex string.

### 6.2 Upload Image (Multipart / Binary File)

```
POST /act_{ACCOUNT_ID}/adimages
Content-Type: multipart/form-data

file: (binary image data, filename required)
access_token: {TOKEN}
```

Use FormData with `formData.append("filename.jpg", blob, "filename.jpg")`.

### 6.3 Upload Video (URL-Based)

```
POST /act_{ACCOUNT_ID}/advideos
Content-Type: application/json

{
  "file_url": "https://publicly-accessible-url.com/video.mp4",
  "name": "my-video.mp4"
}
```

**Response:**
```json
{ "id": "120200..." }
```

Video processing is **asynchronous**. The video ID is returned immediately, but the video may not be ready for use in ads for a few minutes.

### 6.4 Fetch Image URL by Hash

```
GET /act_{ACCOUNT_ID}/adimages
  ?hashes=["9f495644042f7f00f52ab72422a9f3fc"]
  &fields=url,hash,name
```

**Response:**
```json
{
  "data": [
    { "hash": "9f49...", "url": "https://scontent...", "name": "my-image.jpg" }
  ]
}
```

### 6.5 Fetch Video Source & Thumbnail

```
GET /{VIDEO_ID}
  ?fields=source,picture
```

Returns `source` (playable video URL) and `picture` (poster image).

### 6.6 Fetch Video Thumbnails

```
GET /{VIDEO_ID}
  ?fields=thumbnails{uri,is_preferred}
```

**Response:**
```json
{
  "thumbnails": {
    "data": [
      { "uri": "https://...", "is_preferred": true },
      { "uri": "https://...", "is_preferred": false }
    ]
  }
}
```

Pick `is_preferred: true`, fall back to first available.

### 6.7 Video Thumbnail Gotchas

- `video_data` can have **either** `image_url` **or** `image_hash`, never both. Meta rejects payloads with both present.
- In `asset_feed_spec.videos[]`, there is **no** `thumbnail_hash` field. Only `thumbnail_url` is supported.
- Airtable/temporary URLs in `thumbnail_url` can cause error `1487713` ("Video failed to process"). Fix by uploading the image to Meta's adimages API first, then either:
  - Use the returned `hash` as `image_hash` in `video_data` (replacing `image_url`)
  - Or omit `thumbnail_url` in `asset_feed_spec` and let Meta auto-generate

---

## 7. Ad Insights & Reporting

### 7.1 Pull Ad-Level Insights

```
GET /act_{ACCOUNT_ID}/insights
  ?level=ad
  &fields=ad_id,ad_name,campaign_name,adset_name,spend,impressions,clicks,ctr,cpc,cpm,actions,action_values,cost_per_action_type
  &date_preset=maximum
  &sort=spend_descending
  &limit=100
  &filtering=[{"field":"spend","operator":"GREATER_THAN","value":"0"}]
```

Supports pagination via `paging.next`.

### 7.2 Extracting Purchase Data from Actions

The `actions` and `action_values` arrays contain different action types. To get purchases:

```python
for action in actions:
    if action["action_type"] == "purchase":
        purchase_count = int(action["value"])

for action_value in action_values:
    if action_value["action_type"] == "purchase":
        purchase_revenue = float(action_value["value"])

roas = purchase_revenue / spend
```

### 7.3 Date Presets

`maximum`, `today`, `yesterday`, `this_month`, `last_month`, `this_quarter`, `last_3d`, `last_7d`, `last_14d`, `last_28d`, `last_30d`, `last_90d`

### 7.4 Filtering Operators

`EQUAL`, `NOT_EQUAL`, `GREATER_THAN`, `GREATER_THAN_OR_EQUAL`, `LESS_THAN`, `LESS_THAN_OR_EQUAL`, `IN`, `NOT_IN`, `CONTAIN`, `NOT_CONTAIN`

---

## 8. Advantage+ Creative Enhancements

### 8.1 Full Creative Features Spec

This goes inside `degrees_of_freedom_spec.creative_features_spec`:

```json
{
  "advantage_plus_creative": { "enroll_status": "OPT_OUT" },
  "creative_stickers": { "enroll_status": "OPT_IN" },
  "cv_transformation": { "enroll_status": "OPT_IN" },
  "enhance_cta": {
    "enroll_status": "OPT_IN",
    "customizations": {
      "text_extraction": { "enroll_status": "OPT_IN" }
    }
  },
  "generate_cta": { "enroll_status": "OPT_IN" },
  "image_animation": { "enroll_status": "OPT_IN" },
  "image_brightness_and_contrast": { "enroll_status": "OPT_IN" },
  "image_templates": { "enroll_status": "OPT_IN" },
  "image_touchups": { "enroll_status": "OPT_IN" },
  "inline_comment": { "enroll_status": "OPT_IN" },
  "pac_relaxation": { "enroll_status": "OPT_IN" },
  "product_extensions": {
    "enroll_status": "OPT_OUT",
    "customizations": {
      "pe_carousel": { "enroll_status": "OPT_OUT" }
    }
  },
  "replace_media_text": { "enroll_status": "OPT_IN" },
  "reveal_details_over_time": { "enroll_status": "OPT_IN" },
  "show_summary": { "enroll_status": "OPT_IN" },
  "show_destination_blurbs": { "enroll_status": "OPT_IN" },
  "audio_composition": { "enroll_status": "OPT_IN" },
  "multi_item_ads_relaxation": { "enroll_status": "OPT_IN" },
  "site_extensions": { "enroll_status": "OPT_OUT" },
  "text_optimizations": {
    "enroll_status": "OPT_IN",
    "customizations": {
      "text_extraction": { "enroll_status": "OPT_IN" }
    }
  },
  "text_translation": { "enroll_status": "OPT_IN" },
  "video_auto_crop": { "enroll_status": "OPT_IN" },
  "video_filtering": { "enroll_status": "OPT_IN" },
  "video_uncrop": { "enroll_status": "OPT_IN" }
}
```

### 8.2 Features with Nested Customizations

Three features have nested `customizations`:
- `enhance_cta` → `text_extraction`
- `product_extensions` → `pe_carousel`
- `text_optimizations` → `text_extraction`

### 8.3 `standard_enhancements` — DEPRECATED

Meta's API **returns** `standard_enhancements` in creative specs but **rejects** it when you try to create/copy with it. Error subcode `3858504`: "Creative should not include standard enhancements."

**Always strip it** before sending payloads.

### 8.4 Discovering New Enhancement Features

Fetch the creative's `degrees_of_freedom_spec` from a template ad, extract the keys from `creative_features_spec`, and diff against your known list:

```
GET /{AD_ID}?fields=creative{degrees_of_freedom_spec}
```

---

## 9. Batch API

### 9.1 Batch Request Format

```
POST https://graph.facebook.com/v24.0
Content-Type: application/x-www-form-urlencoded

access_token={TOKEN}
&batch=[
  {"method":"POST","relative_url":"act_123/advideos","body":"file_url=...&name=..."},
  {"method":"GET","relative_url":"120200123?fields=thumbnails{uri,is_preferred}"}
]
```

**Or using JSON body:**
```
POST https://graph.facebook.com/v24.0/?access_token={TOKEN}
Content-Type: application/json

{
  "batch": [
    {"method":"GET","relative_url":"120200123?fields=thumbnails{uri,is_preferred}"},
    {"method":"GET","relative_url":"120200456?fields=thumbnails{uri,is_preferred}"}
  ]
}
```

### 9.2 Batch Response Format

```json
[
  {
    "code": 200,
    "headers": [...],
    "body": "{\"images\":{\"my-image.jpg\":{\"hash\":\"abc123\"}}}"
  },
  {
    "code": 400,
    "headers": [...],
    "body": "{\"error\":{\"message\":\"Invalid parameter\"}}"
  }
]
```

The `body` field is a **JSON string** (not parsed JSON). Always `JSON.parse(item.body)`.

### 9.3 Batch Limits

- Max ~50 requests per batch
- Max ~10MB per batch payload (for image uploads, be conservative)
- For image uploads: chunk to ~10 images per batch, max 10MB total
- Add a 2-second delay between batch requests to avoid rate limiting

### 9.4 Video Upload via Batch

```json
{
  "method": "POST",
  "relative_url": "act_123/advideos",
  "body": "file_url=https%3A%2F%2F...&name=my-video.mp4"
}
```

Note: the `body` field for POST batch items uses **URL-encoded form data**, not JSON.

---

## 10. Copying Existing Objects

### 10.1 Copy an Ad Set

```
POST /{TEMPLATE_ADSET_ID}/copies
Authorization: Bearer {TOKEN}
Content-Type: application/json

{
  "deep_copy": false,
  "status_option": "ACTIVE",
  "rename_strategy": "NO_RENAME",
  "campaign_id": "120200...",
  "start_time": "2026-04-01T00:00:00-0400",
  "end_time": "2026-04-30T23:59:59-0400"
}
```

**Response:**
```json
{ "copied_adset_id": "120200..." }
```

Then rename:
```
POST /{COPIED_ADSET_ID}
Content-Type: application/json

{ "name": "New Ad Set Name" }
```

### 10.2 Copy an Ad with Creative Overrides

```
POST /{TEMPLATE_AD_ID}/copies
Authorization: Bearer {TOKEN}
Content-Type: application/json

{
  "rename_strategy": "NO_RENAME",
  "status_option": "ACTIVE",
  "adset_id": "120200...",
  "creative_parameters": {
    "object_story_spec": {
      "page_id": "123456789",
      "video_data": {
        "video_id": "120200...",
        "title": "New Headline",
        "message": "New Body Text",
        "call_to_action": {
          "type": "SHOP_NOW",
          "value": { "link": "https://example.com" }
        }
      }
    },
    "degrees_of_freedom_spec": { ... },
    "url_tags": "utm_source=facebook",
    "contextual_multi_ads": { "enroll_status": "OPT_OUT" }
  }
}
```

**Response:**
```json
{ "copied_ad_id": "120200..." }
```

Then rename:
```
POST /{COPIED_AD_ID}
Content-Type: application/json

{ "name": "New Ad Name" }
```

### 10.3 Copy with Deep Rename

```json
{
  "rename_options": {
    "rename_strategy": "DEEP_RENAME",
    "actions": [{"old_name": ".*", "new_name": "New Name"}]
  }
}
```

### 10.4 Cross-Type Creative Swap (Image ↔ Video)

When copying a template ad, you can switch the creative type:

**Image → Video:** Delete `link_data`, create `video_data`:
```json
{
  "video_data": {
    "video_id": "120200...",
    "image_url": "https://...",
    "title": "...",
    "message": "...",
    "call_to_action": { "type": "SHOP_NOW", "value": { "link": "..." } }
  }
}
```

**Video → Image:** Delete `video_data`, create `link_data`:
```json
{
  "link_data": {
    "image_hash": "abc123...",
    "link": "https://...",
    "name": "...",
    "message": "...",
    "call_to_action": { "type": "LEARN_MORE", "value": { "link": "..." } }
  }
}
```

---

## 11. Error Handling & Retries

### 11.1 Error Response Format

```json
{
  "error": {
    "message": "Human-readable error message",
    "type": "OAuthException",
    "code": 190,
    "error_subcode": 463,
    "error_user_title": "Title for user",
    "error_user_msg": "Message for user",
    "fbtrace_id": "..."
  }
}
```

### 11.2 Rate Limiting (HTTP 429)

```typescript
if (res.status === 429) {
  const retryAfter = res.headers.get("Retry-After");
  const waitMs = retryAfter ? parseInt(retryAfter) * 1000 : 5000;
  await sleep(waitMs);
  res = await doFetch(); // retry once
}
```

### 11.3 Transient Server Errors (502/503/504)

Retry up to 2 times with 2-second backoff:

```typescript
const TRANSIENT_CODES = new Set([502, 503, 504]);
if (TRANSIENT_CODES.has(res.status)) {
  for (let i = 0; i < 2; i++) {
    await sleep(2000);
    res = await doFetch();
    if (!TRANSIENT_CODES.has(res.status)) break;
  }
}
```

### 11.4 HTTP 403 on Batch Requests

Can also indicate rate limiting. Treat same as 429.

### 11.5 Error Subcode 1487713 — "Video failed to process"

Often caused by thumbnail URLs that Meta can't access (e.g., expiring Airtable URLs). Fix:
1. Upload thumbnail to `adimages` API
2. Replace `image_url` with `image_hash` in `video_data`
3. Remove `thumbnail_url` from `asset_feed_spec.videos[]` (let Meta auto-generate)
4. Retry the ad creation

### 11.6 Error Subcode 3858504 — "Creative should not include standard enhancements"

Strip `standard_enhancements` from `creative_features_spec` before sending.

### 11.7 Empty Response Bodies

Meta sometimes returns empty responses, especially for large batch requests. Always check:
```typescript
const text = await response.text();
if (!text || text.trim().length === 0) {
  throw new Error("Meta API returned empty response body");
}
const json = JSON.parse(text);
```

---

## 12. Gotchas & Hard-Won Lessons

1. **Budget values are in cents.** $100.00 = `10000`.

2. **`special_ad_categories` is always required** on campaign creation, even if empty `[]`.

3. **`special_ad_category_country`** must be explicitly removed from the payload when empty — don't leave it as `[]` or `undefined`.

4. **ASC+ campaigns use `v23.0`** and are deprecated in `v24.0+`. Also, for ASC+:
   - `targeting_automation` must be completely omitted
   - `is_adset_budget_sharing_enabled` must be completely omitted

5. **`is_adset_budget_sharing_enabled`:** For **ABO** (ad set budget) non-ASC+ campaigns, set explicitly to `true` or `false`. For **CBO** (campaign has `daily_budget` at campaign level), **omit** this field — setting `true` returns error `4834002` ("Cannot use ad set budget sharing with campaign budget").

6. **Form-encoded `POST` and array fields:** When using `data=payload` (not JSON body), send `pacing_type` as a JSON string, e.g. `json.dumps(["standard"])`. A Python list in the dict is not serialized as a Meta array and triggers `(#100) param pacing_type must be an array`.

7. **Video `image_url` and `image_hash` are mutually exclusive.** Meta rejects payloads containing both. Prefer `image_url` and delete `image_hash`.

8. **`standard_enhancements` is deprecated but still returned by Meta.** Always strip it before sending creative payloads.

9. **Image hashes are 32-character hex strings** (e.g., `9f495644042f7f00f52ab72422a9f3fc`).

10. **Video IDs are numeric.** In `asset_feed_spec.videos[]`, `video_id` must be an integer, not a string.

11. **Batch response `body` is a JSON string**, not parsed JSON. Always `JSON.parse()` it.

12. **No `thumbnail_hash` field exists** in `asset_feed_spec.videos[]`. Only `thumbnail_url` works there.

13. **Duplicate assets in `images`/`videos` arrays are rejected.** If the same asset serves multiple placements, merge the `adlabels` onto one entry.

14. **Meta batch API can return empty responses** for large payloads. Keep batches under ~10MB and ~10-50 items.

15. **Meta tokens have no refresh tokens.** Use the `fb_exchange_token` grant to extend to ~60 days. After that, user must re-authenticate.

16. **Ad account IDs must always include `act_` prefix** in API URLs.

17. **Creative fields vary by API version.** Fields like `link_description` may not be valid on sub-objects depending on the version.

18. **`location_types: ["home", "recent"]`** should always be included when using cities, regions, or zip targeting.

19. **Asset customization requires at least 2 rules.** Meta rejects the payload if you only provide 1.

20. **Meta's max image size is 30MB** for ad images.

21. **When copying ads, always delete the template creative's `id`** — you're creating a new creative, not referencing the existing one.

22. **HEVC videos return HTTP 413** on the `/advideos` multipart upload endpoint even when under 200MB. Re-encode to H.264 (`libx264`) before uploading — CRF 23 at 30fps typically reduces file size 60-70%.

23. **Video `status.video_status` must be `ready`** before using in an ad. `processing_phase: complete` alone is not sufficient — the ad creation endpoint returns error subcode `1885252` ("Video not ready for use in an ad"). Poll with 10s intervals until `video_status == "ready"`.

24. **Insights filter `campaign_id` is deprecated.** Use `campaign.id` instead: `[{"field": "campaign.id", "operator": "EQUAL", "value": "120200..."}]`.

---

## 13. Enum Reference

### Campaign Objectives
`OUTCOME_SALES`, `OUTCOME_LEADS`, `OUTCOME_TRAFFIC`

### Bid Strategies
`LOWEST_COST_WITHOUT_CAP`, `LOWEST_COST_WITH_BID_CAP`, `COST_CAP`

### Billing Events
`IMPRESSIONS`, `LINK_CLICKS`, `POST_ENGAGEMENT`

### Optimization Goals
`OFFSITE_CONVERSIONS`, `LANDING_PAGE_VIEWS`, `LINK_CLICKS`, `IMPRESSIONS`, `REACH`, `LEAD_GENERATION`

### Custom Event Types
`PURCHASE`, `ADD_TO_CART`, `INITIATE_CHECKOUT`, `COMPLETE_REGISTRATION`, `LEAD`, `VIEW_CONTENT`, `SEARCH`, `ADD_PAYMENT_INFO`, `ADD_TO_WISHLIST`, `SUBSCRIBE`, `START_TRIAL`

### CTA Types
`LEARN_MORE`, `SHOP_NOW`, `SIGN_UP`, `SUBSCRIBE`, `BOOK_TRAVEL`, `CONTACT_US`, `DOWNLOAD`, `GET_OFFER`, `GET_QUOTE`, `APPLY_NOW`, `BUY_NOW`, `DONATE_NOW`, `ORDER_NOW`, `WATCH_MORE`, `SEND_MESSAGE`, `WHATSAPP_MESSAGE`, `CALL_NOW`, `GET_DIRECTIONS`, `LISTEN_NOW`, `OPEN_LINK`, `REQUEST_TIME`, `SEE_MENU`, `USE_APP`, `INSTALL_APP`, `PLAY_GAME`, `BUY_TICKETS`, `GET_STARTED`, `SEND_WHATSAPP_MESSAGE`, `NO_BUTTON`

### Ad Statuses
`ACTIVE`, `PAUSED`, `ARCHIVED`

### Publisher Platforms
`facebook`, `instagram`, `messenger`, `audience_network`, `threads`

### Facebook Positions
`feed`, `story`, `facebook_reels`, `right_hand_column`, `search`, `marketplace`, `video_feeds`, `instream_video`, `biz_disco_feed`, `profile_feed`, `notification`

### Instagram Positions
`stream`, `story`, `reels`, `explore`, `explore_home`, `profile_feed`, `ig_search`, `profile_reels`

### Messenger Positions
`story`

### Threads Positions
`feed`

### Special Ad Categories
`HOUSING`, `EMPLOYMENT`, `CREDIT`, `ISSUES_ELECTIONS_POLITICS`

### Creative Enhancement Features
`advantage_plus_creative`, `creative_stickers`, `cv_transformation`, `enhance_cta`, `generate_cta`, `image_animation`, `image_brightness_and_contrast`, `image_templates`, `image_touchups`, `inline_comment`, `pac_relaxation`, `product_extensions`, `replace_media_text`, `reveal_details_over_time`, `show_summary`, `show_destination_blurbs`, `audio_composition`, `multi_item_ads_relaxation`, `site_extensions`, `text_optimizations`, `text_translation`, `video_auto_crop`, `video_filtering`, `video_uncrop`

### Account Status Codes
| Code | Meaning |
|---|---|
| 1 | Active |
| 2 | Disabled |
| 3 | Unsettled |
| 7 | Pending review |
| 8 | Pending closure |
| 9 | In grace period |
| 100 | Temporarily unavailable |
| 101 | Closed |

---

## 14. Ad Library API (ads_archive)

The Ad Library API provides programmatic access to ads stored in the [Meta Ad Library](https://www.facebook.com/ads/library). Use this for competitor research, transparency, and ad monitoring — **not** for managing your own ad account.

### 14.1 Endpoint

```
GET https://graph.facebook.com/{VERSION}/ads_archive
```

Same base URL and access token as the Marketing API. Use `v21.0` or newer.

### 14.2 Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `access_token` | string | Meta developer access token |
| `ad_reached_countries` | string | Comma-separated ISO country codes (e.g. `US`, `US,CA,GB`) |
| `ad_delivery_date_min` | string | Start date `YYYY-mm-dd` |
| `ad_delivery_date_max` | string | End date `YYYY-mm-dd` |
| `search_page_ids` **or** `search_terms` | string | Page IDs (comma-separated, max 10) OR keyword search |

You must provide **either** `search_page_ids` or `search_terms`, not both.

### 14.3 Optional Parameters

| Parameter | Values | Description |
|-----------|--------|-------------|
| `ad_active_status` | `ACTIVE`, `INACTIVE`, `ALL` | Filter by ad status; `ACTIVE` = currently running only |
| `ad_type` | `ALL`, `POLITICAL_AND_ISSUE_ADS`, etc. | Ad category |
| `sort_by` | `impressions_high_to_low`, `longest_running`, `most_recent`, `ad_delivery_start_time_ascending`, `ad_delivery_start_time_descending` | Sort order; `impressions_high_to_low` prioritizes top-reach ads |
| `media_type` | `all`, `video`, `image` | Filter by creative media type |
| `fields` | See 14.5 | Comma-separated fields |
| `limit` | 1–1000 | Results per page |

### 14.4 Response & Pagination

Response contains `data` array of ad objects and `paging.next` for the next page. Follow `paging.next` to paginate.

### 14.5 Key Fields (archived-ad)

| Field | Description | Availability |
|-------|-------------|--------------|
| `id` | Library ad ID | All ads |
| `page_id` | Facebook Page ID | All ads |
| `page_name` | Page display name | All ads |
| `ad_creation_time` | UTC creation time | All ads |
| `ad_delivery_start_time` | Delivery start | All ads |
| `ad_delivery_stop_time` | Delivery end | All ads |
| `ad_snapshot_url` | URL to view ad in library (contains media) | All ads |
| `ad_creative_bodies` | Text content | All ads (can cause 500 with pagination) |
| `publisher_platforms` | e.g. Facebook, Instagram | All ads |
| `impressions` | Impression ranges | **POLITICAL_AND_ISSUE_ADS only** |
| `spend` | Spend ranges | **POLITICAL_AND_ISSUE_ADS only** |
| `eu_total_reach` | EU reach | **EU-delivered ads only** |

### 14.6 Gotchas

1. **No impressions/spend for US commercial ads.** Performance metrics are only returned for political/issue ads and EU ads. The `sort_by=impressions_high_to_low` parameter is accepted and may still influence ranking (Meta may use internal data), but the API does not return impression values for non-political/US ads.
2. **Page IDs required.** The API uses `search_page_ids`, not page names. Resolve names via `GET /{username}?fields=id` when the page has a vanity URL.
3. **Media not in API response.** The API returns `ad_snapshot_url` only. To download images/videos, open the snapshot URL (e.g. with Selenium) and extract media from the page.
4. **Pagination + creative fields.** Requesting `ad_creative_bodies` (and related creative fields) with pagination can cause intermittent HTTP 500. Use minimal fields for the main query; fetch creative fields per-ad if needed.
5. **Rate limiting.** Expect 429 responses under heavy use. Honor `Retry-After` header.
