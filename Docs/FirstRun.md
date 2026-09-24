# First-run launch hero

On a fresh iPhone install with no configured Sure connection, the app opens a
full-screen launch hero before the tabs. The hero implements the "Lake + chart"
direction from the Claude Design handoff (`First Run.html`): a calm lake photo
with a tilted stack of glossy chart cards, and two swipeable pitches.

- **Wallet pitch** ("On this iPhone"): the button requests FinanceKit access
  through `AppleCardConnectionStore.connect()`. Granting access closes the hero
  on Overview, where the local Wallet spending comparison is the reveal.
  Choosing "Don't Share" returns to the hero on the demo pitch.
- **Demo pitch** ("Live demo"): closes the hero and opens Connection Settings on
  the default `https://demo.sure.am` server. Demo reads still go through
  `BackendAccessGate`; no pre-subscription demo exception exists yet.

A device with FinanceKit opens on the Wallet pitch and flips once to the demo
after five seconds; otherwise the order is reversed and the Wallet pitch
explains what it would show. The automatic flip stops as soon as the person
swipes or taps a page dot, and never runs with VoiceOver on. Completion is
stored as `sureFirstRunCompleted`, so the hero appears once.

## Playing with the options

All copy lives in `App/Features/FirstRun/FirstRunCopy.swift`, keyed by
`FirstRunCopyVariant` (the design's A, B and C directions):

| Variant | Wallet headline | Demo headline |
| --- | --- | --- |
| `instantReveal` (default) | See where your money went this month. | A real month of money, made clear. |
| `storyCards` | Your month, in three taps. | Three cards. One real month of money. |
| `heroOverview` | How’s September going? | Meet a year of real money. |

Choose a variant and region without code changes using launch arguments in the
scheme's **Arguments Passed On Launch**:

```text
-sureFirstRunVariant storyCards
-sureFirstRunRegion UK            # US, UK or other
-sureFirstRunAlwaysShow YES       # show even after completion or sign-in
```

Debug builds also show a slider button in the hero's top corner that switches
variant and region in place.

## Regions

`FirstRunRegion` resolves from the device locale (US, UK, other) and selects a
`FirstRunMarket`: the Wallet sources named in the copy, the products listed when
Wallet is unavailable, and the showcase artwork (`FirstRunShowcase`). Every
region currently returns the same US content. To localize a market, add a
`FirstRunMarket` for it in `FirstRunMarket.market(for:)`.

## Artwork and backdrop

The chart cards are drawn natively from `FirstRunShowcase` sample figures, the
equivalent of marketing screenshots. They are labeled as illustrations for
VoiceOver and never shown as account data.

The bundled `FirstRunBackdrop` is [Moraine Lake, photographed by Gorgo](https://commons.wikimedia.org/wiki/File:Moraine_Lake_17092005.jpg)
and released into the public domain by its author. The original 2048 × 1536
photo is cropped to fill the screen, with a gradient behind the pitch copy.

## Not yet implemented

The design's three post-tap reveals (A: in-place headline answer, B:
auto-advancing story cards, C: dark hero collapsing into Overview) and its
"Keep exploring / Connect your Sure account" choice are not built. Today both
paths hand off to existing screens as described above.
