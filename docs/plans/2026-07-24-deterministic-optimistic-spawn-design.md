# Deterministic Optimistic Spawn Design

## Goal

Show launcher output immediately while preserving server authority and producing the same weighted result in Godot and Cloudflare Workers.

## Protocol

Each player state stores a 32-bit `spawn_seed` and monotonically increasing `spawn_sequence`. A successful spawn derives an integer roll from the seed, current sequence, and launcher UID using the same bounded integer algorithm in TypeScript and GDScript. Failed spawns do not advance the sequence.

New clients submit a unique `request_id`, `expected_sequence`, and their predicted item and target. The server validates the expected sequence, executes the authoritative spawn, advances the sequence only on success, and stores a bounded history of successful request IDs. Repeating a stored request returns its original result without consuming resources again. Old clients remain valid because all new request fields are optional.

## Client Prediction

On click, the client reserves charges and resource cost, computes the item and nearest empty cell, and inserts a negative-UID item marked `_pending_spawn`. The predicted item cannot be dragged or used. Subsequent clicks see that occupied cell and therefore predict later target cells correctly.

When the response matches, the client replaces the temporary UID in place. When it differs, the client removes the prediction and applies the authoritative item; the server includes its grid only for mismatch recovery. Rejections remove the corresponding temporary item. Responses remain FIFO because mutations are serialized.

## Compatibility And Verification

Old saves receive and persist the new seed before it is exposed to a client. Spawn history is capped to prevent state growth. Verification includes TypeScript compilation, fixed RNG vectors, idempotent replay, successful sequence advancement, failure without advancement, and editor testing under artificial latency.
