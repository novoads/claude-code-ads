# Changelog

What changed in the **pack**: the skills, the scripts, the setup path and the docs.

This is not an API changelog. When a file here and the deployed spec disagree, the spec wins,
and [`GET /v1/openapi.json`](https://api.novoads.ai/v1/openapi.json) is where its own history
lives.

## v1.0.0 (2026-08-12)

First tagged release. Eleven skills on one executable path (REST plus `NOVOADS_API_KEY`), nine
models, and a live estimate in front of anything that spends. Everything below landed before the
tag, in the order it shipped.

### 2026-08-12

- The README opens on proof and one action: a gallery of real output with the asks that produced
  it, and the install prompt above the fold (#76, #77).
- Corrected two claims that had gone false: the draft tier is real, and the image estimate does
  read the prompt (#75).

### 2026-08-10

- `novoads-image-to-motion`, a transport-only port (#71).
- Competitor sweeps run in parallel, and land as a contact sheet you can click and toggle rather
  than a list you scroll (#58 through #65).
- A claim in a render now needs a true one of ours behind it, and a testimonial needs a person
  (#66, #67, #68).
- The placeholder lint refuses a prompt carrying scaffolding before it charges, and reads the
  prompt it is actually about to send (#70, #72).

### 2026-08-09

- "Clone this ad" returns the ad, and stops re-asking who you are: brand context is read once and
  reused (#52).
- The video cloner was unreachable through its own description, and the pair was misnamed. Both
  fixed (#54, #55).

### 2026-08-08

- `spy-competitor-ads`: find a competitor's live ads through the Novoads API (#48).
- The pack runs **one** executable path, REST plus `NOVOADS_API_KEY`, with a CI ratchet that keeps
  the docs from drifting off it (#50).
- One Pixar skill and one clay skill, both REST (#49).
- Setup stops asking the agent to keep things from you, opens `.env`, and names everything the
  pack does (#51).
- Per-model prompt caps match the deployed spec, checked by script (#44).
- The setup close rides the script's stdout, where the clone flow can see it (#46).

### 2026-08-07

- Adopted the `claude-code-ads` identity (#32).
- Skills survive a solo install from skills.sh, not just a full clone (#33).

### 2026-08-05 to 2026-08-06

- The video clone chapter, evals first (#17), then the image clone chapter to match (#25, #26).
- The two Pixar ad skills, and the clay storyboard skill (#20, #23, #27).
- `craft.md`: one home for the three rules that kept getting recopied into every skill (#30).

### 2026-08-04

- `broll-overlay` and `music-mix`, both evals-first and live-validated.
- Transcripts come from the API, which retired the local whisper prerequisite (#16).
- Per-model reference caps, a sanctioned batch clone, and a standing drift alarm (#14, #15).

### 2026-08-02 to 2026-08-03

- First public commit. Veo 3.1 and Sora 2 un-parked (#1), and the fixes a genuinely fresh clone
  turns up (#2).
