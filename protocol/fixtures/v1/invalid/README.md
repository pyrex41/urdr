# Invalid UAP/netstring fixtures

These bytes are adversarial inputs for M0 framing and canonical-value
rejection. They target the production ADR 0002 netstring frame:

```text
decimal-payload-octet-count ":" payload ","
```

| Fixture | Attack |
| --- | --- |
| `truncated-prefix.hex` | Incomplete length digits; no colon yet |
| `truncated-payload.hex` | Declared payload length not fully received |
| `over-limit.hex` | Declared length exceeds the M0 4,096-octet cap |
| `malformed-utf8.hex` | Well-framed payload containing invalid UTF-8 text |
| `duplicate-fields.hex` | Well-framed record with a repeated field name |

Hex files store lowercase hex of the raw wire bytes. Decoders must reject
every contiguous chunk split without executing adapter effects.
