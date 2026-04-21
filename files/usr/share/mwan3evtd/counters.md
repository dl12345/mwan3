# mwan3evtd status counters

`ubus call mwan3evtd status` returns a per-event array. Each entry contains the current state, three timing fields recorded at the end of each completed batch, and a counters object. This document explains every field and how to use them to tune timing.

&nbsp;

## Timing fields

These are recorded when the handler fires and reflect the most recently completed batch.

**`last_fired_at_ms`** — monotonic millisecond timestamp of the last handler invocation. Useful for confirming that an event is being acted on and for measuring time between firings across multiple batches.

**`last_batch_duration_ms`** — elapsed time in milliseconds from the first push in the last batch to the moment the handler fired. This is the most direct input to choosing `max_window_ms`: if this value regularly approaches your configured `max_window_ms`, the deadline is being hit rather than the window settling. If it is consistently much smaller than `max_window_ms`, the deadline has headroom to spare.

**`last_batch_pushes`** — number of pushes that arrived during the last batch. Combined with `last_batch_duration_ms` this tells you how dense the push traffic was. A high count with a long duration suggests sustained, spread-out churn from multiple callers.

&nbsp;

## Counters

**`pushes`** — cumulative total of accepted pushes. Includes all states.

**`invocations`** — cumulative total of handler firings. The ratio `invocations / pushes` shows how much coalescing is occurring. A ratio close to 1 means nearly every push fired the handler; a low ratio means heavy coalescing.

**`window_resets`** — cumulative count of times the trailing-debounce window timer was reset by an incoming push while a batch was pending. This is the direct measure of whether `window_ms` is doing useful work. If this is zero across many batches, all pushes arrived after the previous window had already settled and `window_ms` is wider than it needs to be. If this is high, the window is actively deferring the handler.

**`deadline_fires`** — cumulative count of times the handler fired because `max_window_ms` elapsed rather than because the window settled. Any non-zero value means pushes were arriving continuously for longer than `max_window_ms`. If this happens regularly, either `max_window_ms` is too short for the observed push pattern or the caller is genuinely pushing without pause.

**`max_inter_push_ms`** — the largest gap in milliseconds observed between consecutive pushes within the same batch, across all batches since startup. This is the most direct input to choosing `window_ms`: set `window_ms` above this value to guarantee that a typical burst is coalesced into a single handler invocation rather than firing mid-burst. If `max_inter_push_ms` is 4200 and `window_ms` is 3000, the window is too short and the handler may fire while the burst is still in progress.

**`superseded_as_source`** — cumulative count of times this event's push was discarded because a stronger event was already pending. Non-zero confirms that supersession relationships are active.

**`superseded_as_target`** — cumulative count of times a pending batch for this event was cancelled by a stronger incoming event.

**`after_running_coalesced`** — cumulative count of pushes that arrived while the handler was running. These pushes set a pending-after flag so the handler reruns once the current invocation completes. A high value means the handler runtime overlaps significantly with push traffic.

**`failures`** — cumulative count of handler exits with a non-zero exit code, plus spawn failures.

**`timeouts`** — cumulative count of handler invocations that exceeded `handler_timeout_ms` and were killed.

&nbsp;

## Tuning workflow

1. Run `ubus call mwan3evtd reset` to zero all counters before starting a representative event sequence. This ensures the measurements reflect only the sequence you are about to trigger, not accumulated history since daemon startup.

2. Trigger the event sequence (e.g. a config change that triggers the callers you care about).

3. Run `ubus call mwan3evtd status` to read the results. Then continue the numbered steps below.

4. Check `max_inter_push_ms`. If it is larger than your configured `window_ms`, the window is too short: raise `window_ms` above `max_inter_push_ms`.

5. Check `last_batch_duration_ms`. If it is close to `max_window_ms`, the deadline is being hit: raise `max_window_ms` to give the window room to settle naturally.

6. Check `deadline_fires`. If it is non-zero and you did not expect continuous pushing, the deadline is too tight for the observed pattern.

7. Check `window_resets`. If it is zero for all batches, `window_ms` is already wider than all inter-push gaps and could be reduced without risk of mid-burst fires.

8. Check `after_running_coalesced`. If it is consistently non-zero, the handler takes longer to complete than the inter-batch interval. Consider whether `handler_timeout_ms` is appropriate or whether the handler command itself needs attention.
