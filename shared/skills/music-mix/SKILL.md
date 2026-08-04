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
turned down by the platform, an output path that would overwrite one of its own inputs,
and — the sneakiest one — a bed so quiet it is not in the mix at all.

That last one is caught **before** the render, not after, and it is worth knowing why:
the output's audio is re-encoded on every path, so a finished file with no music in it
looks exactly like one with music. The script instead measures the music track's own
loudness up front and refuses a silent track or a gain that would put the bed below
audibility. A verifier cannot do that job; do not ask it to.

**Escape hatch:** if a request genuinely doesn't fit this model — music that must hit a
specific cut point, a track that needs an intro trimmed off the front, stems, a
mid-video music change — say so and ask the user how to proceed. Do not improvise
around the script.

## Running it

```
python3 scripts/music_mix.py video.mp4 music.mp3 out-lofi-warm.mp4
```

- `--music-gain DB` — bed level, default −18 dB, range ±60. The main knob between
  variants, and the first one to reach for when loudness verification fails.
- `--no-duck` — flat bed, no ducking. For a video with no voiceover.
- `--dry-run` — validate and print the plan, render nothing.
- `--verify-only OUT --video INPUT` — re-check any existing output, including one from
  an old session. Standalone: mixing it with render arguments is an error.

**Report the script's verification line verbatim** — the measured loudness and true
peak, not a paraphrase. Do not upgrade it: it establishes duration, an un-re-encoded
picture, rebuilt audio and the loudness envelope, and says nothing about how the bed
*sounds*. Exit codes: `2` validation, `3` render, `4` verification. A nonzero exit is a
real failure — surface it, don't retry blindly.

**The refusals worth recognising**, so you fix the input instead of retrying:

| Message | What to do |
|---|---|
| `music is Xs, video is Ys — the track is too short` | Get a longer track. Never loop or pad. |
| `music track is silent` / `music inaudible at these gains` | Wrong file, or `--music-gain` is too low. |
| `input voice is silent/near-silent` | This is not a music-bed job; the video needs a soundtrack. |
| `has N audio streams` | Pick one voice track with ffmpeg first — the script will not guess. |
| `output ... is the same file as the video` | The output path aliases an input (hardlink, symlink, or a case-variant name on macOS). Choose a new name. |
| `master gain clamped` | The input is more than 30 dB off target; fix its level upstream. |

## Evals

`EVALS.md` defines the five scenarios this skill is held to (MM1–MM5).
`scripts/test_music_mix.py` implements all five mechanically against synthetic fixtures,
in 15 cases — run it after touching the script.
