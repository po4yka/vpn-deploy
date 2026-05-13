use include_dir::{include_dir, Dir};

/// All markdown files from the repo's `docs/` directory, bundled at compile time.
pub static DOCS: Dir<'static> = include_dir!("$CARGO_MANIFEST_DIR/../docs");

/// Keywords that trigger runbook excerpt injection in `doctor --ai` output.
const KEYWORD_MAP: &[(&str, &[&str])] = &[
    ("fleet-status", &["RUNBOOK-incident.md", "RUNBOOK-rollback.md"]),
    ("asn-drift", &["RUNBOOK-incident.md"]),
    ("burn-check", &["RUNBOOK-incident.md", "RUNBOOK-rotate.md"]),
];

/// Return runbook excerpts relevant to the diagnostic report text.
///
/// Scans `report` for known keywords and appends the first 60 lines of each
/// matched runbook file.  Duplicates are suppressed.
pub fn relevant_runbook_excerpts(report: &str) -> String {
    let mut seen: Vec<&str> = Vec::new();
    let mut out = String::new();

    for (keyword, files) in KEYWORD_MAP {
        if !report.contains(keyword) {
            continue;
        }
        for &fname in *files {
            if seen.contains(&fname) {
                continue;
            }
            seen.push(fname);
            if let Some(f) = DOCS.get_file(fname) {
                if let Some(text) = f.contents_utf8() {
                    let excerpt: String = text.lines().take(60).collect::<Vec<_>>().join("\n");
                    out.push_str(&format!("\n---\n### Runbook excerpt: {fname}\n\n{excerpt}\n"));
                }
            }
        }
    }

    out
}
