# UAP v1 invalid-input prototypes

These are hostile inputs for the adversarial harness. They are not an accepted
UAP v1 wire contract. In particular, the current self-contained framing oracle
uses a four-byte unsigned big-endian length and a provisional 1 MiB limit only
to make truncation, limits, and every chunk split executable before Agent 6's
selected framing API is integrated.

`*.hex` files contain wire bytes as lowercase hexadecimal:

- `malformed-utf8.hex`: invalid UTF-8 byte sequence `c3 28`.
- `truncated-prefix.hex`: only two bytes of the provisional four-byte prefix.
- `truncated-payload.hex`: length five followed by only two payload bytes.
- `over-limit.hex`: declared length 1,048,577, one byte over the prototype cap.

`duplicate-fields.uap` is valid UTF-8 but repeats `request-id`. A selected
canonical parser must reject it before any adapter effect. The future protocol
integration must replace provisional framing assumptions with accepted v1
limits and error codes while retaining these attack classes.
