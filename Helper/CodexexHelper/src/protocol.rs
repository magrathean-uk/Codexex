use std::io::{BufRead, Write};

use crate::{auth, quota};
use serde::{Deserialize, Serialize};

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
    SignedIn,
    SignedOut,
    Error {
        message: String,
    },
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

pub fn process_stream<R: BufRead, W: Write>(reader: R, writer: &mut W) -> anyhow::Result<()> {
    for line in reader.lines() {
        let response = match line {
            Ok(line) => handle_line(&line),
            Err(err) => HelperResponse::Error {
                message: format!("input error: {err}"),
            },
        };
        writeln!(writer, "{}", serde_json::to_string(&response)?)?;
        writer.flush()?;
    }

    Ok(())
}
