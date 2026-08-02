# Kling 3.0 — prompt craft (PARKED)

> **PARKED — Kling 3.0 is not on this API.** There is no Kling route here, and no b-roll or
> scene endpoint either. Nothing in this file is callable today; it is kept **unconverted**,
> as prompt craft only, until the model ships (plan: Track B P3). At that point it earns a
> real decision-tree row and a body section written against the live spec.
> Any route, DTO or field named below belongs to the **upstream fork's API, not this one** —
> do not send them to `api.novoads.ai`. For what you can generate today, use the decision
> tree in [SKILL.md](../../SKILL.md).

**Vendor guide:** [Kling — video model user guide](https://kling.ai/quickstart/klingai-video-3-model-user-guide)

## Checklist (from Kling guide habits)

- [ ] Subject, environment, and **motion path** described clearly.
- [ ] Separate **style** vs **content** when the guide recommends it.
- [ ] If using reference or start frames, say how motion should treat them.

## Template

```text
{{SUBJECT}}. {{ACTION_MOTION}}. Environment: {{ENV}}. Camera: {{CAM}}. Mood: {{MOOD}}. Avoid: {{NEGATIVE}}.
```

## Example

```text
Coffee pours in slow motion into a ceramic mug on a wooden counter, steam rising. Soft window light, shallow depth of field, calm ASMR pacing. No text overlays.
```

## Request body

None — see the PARKED note at the top. The upstream fork reached Kling-style output through
b-roll and scene DTOs; neither those DTOs nor those endpoints exist on this API, so there is
nothing to document here until the model lands.
