# RunsByIP — App Store Screenshot Generator

Remotion-based pipeline that composites real simulator captures onto a
branded marketing background (dark + orange `#F97316`) and renders App Store
screenshots at the exact sizes Apple requires.

## Output

Six stills render into `out/`:

| File | Size | Apple class |
| --- | --- | --- |
| `sessions-list-69.png` | 1290×2796 | iPhone 6.9" (16 Pro Max) |
| `session-detail-69.png` | 1290×2796 | iPhone 6.9" |
| `chat-69.png` | 1290×2796 | iPhone 6.9" |
| `sessions-list-65.png` | 1242×2688 | iPhone 6.5" (11 Pro Max) |
| `session-detail-65.png` | 1242×2688 | iPhone 6.5" |
| `chat-65.png` | 1242×2688 | iPhone 6.5" |

## Drop in real captures

1. Capture the three screens from the iOS simulator (Device → Screenshot,
   or `⌘S`). Any iPhone simulator size works — the frame crops with
   `object-fit: cover`, so aspect ratio close to 19.5:9 is ideal.
2. Overwrite the files in `public/captures/`:
   - `public/captures/sessions-list.png`
   - `public/captures/session-detail.png`
   - `public/captures/chat.png`
3. Re-render:

   ```bash
   npm run render-all
   ```

   Fresh stills land in `out/`.

## Customize headlines

Edit the `SCREENS` array in `src/Root.tsx`. Each entry controls the
`headline` and `subhead` for both the 6.9" and 6.5" variant of that screen.

## Preview interactively

```bash
npm run studio
```

Opens Remotion Studio where you can tweak `Screenshot.tsx` and see both
sizes live before committing to a render.

## Render a single composition

```bash
npx remotion still src/index.ts chat-69 out/chat-69.png
```

Composition IDs: `sessions-list-69`, `session-detail-69`, `chat-69`,
`sessions-list-65`, `session-detail-65`, `chat-65`.

## Reset placeholders

The initial `public/captures/*.png` files are 1×1 dark placeholders written
by `scripts/init-placeholders.mjs`. To regenerate them (e.g. after
experimenting):

```bash
node scripts/init-placeholders.mjs --force
```
