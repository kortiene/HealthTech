//! Per-IP sliding-window rate limiter for the blob proxy (issue #104).
//!
//! Uses a `tokio::sync::Mutex`-protected `HashMap<IpAddr, Bucket>` — cheap for the low
//! concurrency of a blob proxy. The window resets per IP rather than globally, so a burst
//! from one client does not consume quota for others.
//!
//! Two pre-configured limits:
//! - [`RateLimiter::write_limiter`] : 60 requests / 60 s per IP on mutating paths (PUT, DELETE).
//! - [`RateLimiter::read_limiter`]  : 300 requests / 60 s per IP on read paths (GET).

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::http::StatusCode;
use axum::response::IntoResponse;
use tokio::sync::Mutex;

/// A per-IP sliding-window bucket.
struct Bucket {
    count: u32,
    window_start: Instant,
}

/// Shared per-IP rate limiter. Cheap to clone (inner `Arc`).
#[derive(Clone)]
pub struct RateLimiter {
    buckets: Arc<Mutex<HashMap<IpAddr, Bucket>>>,
    /// Maximum number of requests allowed within `window`.
    max_requests: u32,
    window: Duration,
}

impl RateLimiter {
    pub fn new(max_requests: u32, window: Duration) -> Self {
        Self {
            buckets: Arc::new(Mutex::new(HashMap::new())),
            max_requests,
            window,
        }
    }

    /// Pre-configured limiter for mutating paths: 60 req / 60 s.
    pub fn write_limiter() -> Self {
        Self::new(60, Duration::from_secs(60))
    }

    /// Pre-configured limiter for read paths: 300 req / 60 s.
    pub fn read_limiter() -> Self {
        Self::new(300, Duration::from_secs(60))
    }

    /// Returns `true` if the request should proceed, `false` if it is rate-limited.
    ///
    /// The window slides per IP: the first request in a new window resets the counter.
    pub async fn check(&self, ip: IpAddr) -> bool {
        let mut buckets = self.buckets.lock().await;
        let now = Instant::now();
        let bucket = buckets.entry(ip).or_insert(Bucket {
            count: 0,
            window_start: now,
        });
        if now.duration_since(bucket.window_start) >= self.window {
            bucket.count = 1;
            bucket.window_start = now;
            true
        } else if bucket.count < self.max_requests {
            bucket.count += 1;
            true
        } else {
            false
        }
    }
}

/// Response returned when a client exceeds its rate limit.
pub fn rate_limit_exceeded() -> impl IntoResponse {
    (
        StatusCode::TOO_MANY_REQUESTS,
        [("Retry-After", "60")],
        "rate limit exceeded — retry after 60 s",
    )
}
