use codex_utils_absolute_path::AbsolutePathBuf;
use dirs::home_dir;
use std::path::PathBuf;

/// Environment variable that overrides the configuration directory.
///
/// [fraktal] `FRAKTAL_HOME` is the branded name; `CODEX_HOME` stays supported
/// as a fallback so upstream tooling and existing user scripts keep working.
pub const FRAKTAL_HOME_ENV_VAR: &str = "FRAKTAL_HOME";
pub const LEGACY_CODEX_HOME_ENV_VAR: &str = "CODEX_HOME";

/// Directory name used under the user's home directory when no environment
/// variable is set.
const FRAKTAL_HOME_DIR_NAME: &str = ".fraktal";

/// Returns the path to the Fraktal configuration directory, which can be
/// specified by the `FRAKTAL_HOME` environment variable (or the legacy
/// `CODEX_HOME`). If neither is set, defaults to `~/.fraktal`.
///
/// - If the variable is set, the value must exist and be a directory. The
///   value will be canonicalized and this function will Err otherwise.
/// - If it is not set, this function does not verify that the directory
///   exists.
pub fn find_codex_home() -> std::io::Result<AbsolutePathBuf> {
    find_codex_home_with(|name| std::env::var(name).ok())
}

/// Variable lookup is injected so precedence can be tested without mutating
/// process-wide environment state (which races across parallel tests).
fn find_codex_home_with(
    lookup: impl Fn(&str) -> Option<String>,
) -> std::io::Result<AbsolutePathBuf> {
    // Prefer the branded variable, then fall back to the upstream one.
    let selected = [FRAKTAL_HOME_ENV_VAR, LEGACY_CODEX_HOME_ENV_VAR]
        .into_iter()
        .find_map(|name| {
            lookup(name)
                .filter(|val| !val.is_empty())
                .map(|val| (name, val))
        });
    match selected {
        Some((name, val)) => find_codex_home_from_env(name, Some(&val)),
        None => find_codex_home_from_env(FRAKTAL_HOME_ENV_VAR, /*codex_home_env*/ None),
    }
}

/// `env_var_name` is only used to attribute error messages to whichever
/// variable actually supplied the value.
fn find_codex_home_from_env(
    env_var_name: &str,
    codex_home_env: Option<&str>,
) -> std::io::Result<AbsolutePathBuf> {
    // Honor the home environment variable when it is set to allow users (and
    // tests) to override the default location.
    match codex_home_env {
        Some(val) => {
            let path = PathBuf::from(val);
            let metadata = std::fs::metadata(&path).map_err(|err| match err.kind() {
                std::io::ErrorKind::NotFound => std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    format!("{env_var_name} points to {val:?}, but that path does not exist"),
                ),
                _ => std::io::Error::new(
                    err.kind(),
                    format!("failed to read {env_var_name} {val:?}: {err}"),
                ),
            })?;

            if !metadata.is_dir() {
                Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidInput,
                    format!("{env_var_name} points to {val:?}, but that path is not a directory"),
                ))
            } else {
                let canonical = path.canonicalize().map_err(|err| {
                    std::io::Error::new(
                        err.kind(),
                        format!("failed to canonicalize {env_var_name} {val:?}: {err}"),
                    )
                })?;
                AbsolutePathBuf::from_absolute_path(canonical)
            }
        }
        None => {
            let mut p = home_dir().ok_or_else(|| {
                std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    "Could not find home directory",
                )
            })?;
            p.push(FRAKTAL_HOME_DIR_NAME);
            AbsolutePathBuf::from_absolute_path(p)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::FRAKTAL_HOME_ENV_VAR;
    use super::LEGACY_CODEX_HOME_ENV_VAR;
    use super::find_codex_home_from_env;
    use super::find_codex_home_with;
    use codex_utils_absolute_path::AbsolutePathBuf;
    use dirs::home_dir;
    use pretty_assertions::assert_eq;
    use std::fs;
    use std::io::ErrorKind;
    use tempfile::TempDir;

    #[test]
    fn find_codex_home_env_missing_path_is_fatal() {
        let temp_home = TempDir::new().expect("temp home");
        let missing = temp_home.path().join("missing-codex-home");
        let missing_str = missing
            .to_str()
            .expect("missing codex home path should be valid utf-8");

        let err = find_codex_home_from_env(FRAKTAL_HOME_ENV_VAR, Some(missing_str))
            .expect_err("missing CODEX_HOME");
        assert_eq!(err.kind(), ErrorKind::NotFound);
        assert!(
            err.to_string().contains("FRAKTAL_HOME"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn find_codex_home_env_file_path_is_fatal() {
        let temp_home = TempDir::new().expect("temp home");
        let file_path = temp_home.path().join("codex-home.txt");
        fs::write(&file_path, "not a directory").expect("write temp file");
        let file_str = file_path
            .to_str()
            .expect("file codex home path should be valid utf-8");

        let err = find_codex_home_from_env(FRAKTAL_HOME_ENV_VAR, Some(file_str))
            .expect_err("file CODEX_HOME");
        assert_eq!(err.kind(), ErrorKind::InvalidInput);
        assert!(
            err.to_string().contains("not a directory"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn find_codex_home_env_valid_directory_canonicalizes() {
        let temp_home = TempDir::new().expect("temp home");
        let temp_str = temp_home
            .path()
            .to_str()
            .expect("temp codex home path should be valid utf-8");

        let resolved = find_codex_home_from_env(FRAKTAL_HOME_ENV_VAR, Some(temp_str))
            .expect("valid CODEX_HOME");
        let expected = temp_home
            .path()
            .canonicalize()
            .expect("canonicalize temp home");
        let expected = AbsolutePathBuf::from_absolute_path(expected).expect("absolute home");
        assert_eq!(resolved, expected);
    }

    #[test]
    fn find_codex_home_without_env_uses_default_home_dir() {
        let resolved = find_codex_home_from_env(FRAKTAL_HOME_ENV_VAR, /*codex_home_env*/ None)
            .expect("default CODEX_HOME");
        let mut expected = home_dir().expect("home dir");
        expected.push(".fraktal");
        let expected = AbsolutePathBuf::from_absolute_path(expected).expect("absolute home");
        assert_eq!(resolved, expected);
    }

    fn canonical(dir: &TempDir) -> AbsolutePathBuf {
        let path = dir.path().canonicalize().expect("canonicalize");
        AbsolutePathBuf::from_absolute_path(path).expect("absolute home")
    }

    /// [fraktal] `FRAKTAL_HOME` wins when both are set.
    #[test]
    fn fraktal_home_takes_precedence_over_legacy_codex_home() {
        let fraktal = TempDir::new().expect("fraktal home");
        let legacy = TempDir::new().expect("legacy home");
        let fraktal_path = fraktal.path().to_string_lossy().into_owned();
        let legacy_path = legacy.path().to_string_lossy().into_owned();

        let resolved = find_codex_home_with(|name| match name {
            FRAKTAL_HOME_ENV_VAR => Some(fraktal_path.clone()),
            LEGACY_CODEX_HOME_ENV_VAR => Some(legacy_path.clone()),
            _ => None,
        })
        .expect("resolve home");

        assert_eq!(resolved, canonical(&fraktal));
    }

    /// [fraktal] `CODEX_HOME` alone still works, so upstream tooling and
    /// existing user scripts keep resolving.
    #[test]
    fn legacy_codex_home_is_still_honored_on_its_own() {
        let legacy = TempDir::new().expect("legacy home");
        let legacy_path = legacy.path().to_string_lossy().into_owned();

        let resolved = find_codex_home_with(|name| {
            (name == LEGACY_CODEX_HOME_ENV_VAR).then(|| legacy_path.clone())
        })
        .expect("resolve home");

        assert_eq!(resolved, canonical(&legacy));
    }

    /// An empty value must not shadow the fallback.
    #[test]
    fn empty_fraktal_home_falls_back_to_legacy_codex_home() {
        let legacy = TempDir::new().expect("legacy home");
        let legacy_path = legacy.path().to_string_lossy().into_owned();

        let resolved = find_codex_home_with(|name| match name {
            FRAKTAL_HOME_ENV_VAR => Some(String::new()),
            LEGACY_CODEX_HOME_ENV_VAR => Some(legacy_path.clone()),
            _ => None,
        })
        .expect("resolve home");

        assert_eq!(resolved, canonical(&legacy));
    }

    #[test]
    fn no_env_vars_defaults_to_dot_fraktal() {
        let resolved = find_codex_home_with(|_| None).expect("resolve home");

        let mut expected = home_dir().expect("home dir");
        expected.push(".fraktal");
        let expected = AbsolutePathBuf::from_absolute_path(expected).expect("absolute home");
        assert_eq!(resolved, expected);
    }
}
