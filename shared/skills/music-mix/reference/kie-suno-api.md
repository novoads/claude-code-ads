# KIE Suno API — generating a music bed

> **This is the FALLBACK path, not the default one.** Since 2026-08-04 Novoads renders
> music first-party: `POST /v1/music` on the `$NOVOADS_API_KEY` this pack already holds,
> priced by `POST /v1/estimates` `{"kind":"music"}`, same two tracks, one bill, no
> second account. See `SKILL.md` § "Sourcing the music" (a) and the `novoads-api`
> skill's `reference.md` § `POST /music`. Reach for the direct KIE calls below only when
> there is no `$NOVOADS_API_KEY`, or when music is genuinely off on that deployment —
> which you confirm with the free, keyless `GET /v1/openapi.json`: no `/music` path
> means off, a `/music` path means your request was malformed. The provider figures in
> this file are a **dated measurement record of what KIE charges us**, not a price for
> anyone to quote.

**Verified live 2026-08-04.** One instrumental generation was run end to end against the
real endpoint; every shape below is copied from that exchange, not from the docs.
Docs: <https://docs.kie.ai/suno-api/quickstart>

Auth: `Authorization: Bearer $KIE_API_KEY` — **a second credential this pack does not
set up and most users will not have.** Do not print it.

## Cost, measured

Credit balance before `76012.57`, after `76000.57` → **12 credits for one Generate
Music request**, which returned **two tracks**. At $0.005/credit that is **$0.06 per
request, ~$0.03 per usable track**. Balance is readable at
`GET /api/v1/chat/credit` → `{"code":200,"msg":"success","data":76000.57}`.

A request rejected at validation charges **nothing** — the balance was unchanged after
the failed first attempt below.

## Generate

`POST https://api.kie.ai/api/v1/generate`

```json
{
  "prompt": "warm lofi hip-hop instrumental, calm, mellow rhodes and soft vinyl crackle, no vocals, suitable as a 15-second ad background bed",
  "customMode": false,
  "instrumental": true,
  "model": "V5",
  "callBackUrl": "https://example.com/kie-callback-unused"
}
```

**`callBackUrl` is required in practice, and the docs say it is optional.** Omitting it
returns HTTP 200 with an error body — this cost the first attempt:

```json
{"code": 422, "msg": "Please enter callBackUrl.", "data": null}
```

Polling works fine, so a placeholder URL plus polling is a legitimate pattern; the field
just has to be present. **Always check `body.code == 200`, not the HTTP status** — this
API returns errors as HTTP 200 with a non-200 `code`.

Success:

```json
{"code": 200, "msg": "success", "data": {"taskId": "ff6803ba4e9d1d82172ae3ec1fdf3375"}}
```

`model` accepts `V4`, `V4_5`, `V4_5PLUS`, `V4_5ALL`, `V5`, `V5_5`. With
`customMode: false` only `prompt` matters (max 500 chars); `style` and `title` are
Custom Mode only. `instrumental: true` is what you want for a bed.

## Poll

`GET https://api.kie.ai/api/v1/generate/record-info?taskId=<taskId>`

Observed status progression on a 15s poll interval, **~75 seconds** from request to
`SUCCESS`:

`PENDING` → `TEXT_SUCCESS` → `TEXT_SUCCESS` → `FIRST_SUCCESS` → `SUCCESS`

Terminal failure values: `CREATE_TASK_FAILED`, `GENERATE_AUDIO_FAILED`,
`SENSITIVE_WORD_ERROR`, `CALLBACK_EXCEPTION`.

`data` carries `taskId, parentMusicId, param, response, status, type, operationType,
errorCode, errorMessage, createTime`. Tracks live at `data.response.sunoData[]`, each
with:

```
id, audioUrl, sourceAudioUrl, streamAudioUrl, sourceStreamAudioUrl,
imageUrl, sourceImageUrl, prompt, modelName, title, tags, createTime, duration
```

## Downloading — the 403 gotcha

`audioUrl` points at `https://tempfile.aiquickdraw.com/r/<hash>.mp3`. That CDN
**403s a default urllib/python User-Agent**. Send a browser UA and it succeeds:

```python
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 ..."})
```

The host is named `tempfile` — treat the URLs as short-lived and download immediately.

## What came back

Two tracks from the one request, `modelName: chirp-crow`, both titled
"Late Train Receipt": **89.24s** and **127.72s**, MP3 48 kHz stereo ~184 kbps.
Both are far longer than a 15s ad, so `music_mix.py` trims and fades rather than ever
hitting its too-short error. Verified usable: mixing the 89s track under a 12s fixture
produced an output that passed every check the script makes — duration unchanged, video
packets identical, −14.0 LUFS, −12.6 dBTP. Those checks do **not** establish that the bed
is audible in the mix (nothing after the render can — see EVALS.md MM5); that the track
carries real audio is established before the render, from its own measured loudness.

Saved to `outputs/music-samples/` — **gitignored**, audio is never committed.
