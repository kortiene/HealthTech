//! Centralised HTTP error mapping for the blob API (issue #9).
//!
//! A backing-store failure maps to an HTTP status **without leaking any internal detail** — no
//! DSN, no backend error string, no PII — to the client or the logs (ADR 0004/0005). The response
//! body is the generic status reason phrase only.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

use crate::store::StoreError;

/// API-facing error, mapped from an internal [`StoreError`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiError {
    /// The backing store is unavailable. → `503 Service Unavailable`.
    Unavailable,
}

impl From<StoreError> for ApiError {
    fn from(err: StoreError) -> Self {
        match err {
            StoreError::Unavailable => ApiError::Unavailable,
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = match self {
            ApiError::Unavailable => StatusCode::SERVICE_UNAVAILABLE,
        };
        // Generic reason phrase only — never an internal detail.
        (status, status.canonical_reason().unwrap_or("error")).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::ApiError;
    use crate::store::StoreError;
    use axum::http::StatusCode;
    use axum::response::IntoResponse;

    #[test]
    fn store_unavailable_converts_to_api_unavailable() {
        assert_eq!(
            ApiError::from(StoreError::Unavailable),
            ApiError::Unavailable
        );
    }

    #[test]
    fn api_unavailable_response_is_503() {
        let resp = ApiError::Unavailable.into_response();
        assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[test]
    fn api_error_response_body_is_not_empty() {
        // Must carry a generic reason phrase — never an empty body, never internal detail.
        use http_body_util::BodyExt;
        let resp = ApiError::Unavailable.into_response();
        let body = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(resp.into_body().collect())
            .unwrap()
            .to_bytes();
        assert!(
            !body.is_empty(),
            "error response must include a reason phrase"
        );
        let text = std::str::from_utf8(&body).expect("reason phrase must be UTF-8");
        // Generic text only — no stack traces, DSNs, or internal detail.
        assert!(
            !text.contains("://"),
            "error body must not contain a connection string"
        );
    }

    #[test]
    fn api_error_derives_eq_and_debug() {
        assert_eq!(ApiError::Unavailable, ApiError::Unavailable);
        let _ = format!("{:?}", ApiError::Unavailable);
    }
}
