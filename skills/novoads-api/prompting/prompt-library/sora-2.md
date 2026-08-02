# Sora 2 — prompt craft (PARKED)

> **PARKED — Sora 2 is not on this API.** There is no Sora route here. Nothing in this file
> is callable today; it is kept **unconverted**, as prompt craft only, until the model ships
> (plan: Track B P3). At that point it earns a real decision-tree row and a body section
> written against the live spec.
> Any route, DTO or field named below belongs to the **upstream fork's API, not this one** —
> do not send them to `api.novoads.ai`. For what you can generate today, use the decision
> tree in [SKILL.md](../../SKILL.md).

**Vendor guide (read for craft):** [OpenAI — Sora 2 prompting guide](https://developers.openai.com/cookbook/examples/sora/sora2_prompting_guide)

## Checklist (after reading the vendor guide)

- [ ] Clear subject and setting; camera behavior described (not just “cinematic”).
- [ ] Motion: what moves, what stays stable across the clip.
- [ ] Lighting and style named explicitly if important.
- [ ] If using a reference image, describe how motion should relate to the reference.

## Template

```text
{{HOOK_OPEN}}. {{SUBJECT}} in {{SETTING}}. Camera: {{CAMERA_MOVE}}. Lighting: {{LIGHTING}}. Style: {{STYLE}}. Audio mood: {{AUDIO_MOOD}}. End on {{ENDING_IMAGE}}.
```

## Example (replace IDs in JSON separately)

```text
A skincare founder holds the bottle to camera in a bright bathroom, morning light through blinds. Slow push-in, shallow depth of field. Warm, trustworthy, no medical claims. Soft upbeat ambient. End on product and smile.
```

## Request body

None — see the PARKED note at the top. The upstream fork's field list for this model does not
apply to this API, so there is nothing to document here until the model lands.
