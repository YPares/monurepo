use std::path::PathBuf;

/// Source of Datalog rules: inline string or a file path.
#[derive(Debug, Clone)]
pub enum RulesSource {
    /// Inline rules string.
    Inline(String),
    /// Path to a `.rls` file.
    File(PathBuf),
}

impl RulesSource {
    /// Load the rules text from the source.
    pub fn load(&self) -> Result<String, std::io::Error> {
        match self {
            RulesSource::Inline(rules) => Ok(rules.clone()),
            RulesSource::File(path) => std::fs::read_to_string(path),
        }
    }
}
