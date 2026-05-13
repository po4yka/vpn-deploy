use owo_colors::OwoColorize;

/// Print a wizard section header in Meridian's convention:
/// bold title → dim description → blank line. The caller then prompts.
pub fn section(title: &str, description: &str) {
    println!();
    println!("{}", title.bold());
    if !description.is_empty() {
        println!("{}", description.dimmed());
    }
    println!();
}
