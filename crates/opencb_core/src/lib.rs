use chrono::{DateTime, Utc};
use rusqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_uchar};
use std::path::Path;
use uuid::Uuid;

pub type Result<T> = std::result::Result<T, OpenCbError>;

#[derive(Debug, thiserror::Error)]
pub enum OpenCbError {
    #[error("database error: {0}")]
    Database(#[from] rusqlite::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("clipboard item was not found")]
    NotFound,
    #[error("invalid content type: {0}")]
    InvalidContentType(String),
    #[error("invalid ffi input")]
    InvalidFfiInput,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClipboardContentType {
    Text,
    Code,
    Url,
    Image,
    FileReference,
}

impl ClipboardContentType {
    fn as_str(self) -> &'static str {
        match self {
            Self::Text => "text",
            Self::Code => "code",
            Self::Url => "url",
            Self::Image => "image",
            Self::FileReference => "file_reference",
        }
    }
}

impl TryFrom<&str> for ClipboardContentType {
    type Error = OpenCbError;

    fn try_from(value: &str) -> Result<Self> {
        match value {
            "text" => Ok(Self::Text),
            "code" => Ok(Self::Code),
            "url" => Ok(Self::Url),
            "image" => Ok(Self::Image),
            "file_reference" => Ok(Self::FileReference),
            other => Err(OpenCbError::InvalidContentType(other.to_string())),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardItem {
    pub id: String,
    pub content_type: ClipboardContentType,
    pub preview: String,
    pub content_text: Option<String>,
    pub file_path: Option<String>,
    pub hash: String,
    pub source_app: Option<String>,
    pub tags: Vec<String>,
    pub pinned: bool,
    pub device_id: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub public_key: String,
    pub trusted: bool,
    pub last_seen_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct RetentionPolicy {
    pub max_items: usize,
    pub max_storage_mb: usize,
    pub preserve_pinned: bool,
}

impl Default for RetentionPolicy {
    fn default() -> Self {
        Self {
            max_items: 10_000,
            max_storage_mb: 1_024,
            preserve_pinned: true,
        }
    }
}

pub struct OpenCbCore {
    conn: Connection,
    device_id: String,
}

impl OpenCbCore {
    pub fn open(path: impl AsRef<Path>, device_name: &str) -> Result<Self> {
        let conn = Connection::open(path)?;
        let core = Self {
            conn,
            device_id: Uuid::new_v4().to_string(),
        };
        core.migrate()?;
        core.ensure_local_device(device_name)?;
        Ok(core)
    }

    pub fn open_memory(device_name: &str) -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        let core = Self {
            conn,
            device_id: Uuid::new_v4().to_string(),
        };
        core.migrate()?;
        core.ensure_local_device(device_name)?;
        Ok(core)
    }

    pub fn local_device_id(&self) -> &str {
        &self.device_id
    }

    pub fn capture_text(&self, text: &str, source_app: Option<&str>) -> Result<ClipboardItem> {
        let preview = preview_text(text);
        self.upsert_item(NewClipboardItem {
            content_type: if is_clipboard_url(text) {
                ClipboardContentType::Url
            } else if looks_like_code(text) {
                ClipboardContentType::Code
            } else {
                ClipboardContentType::Text
            },
            preview,
            content_text: Some(text.to_string()),
            file_path: None,
            blob: None,
            source_app: source_app.map(str::to_string),
        })
    }

    pub fn capture_image(&self, bytes: &[u8], source_app: Option<&str>) -> Result<ClipboardItem> {
        let preview = format!("Image - {} bytes", bytes.len());
        self.upsert_item(NewClipboardItem {
            content_type: ClipboardContentType::Image,
            preview,
            content_text: None,
            file_path: None,
            blob: Some(bytes.to_vec()),
            source_app: source_app.map(str::to_string),
        })
    }

    pub fn capture_file_reference(
        &self,
        path: &str,
        source_app: Option<&str>,
    ) -> Result<ClipboardItem> {
        self.upsert_item(NewClipboardItem {
            content_type: ClipboardContentType::FileReference,
            preview: path.to_string(),
            content_text: None,
            file_path: Some(path.to_string()),
            blob: None,
            source_app: source_app.map(str::to_string),
        })
    }

    pub fn list_items(&self, limit: usize, offset: usize) -> Result<Vec<ClipboardItem>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, content_type, preview, content_text, file_path, hash, source_app, tags_json,
                    pinned, device_id, created_at, updated_at
             FROM clipboard_items
             ORDER BY created_at DESC
             LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit as i64, offset as i64], map_item)?;
        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(OpenCbError::from)
    }

    pub fn search_items(&self, query: &str, limit: usize) -> Result<Vec<ClipboardItem>> {
        if query.trim().is_empty() {
            return self.list_items(limit, 0);
        }

        let query = normalize_fts_query(query);
        let mut stmt = self.conn.prepare(
            "SELECT i.id, i.content_type, i.preview, i.content_text, i.file_path, i.hash,
                    i.source_app, i.tags_json, i.pinned, i.device_id, i.created_at, i.updated_at
             FROM clipboard_items_fts f
             JOIN clipboard_items i ON i.id = f.item_id
             WHERE clipboard_items_fts MATCH ?1
             ORDER BY rank, i.created_at DESC
             LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![query, limit as i64], map_item)?;
        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(OpenCbError::from)
    }

    pub fn get_item(&self, id: &str) -> Result<ClipboardItem> {
        self.conn
            .query_row(
                "SELECT id, content_type, preview, content_text, file_path, hash, source_app,
                        tags_json, pinned, device_id, created_at, updated_at
                 FROM clipboard_items
                 WHERE id = ?1",
                params![id],
                map_item,
            )
            .optional()?
            .ok_or(OpenCbError::NotFound)
    }

    pub fn delete_item(&self, id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM clipboard_items_fts WHERE item_id = ?1",
            params![id],
        )?;
        self.conn
            .execute("DELETE FROM clipboard_items WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn set_pinned(&self, id: &str, pinned: bool) -> Result<()> {
        let changed = self.conn.execute(
            "UPDATE clipboard_items SET pinned = ?2, updated_at = ?3 WHERE id = ?1",
            params![id, pinned, now_rfc3339()],
        )?;
        if changed == 0 {
            return Err(OpenCbError::NotFound);
        }
        Ok(())
    }

    pub fn set_tags(&self, id: &str, tags: &[String]) -> Result<()> {
        let tags_json = serde_json::to_string(tags)?;
        let changed = self.conn.execute(
            "UPDATE clipboard_items SET tags_json = ?2, updated_at = ?3 WHERE id = ?1",
            params![id, tags_json, now_rfc3339()],
        )?;
        if changed == 0 {
            return Err(OpenCbError::NotFound);
        }
        self.refresh_fts(id)?;
        Ok(())
    }

    pub fn touch_item(&self, id: &str) -> Result<()> {
        let now = now_rfc3339();
        let changed = self.conn.execute(
            "UPDATE clipboard_items SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
            params![id, now],
        )?;
        if changed == 0 {
            return Err(OpenCbError::NotFound);
        }
        Ok(())
    }

    pub fn apply_retention(&self, policy: RetentionPolicy) -> Result<usize> {
        let pinned_count = if policy.preserve_pinned {
            self.conn.query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE pinned = 1",
                [],
                |row| row.get::<_, usize>(0),
            )?
        } else {
            0
        };
        let unpinned_to_keep = policy.max_items.saturating_sub(pinned_count);
        let mut stmt = self.conn.prepare(
            "SELECT id
             FROM clipboard_items
             WHERE (?1 = 0 OR pinned = 0)
             ORDER BY created_at DESC
             LIMIT -1 OFFSET ?2",
        )?;
        let ids = stmt
            .query_map(
                params![policy.preserve_pinned, unpinned_to_keep as i64],
                |row| row.get::<_, String>(0),
            )?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        for id in &ids {
            self.delete_item(id)?;
        }
        Ok(ids.len())
    }

    pub fn get_blob(&self, id: &str) -> Result<Option<Vec<u8>>> {
        self.conn
            .query_row(
                "SELECT bytes FROM clipboard_blobs WHERE item_id = ?1",
                params![id],
                |row| row.get(0),
            )
            .optional()
            .map_err(OpenCbError::from)
    }

    pub fn create_pairing_code(&self) -> PairingCode {
        PairingCode {
            device_id: self.device_id.clone(),
            public_key: derive_demo_public_key(&self.device_id),
            code: short_code(&self.device_id),
        }
    }

    pub fn trust_device(&self, name: &str, public_key: &str) -> Result<Device> {
        let id = Uuid::new_v4().to_string();
        let now = now_rfc3339();
        self.conn.execute(
            "INSERT INTO devices (id, name, public_key, trusted, last_seen_at)
             VALUES (?1, ?2, ?3, 1, ?4)",
            params![id, name, public_key, now],
        )?;
        self.get_device(&id)
    }

    pub fn list_devices(&self) -> Result<Vec<Device>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, name, public_key, trusted, last_seen_at
             FROM devices
             ORDER BY trusted DESC, name ASC",
        )?;
        let rows = stmt.query_map([], map_device)?;
        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(OpenCbError::from)
    }

    fn upsert_item(&self, item: NewClipboardItem) -> Result<ClipboardItem> {
        let hash = hash_item(&item);
        if let Some(existing_id) = self.find_by_hash(&hash)? {
            let now = now_rfc3339();
            self.conn.execute(
                "UPDATE clipboard_items SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
                params![existing_id, now],
            )?;
            return self.get_item(&existing_id);
        }

        let id = Uuid::new_v4().to_string();
        let now = now_rfc3339();
        self.conn.execute(
            "INSERT INTO clipboard_items
                (id, content_type, preview, content_text, file_path, hash, source_app, tags_json,
                 pinned, device_id, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, '[]', 0, ?8, ?9, ?9)",
            params![
                id,
                item.content_type.as_str(),
                item.preview,
                item.content_text,
                item.file_path,
                hash,
                item.source_app,
                self.device_id,
                now
            ],
        )?;

        if let Some(blob) = item.blob {
            self.conn.execute(
                "INSERT INTO clipboard_blobs (item_id, bytes) VALUES (?1, ?2)",
                params![id, blob],
            )?;
        }

        self.refresh_fts(&id)?;
        self.get_item(&id)
    }

    fn find_by_hash(&self, hash: &str) -> Result<Option<String>> {
        self.conn
            .query_row(
                "SELECT id FROM clipboard_items WHERE hash = ?1 LIMIT 1",
                params![hash],
                |row| row.get(0),
            )
            .optional()
            .map_err(OpenCbError::from)
    }

    fn get_device(&self, id: &str) -> Result<Device> {
        self.conn
            .query_row(
                "SELECT id, name, public_key, trusted, last_seen_at FROM devices WHERE id = ?1",
                params![id],
                map_device,
            )
            .optional()?
            .ok_or(OpenCbError::NotFound)
    }

    fn ensure_local_device(&self, device_name: &str) -> Result<()> {
        let public_key = derive_demo_public_key(&self.device_id);
        self.conn.execute(
            "INSERT INTO devices (id, name, public_key, trusted, last_seen_at)
             VALUES (?1, ?2, ?3, 1, ?4)",
            params![self.device_id, device_name, public_key, now_rfc3339()],
        )?;
        Ok(())
    }

    fn refresh_fts(&self, id: &str) -> Result<()> {
        let item = self.get_item(id)?;
        self.conn.execute(
            "DELETE FROM clipboard_items_fts WHERE item_id = ?1",
            params![id],
        )?;
        self.conn.execute(
            "INSERT INTO clipboard_items_fts (item_id, preview, body, tags, source_app)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                item.id,
                item.preview,
                item.content_text.unwrap_or_default(),
                item.tags.join(" "),
                item.source_app.unwrap_or_default()
            ],
        )?;
        Ok(())
    }

    fn migrate(&self) -> Result<()> {
        self.conn.execute_batch(
            "
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                content_type TEXT NOT NULL,
                preview TEXT NOT NULL,
                content_text TEXT,
                file_path TEXT,
                hash TEXT NOT NULL UNIQUE,
                source_app TEXT,
                tags_json TEXT NOT NULL DEFAULT '[]',
                pinned INTEGER NOT NULL DEFAULT 0,
                device_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS clipboard_blobs (
                item_id TEXT PRIMARY KEY,
                bytes BLOB NOT NULL,
                FOREIGN KEY(item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS devices (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                public_key TEXT NOT NULL,
                trusted INTEGER NOT NULL DEFAULT 0,
                last_seen_at TEXT
            );

            CREATE TABLE IF NOT EXISTS sync_state (
                device_id TEXT PRIMARY KEY,
                cursor TEXT,
                last_synced_at TEXT,
                last_error TEXT,
                FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value_json TEXT NOT NULL
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts
            USING fts5(item_id UNINDEXED, preview, body, tags, source_app);
            ",
        )?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingCode {
    pub device_id: String,
    pub public_key: String,
    pub code: String,
}

struct NewClipboardItem {
    content_type: ClipboardContentType,
    preview: String,
    content_text: Option<String>,
    file_path: Option<String>,
    blob: Option<Vec<u8>>,
    source_app: Option<String>,
}

fn map_item(row: &rusqlite::Row<'_>) -> rusqlite::Result<ClipboardItem> {
    let content_type = row.get::<_, String>(1)?;
    let tags_json = row.get::<_, String>(7)?;
    let tags = serde_json::from_str(&tags_json).unwrap_or_default();
    Ok(ClipboardItem {
        id: row.get(0)?,
        content_type: ClipboardContentType::try_from(content_type.as_str()).map_err(|err| {
            rusqlite::Error::FromSqlConversionFailure(1, rusqlite::types::Type::Text, Box::new(err))
        })?,
        preview: row.get(2)?,
        content_text: row.get(3)?,
        file_path: row.get(4)?,
        hash: row.get(5)?,
        source_app: row.get(6)?,
        tags,
        pinned: row.get(8)?,
        device_id: row.get(9)?,
        created_at: parse_rfc3339(row.get::<_, String>(10)?),
        updated_at: parse_rfc3339(row.get::<_, String>(11)?),
    })
}

fn map_device(row: &rusqlite::Row<'_>) -> rusqlite::Result<Device> {
    let last_seen = row.get::<_, Option<String>>(4)?;
    Ok(Device {
        id: row.get(0)?,
        name: row.get(1)?,
        public_key: row.get(2)?,
        trusted: row.get(3)?,
        last_seen_at: last_seen.map(parse_rfc3339),
    })
}

fn hash_item(item: &NewClipboardItem) -> String {
    let mut hasher = Sha256::new();
    hasher.update(item.content_type.as_str().as_bytes());
    if let Some(text) = &item.content_text {
        hasher.update(text.as_bytes());
    }
    if let Some(path) = &item.file_path {
        hasher.update(path.as_bytes());
    }
    if let Some(blob) = &item.blob {
        hasher.update(blob);
    }
    format!("{:x}", hasher.finalize())
}

fn derive_demo_public_key(device_id: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"opencb-device-key:");
    hasher.update(device_id.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn short_code(device_id: &str) -> String {
    device_id
        .chars()
        .filter(|ch| ch.is_ascii_hexdigit())
        .take(8)
        .collect::<String>()
        .to_uppercase()
}

fn preview_text(text: &str) -> String {
    let compact = text.split_whitespace().collect::<Vec<_>>().join(" ");
    compact.chars().take(160).collect()
}

fn is_clipboard_url(value: &str) -> bool {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed.chars().any(char::is_whitespace) {
        return false;
    }
    let lower = trimmed.to_ascii_lowercase();
    let without_scheme = if lower.starts_with("https://") {
        &trimmed[8..]
    } else if lower.starts_with("http://") {
        &trimmed[7..]
    } else {
        trimmed
    };
    if without_scheme.contains("://") {
        return false;
    }
    let host = without_scheme
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default()
        .split('@')
        .next_back()
        .unwrap_or_default()
        .split(':')
        .next()
        .unwrap_or_default();
    !host.is_empty()
        && (host.eq_ignore_ascii_case("localhost")
            || (host.contains('.') && !host.starts_with('.') && !host.ends_with('.')))
}

fn looks_like_code(value: &str) -> bool {
    let trimmed = value.trim();
    if trimmed.len() < 12 {
        return false;
    }

    let lower = trimmed.to_ascii_lowercase();
    let keyword_score = [
        "class ",
        "function ",
        "const ",
        "let ",
        "var ",
        "final ",
        "import ",
        "export ",
        "return ",
        "if ",
        "else",
        "for ",
        "while ",
        "switch ",
        "case ",
        "try ",
        "catch ",
        "async ",
        "await ",
        "fn ",
        "pub ",
        "impl ",
        "struct ",
        "enum ",
        "use ",
        "def ",
        "from ",
        "select ",
        "insert ",
        "update ",
        "delete ",
        "create ",
        "where ",
    ]
    .iter()
    .any(|keyword| lower.contains(keyword));
    let operator_score = [
        "=>", "->", "::", "&&", "||", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=",
    ]
    .iter()
    .any(|operator| trimmed.contains(operator));
    let has_syntax_punctuation = trimmed.chars().any(|ch| matches!(ch, '{' | '}' | ';'));
    let starts_like_markup = trimmed.starts_with('<')
        && trimmed
            .chars()
            .nth(1)
            .map(|ch| ch.is_ascii_alphabetic())
            .unwrap_or(false);
    let looks_like_json = ((trimmed.starts_with('{') && trimmed.ends_with('}'))
        || (trimmed.starts_with('[') && trimmed.ends_with(']')))
        && trimmed.contains(':');
    let lines: Vec<&str> = trimmed.lines().collect();
    let indented_lines = lines
        .iter()
        .filter(|line| line.starts_with("  ") || line.starts_with('\t'))
        .count();
    let multiline_syntax = lines.len() >= 2
        && trimmed
            .chars()
            .any(|ch| matches!(ch, '(' | ')' | '{' | '}' | '[' | ']' | ';'));

    let mut score = 0;
    if keyword_score {
        score += 2;
    }
    if operator_score {
        score += 2;
    }
    if has_syntax_punctuation {
        score += 1;
    }
    if starts_like_markup {
        score += 2;
    }
    if looks_like_json {
        score += 2;
    }
    if lines.len() >= 3 && indented_lines >= 2 {
        score += 1;
    }
    if multiline_syntax {
        score += 1;
    }

    score >= 3
}

fn normalize_fts_query(query: &str) -> String {
    query
        .split_whitespace()
        .map(|part| format!("{}*", part.replace('"', "")))
        .collect::<Vec<_>>()
        .join(" ")
}

fn now_rfc3339() -> String {
    Utc::now().to_rfc3339()
}

fn parse_rfc3339(value: String) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(&value)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now())
}

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

fn set_last_error(error: impl ToString) {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = Some(error.to_string());
    });
}

fn clear_last_error() {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = None;
    });
}

unsafe fn cstr_to_string(value: *const c_char) -> Result<String> {
    if value.is_null() {
        return Err(OpenCbError::InvalidFfiInput);
    }
    let text = unsafe { CStr::from_ptr(value) }
        .to_str()
        .map_err(|_| OpenCbError::InvalidFfiInput)?;
    Ok(text.to_string())
}

fn json_string<T: Serialize>(value: &T) -> *mut c_char {
    let json = serde_json::to_string(value).unwrap_or_else(|error| {
        set_last_error(error);
        "null".to_string()
    });
    CString::new(json)
        .unwrap_or_else(|_| CString::new("null").expect("literal has no nul"))
        .into_raw()
}

#[unsafe(no_mangle)]
pub extern "C" fn opencb_core_version() -> *const c_char {
    static VERSION: &[u8] = b"0.1.0\0";
    VERSION.as_ptr().cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn opencb_default_retention_policy_json() -> *mut c_char {
    let json = serde_json::to_string(&RetentionPolicy::default()).unwrap_or_else(|_| {
        "{\"max_items\":10000,\"max_storage_mb\":1024,\"preserve_pinned\":true}".to_string()
    });
    CString::new(json)
        .expect("retention policy json must not contain NUL")
        .into_raw()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            drop(CString::from_raw(value));
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn opencb_last_error_json() -> *mut c_char {
    let message = LAST_ERROR.with(|slot| slot.borrow().clone());
    json_string(&serde_json::json!({ "error": message }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_open(
    db_path: *const c_char,
    device_name: *const c_char,
) -> *mut OpenCbCore {
    match (unsafe { cstr_to_string(db_path) }, unsafe {
        cstr_to_string(device_name)
    }) {
        (Ok(path), Ok(name)) => match OpenCbCore::open(path, &name) {
            Ok(core) => {
                clear_last_error();
                Box::into_raw(Box::new(core))
            }
            Err(error) => {
                set_last_error(error);
                std::ptr::null_mut()
            }
        },
        (Err(error), _) | (_, Err(error)) => {
            set_last_error(error);
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_close(core: *mut OpenCbCore) {
    if !core.is_null() {
        unsafe {
            drop(Box::from_raw(core));
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_list_items_json(
    core: *mut OpenCbCore,
    limit: usize,
    offset: usize,
) -> *mut c_char {
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return json_string(&Vec::<ClipboardItem>::new());
    }
    match unsafe { &*core }.list_items(limit, offset) {
        Ok(items) => {
            clear_last_error();
            json_string(&items)
        }
        Err(error) => {
            set_last_error(error);
            json_string(&Vec::<ClipboardItem>::new())
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_search_items_json(
    core: *mut OpenCbCore,
    query: *const c_char,
    limit: usize,
) -> *mut c_char {
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return json_string(&Vec::<ClipboardItem>::new());
    }
    match unsafe { cstr_to_string(query) }.and_then(|q| unsafe { &*core }.search_items(&q, limit)) {
        Ok(items) => {
            clear_last_error();
            json_string(&items)
        }
        Err(error) => {
            set_last_error(error);
            json_string(&Vec::<ClipboardItem>::new())
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_capture_text_json(
    core: *mut OpenCbCore,
    text: *const c_char,
    source_app: *const c_char,
) -> *mut c_char {
    capture_with(core, |core| {
        let text = unsafe { cstr_to_string(text) }?;
        let source = unsafe { cstr_to_string(source_app) }.ok();
        core.capture_text(&text, source.as_deref())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_capture_file_reference_json(
    core: *mut OpenCbCore,
    path: *const c_char,
    source_app: *const c_char,
) -> *mut c_char {
    capture_with(core, |core| {
        let path = unsafe { cstr_to_string(path) }?;
        let source = unsafe { cstr_to_string(source_app) }.ok();
        core.capture_file_reference(&path, source.as_deref())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_capture_image_json(
    core: *mut OpenCbCore,
    bytes: *const c_uchar,
    len: usize,
    source_app: *const c_char,
) -> *mut c_char {
    capture_with(core, |core| {
        if bytes.is_null() || len == 0 {
            return Err(OpenCbError::InvalidFfiInput);
        }
        let source = unsafe { cstr_to_string(source_app) }.ok();
        let slice = unsafe { std::slice::from_raw_parts(bytes, len) };
        core.capture_image(slice, source.as_deref())
    })
}

fn capture_with<F>(core: *mut OpenCbCore, action: F) -> *mut c_char
where
    F: FnOnce(&OpenCbCore) -> Result<ClipboardItem>,
{
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return json_string(&Option::<ClipboardItem>::None);
    }
    match action(unsafe { &*core }) {
        Ok(item) => {
            clear_last_error();
            json_string(&item)
        }
        Err(error) => {
            set_last_error(error);
            json_string(&Option::<ClipboardItem>::None)
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_delete_item(core: *mut OpenCbCore, id: *const c_char) -> bool {
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return false;
    }
    match unsafe { cstr_to_string(id) }.and_then(|id| unsafe { &*core }.delete_item(&id)) {
        Ok(()) => {
            clear_last_error();
            true
        }
        Err(error) => {
            set_last_error(error);
            false
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_set_pinned(
    core: *mut OpenCbCore,
    id: *const c_char,
    pinned: bool,
) -> bool {
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return false;
    }
    match unsafe { cstr_to_string(id) }.and_then(|id| unsafe { &*core }.set_pinned(&id, pinned)) {
        Ok(()) => {
            clear_last_error();
            true
        }
        Err(error) => {
            set_last_error(error);
            false
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_set_tags_json(
    core: *mut OpenCbCore,
    id: *const c_char,
    tags_json: *const c_char,
) -> bool {
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return false;
    }
    let result = unsafe {
        cstr_to_string(id).and_then(|id| {
            let tags_text = cstr_to_string(tags_json)?;
            let tags = serde_json::from_str::<Vec<String>>(&tags_text)?;
            (&*core).set_tags(&id, &tags)
        })
    };
    match result {
        Ok(()) => {
            clear_last_error();
            true
        }
        Err(error) => {
            set_last_error(error);
            false
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_touch_item(core: *mut OpenCbCore, id: *const c_char) -> bool {
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return false;
    }
    match unsafe { cstr_to_string(id) }.and_then(|id| unsafe { &*core }.touch_item(&id)) {
        Ok(()) => {
            clear_last_error();
            true
        }
        Err(error) => {
            set_last_error(error);
            false
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_apply_retention(
    core: *mut OpenCbCore,
    max_items: usize,
    max_storage_mb: usize,
    preserve_pinned: bool,
) -> isize {
    if core.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return -1;
    }
    let policy = RetentionPolicy {
        max_items,
        max_storage_mb,
        preserve_pinned,
    };
    match unsafe { &*core }.apply_retention(policy) {
        Ok(removed) => {
            clear_last_error();
            removed as isize
        }
        Err(error) => {
            set_last_error(error);
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_get_blob(
    core: *mut OpenCbCore,
    id: *const c_char,
    out_len: *mut usize,
) -> *mut c_uchar {
    if core.is_null() || out_len.is_null() {
        set_last_error(OpenCbError::InvalidFfiInput);
        return std::ptr::null_mut();
    }
    let result = unsafe { cstr_to_string(id) }.and_then(|id| unsafe { &*core }.get_blob(&id));
    match result {
        Ok(Some(bytes)) => {
            unsafe {
                *out_len = bytes.len();
            }
            clear_last_error();
            let mut boxed = bytes.into_boxed_slice();
            let ptr = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            ptr
        }
        Ok(None) => {
            unsafe {
                *out_len = 0;
            }
            clear_last_error();
            std::ptr::null_mut()
        }
        Err(error) => {
            set_last_error(error);
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn opencb_blob_free(ptr: *mut c_uchar, len: usize) {
    if !ptr.is_null() {
        unsafe {
            drop(Vec::from_raw_parts(ptr, len, len));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captures_and_deduplicates_text() {
        let core = OpenCbCore::open_memory("windows-dev").unwrap();
        let first = core.capture_text("hello OpenCB", Some("test")).unwrap();
        let second = core.capture_text("hello OpenCB", Some("test")).unwrap();

        assert_eq!(first.id, second.id);
        assert_eq!(core.list_items(10, 0).unwrap().len(), 1);
    }

    #[test]
    fn searches_with_fts() {
        let core = OpenCbCore::open_memory("windows-dev").unwrap();
        core.capture_text("rust powered clipboard history", None)
            .unwrap();
        core.capture_text("unrelated note", None).unwrap();

        let results = core.search_items("clipboard", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].preview, "rust powered clipboard history");
    }

    #[test]
    fn retention_preserves_pinned_items() {
        let core = OpenCbCore::open_memory("windows-dev").unwrap();
        let pinned = core.capture_text("keep me", None).unwrap();
        core.set_pinned(&pinned.id, true).unwrap();
        core.capture_text("drop me one", None).unwrap();
        core.capture_text("drop me two", None).unwrap();

        let removed = core.apply_retention(RetentionPolicy {
            max_items: 1,
            max_storage_mb: 1024,
            preserve_pinned: true,
        });

        assert_eq!(removed.unwrap(), 2);
        let remaining = core.list_items(10, 0).unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].id, pinned.id);
    }

    #[test]
    fn list_order_uses_recency_without_pin_priority() {
        let core = OpenCbCore::open_memory("windows-dev").unwrap();
        let pinned = core.capture_text("pinned older item", None).unwrap();
        core.set_pinned(&pinned.id, true).unwrap();
        let newer = core.capture_text("newer regular item", None).unwrap();

        let items = core.list_items(10, 0).unwrap();
        assert_eq!(items[0].id, newer.id);
        assert_eq!(items[1].id, pinned.id);
    }

    #[test]
    fn touching_item_moves_it_to_top() {
        let core = OpenCbCore::open_memory("windows-dev").unwrap();
        let first = core.capture_text("first item", None).unwrap();
        let second = core.capture_text("second item", None).unwrap();

        assert_eq!(core.list_items(10, 0).unwrap()[0].id, second.id);
        core.touch_item(&first.id).unwrap();

        assert_eq!(core.list_items(10, 0).unwrap()[0].id, first.id);
    }

    #[test]
    fn creates_pairing_code_and_trusted_device() {
        let core = OpenCbCore::open_memory("windows-dev").unwrap();
        let code = core.create_pairing_code();
        let device = core.trust_device("Laptop", &code.public_key).unwrap();

        assert!(!code.code.is_empty());
        assert!(device.trusted);
        assert_eq!(core.list_devices().unwrap().len(), 2);
    }
}
