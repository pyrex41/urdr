\* Canonical dependency-ordered load manifest for consuming urdr's Shen
   tree as a library.

   The current working directory MUST be the urdr repository root: every
   path below is root-relative, exactly as in the test lanes. External
   consumers load this file once (`shen -l shen/load.shen`, or read and
   eval it the way the test suites do) instead of copying a lane's inline
   load sequence.

   The order is the reviewed one from the fullest test lane
   (shen/tests/integration/run-tests.shen), with the grammar-family module
   (shen/search/grammar.shen; ADR 0004 Decision 5) inserted after its only
   dependency, shen/search/search.shen, in the order its own lane uses.

   Deliberately excluded:
   - shen/properties/query.shen — ANALYSIS status, non-certifying, loaded
     by no lane; consumers who want it load it after this manifest.
   - shen/run/models/partition-retry.shen and scenarios/ — reference
     fixtures, not library surface.

   The quiet loader below mirrors the test lanes' pattern: it evaluates
   each toplevel form via eval (so nothing is echoed) and skips embedded
   (load ...) forms. Its names carry the urdr.load. prefix so they cannot
   collide with a lane's own loader (urn./uit./ug. ...). *\

(define urdr.load.eval-forms
  [] -> loaded
  [[load _] | Forms] -> (urdr.load.eval-forms Forms)
  [Form | Forms] ->
    (let Ignored (eval Form)
      (urdr.load.eval-forms Forms)))

(define urdr.load.quiet-load
  File -> (urdr.load.eval-forms (read-file File)))

(urdr.load.quiet-load "shen/protocol/canonical.shen")
(urdr.load.quiet-load "shen/world/integer.shen")
(urdr.load.quiet-load "shen/world/prng.shen")
(urdr.load.quiet-load "shen/world/netkat.shen")
(urdr.load.quiet-load "shen/world/component.shen")
(urdr.load.quiet-load "shen/world/world.shen")
(urdr.load.quiet-load "shen/scenario/scenario.shen")
(urdr.load.quiet-load "shen/world/models/common.shen")
(urdr.load.quiet-load "shen/world/models/mask.shen")
(urdr.load.quiet-load "shen/world/models/net.shen")
(urdr.load.quiet-load "shen/world/models/timer.shen")
(urdr.load.quiet-load "shen/world/models/fault.shen")
(urdr.load.quiet-load "shen/world/models/registry.shen")
(urdr.load.quiet-load "shen/world/netpol.shen")
(urdr.load.quiet-load "shen/world/netkat-witness.shen")
(urdr.load.quiet-load "shen/properties/properties.shen")
(urdr.load.quiet-load "shen/world/eventlog.shen")
(urdr.load.quiet-load "shen/world/replay.shen")
(urdr.load.quiet-load "shen/world/certificate.shen")
(urdr.load.quiet-load "shen/search/search.shen")
(urdr.load.quiet-load "shen/search/grammar.shen")
(urdr.load.quiet-load "shen/shrink/shrink.shen")
(urdr.load.quiet-load "shen/run/run.shen")
