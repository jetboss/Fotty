# PocketBase Web MVP Schema

The Fotty web MVP writes locally first, then attempts authenticated PocketBase sync through `/api/pocketbase/sync`. These collections let the browser MVP share the same account-backed data path as iOS.

## Existing or Required Collections

### `team_follows`

Purpose: tracked teams used for home personalization and future push targeting.

Fields:

- `user`: relation to `users`, required
- `key`: text, required, unique per user
- `teamName`: text, required
- `sportCategory`: text, default `Football`
- `league`: text, optional
- `alertsEnabled`: bool, default `true`
- `createdAtLocal`: text or date, optional

Suggested rules:

- List/view: `user = @request.auth.id`
- Create/update/delete: `user = @request.auth.id`

### `match_reminders`

Purpose: match reminders saved from fixture cards.

Fields:

- `user`: relation to `users`, required
- `key`: text, required, unique per user
- `matchID`: text, required
- `cid`: text, required
- `title`: text, required
- `league`: text, optional
- `sport`: text, optional
- `startsAt`: text or date, required
- `href`: text, required
- `createdAtLocal`: text or date, optional

Suggested rules:

- List/view: `user = @request.auth.id`
- Create/update/delete: `user = @request.auth.id`

### `partner_inquiries`

Purpose: Collab inquiries from venues, clubs, sponsors, and communities.

Fields:

- `user`: relation to `users`, required
- `packageID`: text, required
- `packageTitle`: text, required
- `organization`: text, optional
- `contact`: text, optional
- `region`: text, optional
- `audienceSize`: text, optional
- `matchFocus`: text, optional
- `useCase`: text, optional
- `status`: text, default `new`
- `createdAtLocal`: text or date, optional

Suggested rules:

- List/view: `user = @request.auth.id`
- Create: `user = @request.auth.id`
- Update: admin only, unless the user should be allowed to edit drafts

### `support_pledges`

Purpose: support and payment intent fallback before payment links or subscriptions are live.

Fields:

- `user`: relation to `users`, required
- `plan`: text, required
- `title`: text, required
- `amount`: number, optional
- `contact`: text, optional
- `note`: text, optional
- `status`: text, default `new`
- `createdAtLocal`: text or date, optional

Suggested rules:

- List/view: `user = @request.auth.id`
- Create: `user = @request.auth.id`
- Update: admin only, unless the user should be allowed to edit pledges

## Production Switches

- Set `POCKETBASE_BASE_URL` or `NEXT_PUBLIC_POCKETBASE_URL`.
- Keep `/api/pocketbase/auth` active against the real `users` collection.
- Add payment URLs for support packages when ready.
- Add a server push job later that reads `team_follows` and `match_reminders`; the browser MVP already captures the required intent.
