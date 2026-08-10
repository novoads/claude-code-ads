# spy-competitor-ads — error codes

Read this when a call fails. Branch on `error.code`, never on the message: the codes are the
contract and the prose is not.

## Errors: branch on `error.code`, never on the message

These are the codes this surface actually emits. `error.code` is the string in the JSON envelope;
the HTTP status is shown beside it because both are worth logging.

| `error.code` | Status | What it means | What to do |
|---|---|---|---|
| `invalid_input` | 400 | Either this deployment does not offer sweeps (the message names what it does offer), or a field is wrong: `mediaType` missing, `country` not alpha-2 or `ALL`, `count` outside 1..20, `query` outside 2..200 | Read the message; it says which. Fix the field, or stop |
| `insufficient_credits` | 402 | Carries `required` and `available`, in credits | Report both and the top-up path. Do not retry |
| `provider_failed` | 502 | The Ad Library query failed, timed out, or came back in a shape the server would not trust. **The credits were refunded** — the message says so, and says "queued" instead if the refund has not landed yet | This is NOT an empty result. Say the scrape failed and the charge was returned. Retry once; if it fails again, stop and say the source is down |
| `rate_limited`, `error.details.reason` = `competitor_ads_concurrency_limit` | 429 | The SWEEP ceiling: you already have the maximum number of sweeps in flight for this organization. Its own queue, counted separately from renders | Wait about ten seconds — `error.details.retryAfterSeconds` and the `Retry-After` header carry the number — then retry. Do not lengthen the backoff; a slot frees when a sweep returns |
| `rate_limited`, `error.details.reason` = `concurrency_limit` | 429 | The RENDER budget, not this endpoint's: the organization has too many video generations in flight. A sweep does not consume one and cannot cause this | Not your queue. Say what is actually blocked, and wait on the renders — sweeping again will not clear it |
| `rate_limited`, any other reason | 429 | Per-key or per-org REQUEST rate, or another endpoint's ceiling | Back off by `Retry-After` and retry. Different problem, different fix |
| `forbidden`, `error.details.reason` = `plan_required` / `subscription_inactive` | 403 | Good key, no live subscription | Say which. It is not a key problem |
| `unauthorized` | 401 | The key is wrong, revoked, or from another account | Stop. Do not retry with the same key |

There is **no `vendor_error` code** on this API. A refunded vendor failure arrives as
`provider_failed`; `vendor_error` is internal vocabulary and branching on it matches nothing, which
sends the whole case into unknown-error handling and re-fires a sweep that pays the fee twice.

**A call that times out on your side is not a call that failed.** There is no idempotency on
sweeps, so re-firing can pay twice. The sweep is recorded as a generation: list your recent
generations and look for it before you retry anything (its `prompt` is the query you sent, which is
how you recognise it). Note that the generation record is a receipt, not a mirror — it carries no
`outputUrl` at all, there is nothing to watch or download, and the media lives only in the
response you already have. That is the whole reason step 4 downloads first.

