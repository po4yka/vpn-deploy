//! Property-based tests for the urlencode helper (commands::share).
//!
//! Covers two invariants:
//!   1. Encoded output never contains raw whitespace.
//!   2. Encoding is reversible via percent_decode_str (round-trip identity).
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use proptest::prelude::*;
use vpnd::commands::share::urlencode;

proptest! {
    /// Any string input must produce output with no raw whitespace characters.
    #[test]
    fn urlencode_no_whitespace_survives(s in ".*") {
        let encoded = urlencode(&s);
        prop_assert!(
            !encoded.contains(' ') && !encoded.contains('\t') && !encoded.contains('\n'),
            "encoded output must not contain raw whitespace, got: {:?}",
            encoded
        );
    }

    /// Encoding then decoding must recover the original string byte-for-byte.
    #[test]
    fn urlencode_roundtrip_via_url_decode(s in ".*") {
        let encoded = urlencode(&s);
        let decoded = percent_encoding::percent_decode_str(&encoded)
            .decode_utf8()
            .expect("percent_decode must produce valid UTF-8 for UTF-8 input");
        prop_assert_eq!(
            decoded.as_ref(),
            s.as_str(),
            "round-trip must recover original string"
        );
    }
}
