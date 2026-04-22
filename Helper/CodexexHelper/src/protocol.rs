use std::io::{BufRead, Write};

use crate::{auth, quota};
use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u16 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "method", rename_all = "camelCase")]
pub enum HelperRequest {
    FetchSnapshot,
    BeginDeviceAuth,
    PollDeviceAuth { flow_id: String },
    SignOut,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum HelperResponse {
    Snapshot {
        #[serde(rename = "payloadJson")]
        payload_json: String,
    },
    DeviceAuthStarted {
        #[serde(rename = "flowId")]
        flow_id: String,
        #[serde(rename = "verificationUri")]
        verification_uri: String,
        #[serde(rename = "userCode")]
        user_code: String,
    },
    DeviceAuthPending {
        message: String,
    },
    SignedIn,
    SignedOut,
    Error {
        message: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HelperRequestEnvelope {
    #[serde(rename = "protocolVersion")]
    pub protocol_version: u16,
    #[serde(rename = "requestId")]
    pub request_id: Option<String>,
    pub method: String,
    #[serde(rename = "flow_id", alias = "flowId", default)]
    pub flow_id: Option<String>,
}

impl HelperRequestEnvelope {
    pub fn new(request: HelperRequest, request_id: Option<String>) -> Self {
        match request {
            HelperRequest::FetchSnapshot => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                method: "fetchSnapshot".to_string(),
                flow_id: None,
            },
            HelperRequest::BeginDeviceAuth => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                method: "beginDeviceAuth".to_string(),
                flow_id: None,
            },
            HelperRequest::PollDeviceAuth { flow_id } => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                method: "pollDeviceAuth".to_string(),
                flow_id: Some(flow_id),
            },
            HelperRequest::SignOut => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                method: "signOut".to_string(),
                flow_id: None,
            },
        }
    }

    fn into_request(self) -> Result<HelperRequest, String> {
        if self.request_id.as_deref().unwrap_or_default().trim().is_empty() {
            return Err("missing requestId".to_string());
        }

        match self.method.as_str() {
            "fetchSnapshot" => Ok(HelperRequest::FetchSnapshot),
            "beginDeviceAuth" => Ok(HelperRequest::BeginDeviceAuth),
            "pollDeviceAuth" => self
                .flow_id
                .filter(|value| value.trim().is_empty() == false)
                .map(|flow_id| HelperRequest::PollDeviceAuth { flow_id })
                .ok_or_else(|| "pollDeviceAuth requires flow_id".to_string()),
            "signOut" => Ok(HelperRequest::SignOut),
            method => Err(format!("unsupported method: {method}")),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HelperResponseEnvelope {
    #[serde(rename = "protocolVersion")]
    pub protocol_version: u16,
    #[serde(rename = "requestId", skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    #[serde(rename = "type")]
    pub response_type: String,
    #[serde(rename = "payloadJson", skip_serializing_if = "Option::is_none")]
    pub payload_json: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(rename = "flowId", skip_serializing_if = "Option::is_none")]
    pub flow_id: Option<String>,
    #[serde(rename = "verificationUri", skip_serializing_if = "Option::is_none")]
    pub verification_uri: Option<String>,
    #[serde(rename = "userCode", skip_serializing_if = "Option::is_none")]
    pub user_code: Option<String>,
}

impl HelperResponseEnvelope {
    pub fn from_response(request_id: Option<String>, response: HelperResponse) -> Self {
        match response {
            HelperResponse::Snapshot { payload_json } => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                response_type: "snapshot".to_string(),
                payload_json: Some(payload_json),
                message: None,
                flow_id: None,
                verification_uri: None,
                user_code: None,
            },
            HelperResponse::DeviceAuthStarted {
                flow_id,
                verification_uri,
                user_code,
            } => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                response_type: "deviceAuthStarted".to_string(),
                payload_json: None,
                message: None,
                flow_id: Some(flow_id),
                verification_uri: Some(verification_uri),
                user_code: Some(user_code),
            },
            HelperResponse::DeviceAuthPending { message } => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                response_type: "deviceAuthPending".to_string(),
                payload_json: None,
                message: Some(message),
                flow_id: None,
                verification_uri: None,
                user_code: None,
            },
            HelperResponse::SignedIn => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                response_type: "signedIn".to_string(),
                payload_json: None,
                message: None,
                flow_id: None,
                verification_uri: None,
                user_code: None,
            },
            HelperResponse::SignedOut => Self {
                protocol_version: PROTOCOL_VERSION,
                request_id,
                response_type: "signedOut".to_string(),
                payload_json: None,
                message: None,
                flow_id: None,
                verification_uri: None,
                user_code: None,
            },
            HelperResponse::Error { message } => Self::error(request_id, message),
        }
    }

    pub fn error(request_id: Option<String>, message: String) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            request_id,
            response_type: "error".to_string(),
            payload_json: None,
            message: Some(message),
            flow_id: None,
            verification_uri: None,
            user_code: None,
        }
    }
}

pub fn handle_request(request: HelperRequest) -> HelperResponse {
    match dispatch_request(request) {
        Ok(response) => response,
        Err(err) => HelperResponse::Error {
            message: err.to_string(),
        },
    }
}

fn dispatch_request(request: HelperRequest) -> anyhow::Result<HelperResponse> {
    match request {
        HelperRequest::FetchSnapshot => quota::fetch_snapshot(),
        HelperRequest::BeginDeviceAuth => auth::begin_device_auth(),
        HelperRequest::PollDeviceAuth { flow_id } => auth::poll_device_auth(&flow_id),
        HelperRequest::SignOut => auth::sign_out(),
    }
}

pub fn handle_line(line: &str) -> HelperResponse {
    match serde_json::from_str::<HelperRequest>(line) {
        Ok(request) => handle_request(request),
        Err(err) => HelperResponse::Error {
            message: format!("invalid request: {err}"),
        },
    }
}

pub fn handle_wire_line(line: &str) -> HelperResponseEnvelope {
    match serde_json::from_str::<HelperRequestEnvelope>(line) {
        Ok(envelope) => {
            let request_id = envelope.request_id.clone();
            if envelope.protocol_version != PROTOCOL_VERSION {
                return HelperResponseEnvelope::error(
                    request_id,
                    format!(
                        "unsupported protocol version {} (expected {})",
                        envelope.protocol_version, PROTOCOL_VERSION
                    ),
                );
            }

            match envelope.into_request() {
                Ok(request) => HelperResponseEnvelope::from_response(request_id, handle_request(request)),
                Err(message) => HelperResponseEnvelope::error(request_id, format!("invalid request: {message}")),
            }
        }
        Err(err) => HelperResponseEnvelope::error(None, format!("invalid request: {err}")),
    }
}

pub fn process_stream<R: BufRead, W: Write>(reader: R, writer: &mut W) -> anyhow::Result<()> {
    for line in reader.lines() {
        let response = match line {
            Ok(line) => handle_wire_line(&line),
            Err(err) => HelperResponseEnvelope::error(None, format!("input error: {err}")),
        };
        writeln!(writer, "{}", serde_json::to_string(&response)?)?;
        writer.flush()?;
    }

    Ok(())
}
