---
name: music-mix
description: >-
  Lays a music bed under a finished video — the music is trimmed and faded to the
  video's exact length and ducks beneath the voice, while the video stream is copied
  untouched. Use when the user asks to add music, add a background track, add a music
  bed or soundtrack, or asks for something like "make a lofi mix of this": "put music
  under this ad", "add a background track", "give me a couple of music versions".
  Entered from a finished cut — captions already burned is the preferred input, not a
  problem. It never edits the picture and never changes the video's length.
---

# Music mix

Puts a music bed under a finished video. The bed is trimmed to the video's exact
duration, faded out at the tail, and ducked under the voice. This is the last step of
the pack: base video → b-roll overlay → burned captions → **music**.

Mixing mechanics live entirely in `scripts/music_mix.py`. This file is judgment only —
when to enter, what track to pick, where the music comes from, what the user sees.

## Entry condition

**A finished video the user has signed off on.** Captions already burned in is the
preferred input, because music is genuinely the last thing that happens.

That is safe because the script copies the video stream packet for packet (`-c:v copy`)
and verifies afterwards that the output's video packets hash identical to the input's —
so burned captions come through bit-exact, not "re-encoded but probably fine".

If the cut is still moving, wait. Remixing is cheap; re-rendering the pipeline is not.

## Track judgment

- **Match the genre to the ad's mood, not to your taste.** Calm skincare and a punchy
  supplement ad do not want the same bed. Read the script's tone first.
- **Lofi is the default** — it is what the reference edit used, and it sits under a
  talking head without competing with it. Depart from it deliberately, and say why.
- **Always produce 2–3 named variants.** The reference edit shipped a `final-mixes`
  folder holding `lofi-jazzy` and `lofi-warm` versions of the same cut. Vary the track
  or the `--music-gain`, name them for what they are, and let the user pick. Once the
  video is rendered, each extra mix costs one ffmpeg pass and no credits — there is no
  reason to present one option.
- **Instrumental only.** Lyrics compete with the voiceover for the same attention.

## Sourcing the music

**Verified live 2026-08-04** — the KIE path below was run end to end; request/response
shapes, the required-field gotcha and the measured cost are in
`reference/kie-suno-api.md`.

**(a) A file the user supplies.** Always allowed, no questions. Licensing is theirs.

**(b) Generated via the KIE Suno API.** `$KIE_API_KEY` is already in the shell env.
Docs: <https://docs.kie.ai/suno-api/quickstart>. Generate Music costs **12 KIE credits
≈ $0.06 per request** (1 KIE credit = $0.005) and returns two tracks. Supports Suno
V5/V5.5; use instrumental mode for beds. See the reference file before writing any call
— `callBackUrl` is required in practice despite being documented as optional, and
errors arrive as HTTP 200 with a non-200 `code`.

**(c) The licensing tradeoff — surface it, do not decide it.** Commercial rights for
Suno-via-reseller output are legally murky. Suno's own commercial license requires a
paid Suno plan, which going through a reseller does not give the user, and major-label
litigation against Suno was still ongoing as of mid-2026. For client-facing or
paid-media deliverables, prefer a licensed source: **ElevenLabs Music v2** trains on a
licensed-only catalog and grants full commercial rights at roughly **$0.40/min** via
API, or use a licensed library. For internal tests and concepting, the KIE path is
fine. **State this tradeoff once, plainly, and let the user choose.**

## Hard rule: mixing always goes through the script

Never hand-write mixing ffmpeg for this task. `music_mix.py` owns validation, rendering
and verification, and it fails loudly on what fails silently by hand: a track shorter
than the video, a re-encoded picture, a duration that drifts, loudness that will get
turned down by the platform, and — the sneakiest one — an output that is just a copy of
the input with no music in it at all.

**Escape hatch:** if a request genuinely doesn't fit this model — music that must hit a
specific cut point, a track that needs an intro trimmed off the front, stems, a
mid-video music change — say so and ask the user how to proceed. Do not improvise
around the script.

## Running it

```
python3 scripts/music_mix.py video.mp4 music.mp3 out-lofi-warm.mp4
```

- `--music-gain DB` — bed level, default −18 dB. The main knob between variants.
- `--no-duck` — flat bed, no ducking. For a video with no voiceover.
- `--dry-run` — validate and print the plan, render nothing.
- `--verify-only OUT --video INPUT` — re-check any existing output, including one from
  an old session.

**Report the script's verification line verbatim** — the measured loudness and true
peak, not a paraphrase. Exit codes: `2` validation, `3` render, `4` verification. A
nonzero exit is a real failure — surface it, don't retry blindly.

## Evals

`EVALS.md` defines the five scenarios this skill is held to (MM1–MM5).
`scripts/test_music_mix.py` implements all five mechanically against synthetic fixtures
— run it after touching the script.
