# Veo 3.1 — prompt craft (PARKED)

> **PARKED — Veo 3.1 is not on this API.** There is no Veo route here. Nothing in this file
> is callable today; it is kept **unconverted**, as prompt craft only, until the model ships
> (plan: Track B P3). At that point it earns a real decision-tree row and a body section
> written against the live spec.
> Any route, DTO or field named below belongs to the **upstream fork's API, not this one** —
> do not send them to `api.novoads.ai`. For what you can generate today, use the decision
> tree in [SKILL.md](../../SKILL.md).

**Vendor guide:** [Google Cloud — Ultimate prompting guide for Veo 3.1](https://cloud.google.com/blog/products/ai-machine-learning/ultimate-prompting-guide-for-veo-3-1)

## Checklist

- [ ] Describe scene, action, and **how the shot evolves** over time (first frame → later beats).
- [ ] Specify **style** (film stock, animation, documentary, etc.) if it matters.
- [ ] If using **reference images** or **start/end frames**, say how motion should treat them. (Whatever rules govern them here will be written when the model lands — do not assume this API's Seedance rules carry over.)
- [ ] **ALWAYS** end the prompt with `"No subtitles, no captions, no text overlays."` — Veo 3.1 sometimes burns subtitles into the video if not explicitly excluded.

## Template

```text
{{OPENING_BEAT}}. {{ACTION_OVER_TIME}}. Setting: {{SETTING}}. Camera: {{CAMERA}}. Style: {{STYLE}}. Lighting: {{LIGHT}}. Optional dialogue: {{DIALOGUE}}.
```

## Example

```text
Wide shot of a city rooftop at golden hour; runner ties shoes, then jogs toward camera as the camera tracks sideways. Documentary handheld feel, warm natural light, subtle film grain. No logos on clothing.
```

## Request body

None — see the PARKED note at the top. The upstream fork's field list for this model does not
apply to this API, so there is nothing to document here until the model lands.
