# Sure contract baseline

## Supported upstream revision

During the developer and TestFlight phase, this client targets Sure `main` at:

- Commit: `5594f8bc94c8e659838cac70d826bbcaeaa3bae2`
- Upstream commit time: 2026-08-28 06:57:50 UTC
- Commit subject: `fix(holdings): an outbound transfer must not clear a cost basis (#3237)`

Permalinks for the contract sources used by this baseline:

- [OpenAPI](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/openapi.yaml)
- [Client architecture](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/clients.md)
- [Transaction API](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/transactions.md)
- [Chat API](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/api/chats.md)
- [AI architecture](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/hosting/ai.md)

This is a deliberate compatibility pin, not a claim that Sure has a versioned
API. Backward compatibility with older self-hosted revisions is not required
yet. The app should nevertheless tolerate additive optional response fields.

## Current client policy

- Sure remains the system of record for financial data and calculations.
- Financial features are read-only. Authentication/session and APNs
  subscription lifecycle operations may write infrastructure state.
- Preserve the existing API-key and Passkey OAuth behavior until the dedicated
  authentication step. Do not mix an authentication migration into API typing.
- Prefer documented typed endpoints. In particular, migrate insight loading to
  the documented `/api/v1/insights` operation during the typed API work instead
  of prompting chat to return tool JSON.
- Handle collection pagination explicitly when the endpoint supports it.
- Treat preview-feature 403 responses separately from invalid credentials.
- Keep wire DTOs, financial domain types, and SwiftUI presentation types
  separate.

## Transaction product behavior

The first production transaction surface remains read-only:

- Account selection shows transactions belonging to that account from the
  rolling last 31 days.
- Overview Recent activity opens transactions across accounts from the rolling
  last 7 days.
- Foundational work should not redesign existing screens. Only the navigation,
  loading, empty, and error states required by these flows may change visually.

Date windows must be calculated through an injected calendar/clock so boundary
behavior is deterministic and testable. The typed transaction mapping must
retain the account identifier needed for account filtering.

## Known migration gaps

The current client predates this baseline and is not yet contract-verified:

- `SureAPIClient` uses permissive `JSONSerialization` and recursive key lookup.
- Collection pagination is not followed.
- Missing server identifiers and dates can become random/local fallback values.
- Insight retrieval currently creates a chat and asks it to return tool JSON.
- Budget-category routing and payloads still need reconciliation with the pinned
  OpenAPI document.
- Financial values currently use `Double` and do not preserve currency in the
  domain model.
- Current OAuth behavior remains intentionally deferred until the authentication
  migration step.

These gaps are migration inventory, not supported alternate contracts.

## Updating the pin

Adopt a newer Sure `main` revision deliberately:

1. Record the new full commit SHA and timestamp here.
2. Review relevant OpenAPI, client, transaction, chat, authentication, insight,
   and preview-feature changes between the two pins.
3. Update sanitized response fixtures and their provenance notes.
4. Update typed DTOs, endpoints, and compatibility policy together.
5. Run contract tests plus iOS, macOS, and Watch builds before committing.

Do not silently move this pin as part of unrelated feature work.
