(set *hush* true)
(load "shen/protocol/canonical.shen")
(load "shen/tests/canonical/suite.shen")
(set *hush* false)
(urdr.canonical.test.run
  "protocol/fixtures/v1/canonical/cases.tsv")
