# AI usage coverage

The agent that runs a task and the provider serving its model are different things. OpenCode may call OpenRouter, GroqCloud or another service. Vorssaint preserves the service identifier OpenCode records and displays it separately from the calling agent and exact model ID.

## What the local readers can establish

The Model providers card follows Today, 7 days or 30 days. It shows every observed service/model combination and its deduplicated request count from the enabled agents on this Mac. It scrolls rather than silently dropping rows after the first three. Provider meters show each service's share of requests in the selected period; model bars show the share within that service. These are local request shares, never account allowance percentages. Meters, rounded totals, chips and service colours follow the existing AI Agents components, and the same service colour is used in the Models card. The existing Models card also retains separate rows when the same model is reached through different services.

OpenCode 1's `providerID`/`provider_id` and OpenCode 2's nested model provider are read from the existing read-only database projection. Recognized IDs receive familiar display names; custom IDs remain visible. A missing ID is shown as unrecorded and is never inferred from the model vendor. OpenCode metadata remains in memory and is excluded from the persisted usage cache.

**Marked free** counts only routes whose model IDs explicitly denote free models: OpenRouter's `:free` models and `openrouter/free`, and OpenCode Zen's `-free` models. It is not a count of every request covered by a free plan. Zero cost, an unknown price, a subscription or the use of a locally hosted model do not establish a free tier or remaining allowance.

Request counts use the app's existing local calendar periods. They are not UTC account reset windows, premium-request billing units, account-wide totals, remaining credits or percentages of a provider allowance. Claude and Codex's existing reported allowance percentages remain in the Limits cards.

## Provider decisions

| Service | Coverage in this change | Account allowance source and limitations |
| --- | --- | --- |
| Antigravity | Named attribution if its provider/plugin ID is recorded by OpenCode. | Direct app quotas require its signed-in local service or a Google OAuth integration; not available from an ordinary OpenCode response. No direct Antigravity reader is claimed. |
| GitHub Copilot | Existing direct Copilot CLI/app activity and model counts, plus named attribution through OpenCode. | Account premium/chat allowances require a signed-in account check. Model responses are not necessarily premium requests: model multipliers and plan rules differ. No percentage is inferred from CLI activity. |
| Cursor | Named attribution if a Cursor provider/plugin ID is recorded by OpenCode. | A direct Cursor account reader needs its app authentication/usage service. An OpenCode trace alone cannot report Cursor subscription consumption. No direct Cursor reader is claimed. |
| GroqCloud | Named attribution, exact models and observed request counts through OpenCode. | Groq publishes organization/model-specific request and token limits in response headers. OpenCode's stored usage rows do not retain those headers; a generic API request would not measure the same model's allowance. |
| OpenRouter | Named attribution, exact model counts and explicitly free route counts. | Its authenticated key endpoint exposes credit usage and applicable budgets. Those are spending budgets, not the remaining free-model request count. Free-model daily limits also depend on account history; no fixed maximum is assumed. |
| Mistral API | Named attribution and observed model/request counts through OpenCode. | Account tier, model rate limits and spend must come from the account; a model's zero reported cost is not an account quota. |
| Cloudflare Workers AI | Named attribution and observed model/request counts through OpenCode. AI Gateway is shown separately. | Workers AI's free allocation is measured in neurons, not requests. A neuron allowance percentage cannot be reconstructed from token/request counts alone; account analytics are needed. |
| Grok Build | Named attribution when the recorded ID explicitly identifies Grok Build. | The xAI inference API is a separate service and is labelled xAI API. Grok Build account limits require its own account/CLI integration. |
| Ollama Cloud | Named attribution for an explicit cloud provider ID; generic Ollama remains labelled Ollama. | A generic Ollama provider can target a local or remote endpoint, so it is not automatically called cloud usage. Cloud subscription consumption needs an authenticated account source. |

Aliases and custom provider IDs are evidence from the calling agent, not verification of an account or endpoint. A provider's absence means the enabled local readers have not recorded it; this does not mean it has not been used elsewhere.

## Account connection boundary

The local coverage change does not read credentials, import browser cookies, start billable inference requests or send usage anywhere. Adding account-wide checks needs an explicit, separate opt-in connection for each supported service. This first change is deliberately limited to local counts and attribution; account connections are a separate follow-up.

For connected quotas, retain the provider's units, scope, reset window, observation time and failure state. Show a percentage only when that source supplies a valid numerator and denominator or an authoritative percentage. OpenRouter key spend, Groq model rate limits and Cloudflare neurons must never be relabelled as the same kind of free-request allowance.

## Sources checked

- [Groq rate limits and response headers](https://console.groq.com/docs/rate-limits)
- [OpenRouter limits and API key budgets](https://openrouter.ai/docs/api/reference/limits)
- [Cloudflare Workers AI limits](https://developers.cloudflare.com/workers-ai/platform/limits/)
- [Ollama Cloud and its API authentication](https://docs.ollama.com/cloud)
- [GitHub Copilot requests](https://docs.github.com/en/copilot/concepts/billing/copilot-requests)
- [CodexBar's existing provider integrations](https://github.com/steipete/CodexBar/tree/main/Sources/CodexBarCore/Providers), used to assess the account/authentication work needed for Antigravity, Cursor, Copilot, Grok and Ollama; no implementation is copied.

Dynamic Island hover and expansion are assessed separately; this change does not port that interaction.
