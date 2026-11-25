# Correctness before performance

Apply the checks relevant to the proposed optimization. They are failure probes,
not a universal refactor checklist.

## Derived data and identity

A stable item ID identifies a row; it does not mean the row’s values are unchanged.
Equality used to skip rendering must cover relevant value-semantic inputs and
must not suppress changed labels, scores, availability, selection or behavior.
Avoid an equality wrapper when its dependencies cannot be represented safely.

If moving a transformation out of rendering, identify who owns it and every
input that invalidates it. Check an initially populated collection, initially
empty data followed by loading, same-ID field changes, reorder, removal and
relevant locale/time changes. Updating an initially empty cache only on a later
change can lose the first populated render. A generic computed property in a
model is not automatically cheaper; inspect when it is called.

Use view state for view-owned lifecycle, not as an arbitrary memoization cache.
Prefer the existing model/projection owner when appropriate. Do not cache
time-sensitive status indefinitely or replace truthful live state with a guess.

## Concurrency and cancellation

An async function is not proof its synchronous work runs off the main actor.
Verify isolation and call-site behavior before claiming an await fixes a hang.
Off-main preprocessing must preserve ordered publication, actor-safe state and
cancellation. Test repeated actions, navigation away, superseded requests and
out-of-order completion. An obsolete task must not publish over a newer attempt.

Use bounded requests and existing task ownership. Do not introduce detached work
or unchecked shared mutable caches merely to silence an isolation diagnostic.

## Media-related interaction

First establish whether native AVPlayer, WebKit or another reviewed component
owns the playing media, controls and PiP. A visual loading or pause state alone
does not identify the actual owner. Preserve attempt-scoped teardown, audio and
background continuity when changing source-resolution presentation.

Separate input registration from visual feedback and media readiness. A state
assignment is not proof the frame has rendered. Verify that progress feedback
does not mask child controls, create a second player, trap cancellation or
allow an old completion to select a source after the user has moved on.

Do not change provider admission, infer available media or disable security as
a performance fix. Report those as separate functional or source findings.
