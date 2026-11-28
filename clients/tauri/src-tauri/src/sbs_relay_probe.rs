//! TLS-only headset LAN relay, started on demand by the native HMD panel.
//! No arbitrary asset bridge or control commands. Invitations are single-use.
use ring::rand::{SecureRandom, SystemRandom};
use subtle::ConstantTimeEq;
use serde::{Deserialize, Serialize};
use serde_json::{Value, Map};
use std::{
    net::{IpAddr, Ipv4Addr, SocketAddr},
    fs, path::PathBuf,
    sync::{atomic::{AtomicBool, AtomicU64, Ordering}, Arc, Mutex, OnceLock},
    time::{Duration, Instant},
};
use tauri::{AppHandle, Manager, WebviewWindow};
use tauri_plugin_dialog::DialogExt;
use tokio::{
    io::{AsyncReadExt, AsyncWrite, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::{Mutex as AsyncMutex, Notify, Semaphore},
    time::timeout,
};
use tokio_rustls::{
    rustls::{pki_types::{pem::PemObject, CertificateDer, PrivateKeyDer}, ServerConfig},
    TlsAcceptor,
};

const TTL: Duration = Duration::from_secs(600);
const MAX_HEADERS: usize = 8192;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(8);
const SESSION_TTL: Duration = Duration::from_secs(60 * 60);
const MAX_WORLD_BYTES: usize = 256 * 1024;
const MAX_RELAY_ENTITIES: usize = 256;

const PROOF_PAGE: &str = r##"<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SunRacer - LAN Relay Proof</title>
<style>
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#030b16;color:#d9fff5;font:16px system-ui,sans-serif}
main{max-width:26rem;border:1px solid #56d3c2;border-radius:12px;padding:1.5rem;margin:1rem;background:#0b2530}
h1{font-size:1.25rem;margin-top:0}small{color:#a1c5ca}
</style></head><body><main><h1>SUNRACER - LOCAL LINK</h1>
<p id="status" role="status">Checking secure laptop connection...</p>
<small>Encrypted LAN world-state relay. Flight and combat remain laptop-only.</small>
</main><script>
(async()=>{
  const status=document.querySelector("#status");
  // Only the same laptop's existing HTTPS headset page can receive this
  // boolean confirmation. Never post the invitation or game credentials.
  const postParent=(message)=>{
    if(window.parent!==window){
      window.parent.postMessage(message,"https://"+location.hostname+":4443");
    }
  };
  const report=(passed)=>postParent({type:"sunracer:relay-proof",passed});
  const reportHeartbeat=()=>postParent({type:"sunracer:relay-heartbeat"});
  const token=location.hash.startsWith("#")?location.hash.slice(1):"";
  history.replaceState(null,"","/relay-check");
  if(!/^[0-9a-f]{48}$/.test(token)){
    status.textContent="Invalid local invitation. Scan a fresh PILOT HMD QR code.";
    report(false);
    return;
  }
  try{
    const result=await fetch("/relay/prove",{method:"POST",
      headers:{"Authorization":"Bearer "+token},
      cache:"no-store",credentials:"omit",referrerPolicy:"no-referrer"});
    if(!result.ok){
      status.textContent="Invitation expired, already used or rejected.";
      report(false);
      return;
    }
    const proof=await result.json();
    if(!/^[0-9a-f]{48}$/.test(proof.stream_token||""))throw new Error("Invalid LAN session");
    status.textContent="SECURE LAN LINK CONFIRMED. Receiving world state...";
    report(true);
    let since=0;
    while(true){
      // The stream token stays inside this isolated, TLS-only document.
      // Parent receives ONLY filtered visual world maps.
      const response=await fetch("/relay/state?since="+since,{
        method:"GET",headers:{"Authorization":"Bearer "+proof.stream_token},
        cache:"no-store",credentials:"omit",referrerPolicy:"no-referrer"
      });
      if(response.status===204){
        reportHeartbeat();
        continue;
      }
      if(!response.ok)throw new Error("Local world stream unavailable");
      const frame=await response.json();
      if(!Number.isSafeInteger(frame.seq)||frame.seq<=since||
         !frame.map||!Array.isArray(frame.map.entities))throw new Error("Invalid LAN world");
      since=frame.seq;
      postParent({type:"sunracer:relay-world",frame});
    }
  }catch{
    status.textContent="Connection failed. Check LAN reachability and the trusted TLS certificate.";
    report(false);
  }
})();
</script></body></html>"##;

#[derive(Serialize)]
pub struct ProbeInfo {
    pub url: String,
    pub expires_seconds: u64,
    pub warning: &'static str,
}
#[derive(Serialize)]
pub struct ProbeStatus {
    pub running: bool,
    pub verified: bool,
    pub frames_served: u64,
    pub bytes_served: u64,
}

struct RelayFrame { seq: u64, body: String }
struct Shared {
    token: AsyncMutex<Option<String>>,
    session: AsyncMutex<Option<String>>,
    latest: AsyncMutex<Option<RelayFrame>>,
    // Wake authenticated LAN readers immediately when a new visual frame arrives.
    // A 100ms sleep here previously added latency on top of server ticks.
    updated: Notify,
    expires: Instant,
    session_expires: Instant,
    verified: AtomicBool,
    frames_served: AtomicU64,
    bytes_served: AtomicU64,
}
struct Active {
    task: tauri::async_runtime::JoinHandle<()>,
    shared: Arc<Shared>,
}
static ACTIVE: OnceLock<Mutex<Option<Active>>> = OnceLock::new();
fn active() -> &'static Mutex<Option<Active>> {
    ACTIVE.get_or_init(|| Mutex::new(None))
}

fn private_lan(ip: Ipv4Addr) -> bool {
    let [a,b,_c,d] = ip.octets();
    d != 0 && d != 255 &&
        (a == 10 || (a == 172 && (16..=31).contains(&b)) ||
         (a == 192 && b == 168) || (a == 100 && (64..=127).contains(&b)))
}
// Pairing already discovers a phone-reachable HTTPS origin through Phoenix.
 // Bind the same local IPv4, not the OS default route (which may be a VPN).
fn select_bind(helmet_origin: Option<&str>, override_address: Option<&str>) -> Result<SocketAddr, String> {
    let ip: Ipv4Addr = helmet_origin
        .and_then(|origin| origin.strip_prefix("https://"))
        .and_then(|origin| origin.strip_suffix(":4443"))
        .and_then(|host| host.parse().ok())
        .filter(|ip| private_lan(*ip))
        .ok_or("Local relay needs the laptop's trusted HTTPS headset address on port 4443. Direct headset connection remains available.")?;
    let expected = SocketAddr::from((ip, 4455));
    if let Some(raw) = override_address {
        let address: SocketAddr = raw.parse()
            .map_err(|_| "Invalid optional SBS bind override.")?;
        if address != expected {
            return Err("SBS bind override must match the headset LAN address and port 4455.".into());
        }
    }
    Ok(expected)
}

fn bind_address(helmet_origin: Option<&str>) -> Result<SocketAddr, String> {
    select_bind(helmet_origin, std::env::var("SUNRACER_SBS_BIND").ok().as_deref())
}

#[derive(Deserialize, Serialize)]
struct RelayCredentials {
    cert: PathBuf,
    key: PathBuf,
}
fn credentials_dir(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app.path().app_config_dir().map_err(|error| error.to_string())?.join("sbs"))
}

fn credentials(app: &AppHandle) -> Result<RelayCredentials, String> {
    // Explicit overrides remain a developer escape hatch, not a requirement.
    match (std::env::var_os("SUNRACER_SBS_CERT"), std::env::var_os("SUNRACER_SBS_KEY")) {
        (Some(cert), Some(key)) => return Ok(RelayCredentials {cert: cert.into(), key: key.into()}),
        (None, None) => {},
        _ => return Err("Both optional SBS certificate overrides must be supplied together.".into()),
    }
    let dir = credentials_dir(app)?;
    let saved = dir.join("credentials.json");
    match fs::read_to_string(&saved) {
        Ok(content) => return serde_json::from_str(&content)
            .map_err(|_| "Saved headset certificate settings are invalid. Select the certificate again.".into()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {},
        Err(error) => return Err(format!("Cannot read headset certificate settings: {error}")),
    }
    let local = RelayCredentials {cert:dir.join("localhost.pem"),key:dir.join("localhost-key.pem")};
    if local.cert.is_file() && local.key.is_file() {return Ok(local)}
    // Compatibility with existing local Phoenix development installations.
    if let Ok(home) = app.path().home_dir() {
        let dev = home.join("SunRacer/apps/sunracer_web/priv/cert");
        let local = RelayCredentials {cert:dev.join("localhost.pem"),key:dev.join("localhost-key.pem")};
        if local.cert.is_file() && local.key.is_file() {return Ok(local)}
    }
    Err("Select the existing trusted headset certificate and matching key (one-time setup).".into())
}

#[tauri::command]
pub async fn configure_sbs_relay_tls(app: AppHandle, window: WebviewWindow) -> Result<bool, String> {
    crate::network::require_local(&window)?;
    // Native picker: no paths or key contents accepted from the webview.
    // Run the blocking dialogs away from the UI thread.
    tauri::async_runtime::spawn_blocking(move || {
        let Some(cert) = app.dialog().file().set_title("Select trusted headset certificate (PEM)")
            .add_filter("PEM certificate", &["pem", "crt"]).blocking_pick_file() else {return Ok(false)};
        let Some(key) = app.dialog().file().set_title("Select matching headset private key (PEM)")
            .add_filter("PEM key", &["pem", "key"]).blocking_pick_file() else {return Ok(false)};
        let selected = RelayCredentials {
            cert:cert.into_path().map_err(|_| "Choose a local certificate file.")?,
            key:key.into_path().map_err(|_| "Choose a local private key file.")?,
        };
        // Validate before persisting paths; never copy or expose private keys.
        tls_config(&selected)?;
        let dir = credentials_dir(&app)?;
        fs::create_dir_all(&dir).map_err(|error| error.to_string())?;
        let content = serde_json::to_vec_pretty(&selected).map_err(|error| error.to_string())?;
        fs::write(dir.join("credentials.json"), content).map_err(|error| error.to_string())?;
        Ok(true)
    }).await.map_err(|error| error.to_string())?
}

fn tls_config(credentials: &RelayCredentials) -> Result<Arc<ServerConfig>, String> {
    let cert = &credentials.cert;
    let key = &credentials.key;
    let certs: Vec<CertificateDer<'static>> = CertificateDer::pem_file_iter(cert)
        .map_err(|error| format!("SBS certificate cannot be read: {error}"))?
        .collect::<Result<_, _>>()
        .map_err(|error| format!("SBS certificate invalid: {error}"))?;
    if certs.is_empty() {return Err("SBS certificate PEM is empty.".into())}
    let key = PrivateKeyDer::from_pem_file(key)
        .map_err(|error| format!("SBS key cannot be loaded: {error}"))?;
    // Both aws-lc-rs and ring are enabled transitively by the Tauri/
    // reqwest dependency graph. ServerConfig::builder() panics when rustls
    // cannot choose a process-wide CryptoProvider automatically.
    // Select ring for THIS LAN listener rather than changing the global
    // cryptographic provider used by other parts of the desktop client.
    let config = ServerConfig::builder_with_provider(Arc::new(
        tokio_rustls::rustls::crypto::ring::default_provider(),
    ))
        .with_safe_default_protocol_versions()
        .map_err(|error| format!("SBS TLS protocol configuration invalid: {error}"))?
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|error| format!("SBS TLS certificate/key invalid: {error}"))?;
    Ok(Arc::new(config))
}
fn random_token() -> Result<String, String> {
    let mut bytes = [0u8; 24];
    SystemRandom::new().fill(&mut bytes)
        .map_err(|_| "Secure random generator unavailable; refusing pairing.".to_string())?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

#[tauri::command]
pub async fn start_sbs_relay_probe(app: AppHandle, window: WebviewWindow, helmet_origin: Option<String>) -> Result<ProbeInfo, String> {
    crate::network::require_local(&window)?;
    if window.label() != "main" {
        return Err("The SBS relay requires the local Tauri main game window.".into())
    }
    if active().lock().map_err(|_| "Relay state locked.")?.is_some() {
        return Err("SBS test already running. Stop it before making another invitation.".into())
    }
    // Validate cert and exact LAN address before binding; NEVER use plain HTTP.
    let address = bind_address(helmet_origin.as_deref())?;
    let config = tls_config(&credentials(&app)?)?;
    let token = random_token()?;
    let listener = TcpListener::bind(address).await
        .map_err(|error| format!("Unable to bind secure SBS listener: {error}"))?;
    let shared = Arc::new(Shared {
        token: AsyncMutex::new(Some(token.clone())),
        session: AsyncMutex::new(None),
        latest: AsyncMutex::new(None),
        updated: Notify::new(),
        expires: Instant::now() + TTL,
        session_expires: Instant::now() + SESSION_TTL,
        verified: AtomicBool::new(false),
        frames_served: AtomicU64::new(0),
        bytes_served: AtomicU64::new(0),
    });
    let task_shared = Arc::clone(&shared);
    let task = tauri::async_runtime::spawn(async move {
        serve(listener, TlsAcceptor::from(config), task_shared, address).await;
    });
    let mut state = active().lock().map_err(|_| "Relay state locked.")?;
    if state.is_some() {
        task.abort();
        return Err("SBS test started concurrently. Try again.".into())
    }
    *state = Some(Active {task, shared});
    Ok(ProbeInfo {
        // Fragment is never sent to the LAN server. JS immediately clears it.
        url: format!("https://{address}/relay-check#{token}"),
        expires_seconds: TTL.as_secs(),
        warning: "The phone must trust the laptop's TLS certificate. This is a one-time connection proof, not a game-state relay.",
    })
}

#[tauri::command]
pub fn sbs_relay_probe_status(window: WebviewWindow) -> Result<ProbeStatus, String> {
    crate::network::require_local(&window)?;
    let state = active().lock().map_err(|_| "Relay state locked.")?;
    Ok(match state.as_ref() {
        Some(p) => ProbeStatus {
            running: true,
            verified: p.shared.verified.load(Ordering::Acquire),
            frames_served: p.shared.frames_served.load(Ordering::Relaxed),
            bytes_served: p.shared.bytes_served.load(Ordering::Relaxed),
        },
        None => ProbeStatus {running: false, verified: false,
                             frames_served: 0, bytes_served: 0},
    })
}

#[tauri::command]
pub async fn stop_sbs_relay_probe(window: WebviewWindow) -> Result<(), String> {
    crate::network::require_local(&window)?;
    // Drop the synchronous guard BEFORE awaiting the async challenge lock.
    // Existing accepted connections may still be mid-request after the
    // listener task stops. Revoke their one-time token as well.
    let probe = {
        active().lock().map_err(|_| "Relay state locked.")?.take()
    };
    if let Some(p) = probe {
        *p.shared.token.lock().await = None;
        *p.shared.session.lock().await = None;
        *p.shared.latest.lock().await = None;
        p.task.abort();
    }
    Ok(())
}

// The desktop is the ONLY producer. Its main Webview's native-only Tauri
// capability is enforced before accepting a visual world projection.
#[tauri::command]
pub async fn publish_sbs_relay_world(window: WebviewWindow, world: Value) -> Result<(), String> {
    crate::network::require_local(&window)?;
    let shared = {
        active().lock().map_err(|_| "Relay state locked.")?
            .as_ref().map(|p| Arc::clone(&p.shared))
    };
    let Some(shared) = shared else { return Ok(()); };
    let filtered = sanitize_world(&world)?;
    let mut latest = shared.latest.lock().await;
    let seq = latest.as_ref().map_or(1, |v| v.seq.saturating_add(1));
    let body = serde_json::to_string(&serde_json::json!({"seq":seq,"map":filtered}))
        .map_err(|_| "Cannot encode relay world.")?;
    if body.len() > MAX_WORLD_BYTES {
        return Err("Relay world exceeds maximum LAN payload.".into());
    }
    *latest = Some(RelayFrame { seq, body });
    drop(latest);
    shared.updated.notify_waiters();
    Ok(())
}

// Native allowlists are a second security boundary: never trust even a
// bundled JavaScript publisher to forward arbitrary nested world objects.
fn pick_scalars(input: &Value, keys: &[&str]) -> Value {
    let mut clean = Map::new();
    for key in keys {
        if let Some(value) = input.get(*key) {
            let allowed = match value {
                Value::Null | Value::Bool(_) | Value::Number(_) => true,
                Value::String(text) => text.len() <= 96,
                _ => false,
            };
            if allowed { clean.insert((*key).to_owned(), value.clone()); }
        }
    }
    Value::Object(clean)
}
fn picked_vector(input: &Value) -> Value {
    pick_scalars(input, &["x","y","z","w","pitch","roll","yaw","room_id"])
}
// Native second boundary for the opt-in visual-only pose. Never accept a
// pilot ID not present in the same sanitized world, or arbitrary nested data.
fn sanitized_visual_pose(input: &Value, entities: &[Value]) -> Option<Value> {
    let id = input.get("id")?;
    if !(id.is_number() || id.is_string()) ||
        !entities.iter().any(|entity| entity.get("id") == Some(id)) {
        return None;
    }
    let pos = input.get("position_3d")?;
    let rot = input.get("orientation")?;
    let f = |obj: &Value, key: &str| {
        obj.get(key).and_then(Value::as_f64)
            .filter(|n| n.is_finite() && n.abs() <= 1e12)
    };
    let (x, y, z) = (f(pos, "x")?, f(pos, "y")?, f(pos, "z")?);
    let (qx, qy, qz, qw) =
        (f(rot, "x")?, f(rot, "y")?, f(rot, "z")?, f(rot, "w")?);
    let norm = (qx*qx + qy*qy + qz*qz + qw*qw).sqrt();
    if !(0.9..=1.1).contains(&norm) { return None; }
    let mut pose = serde_json::json!({
        "id": id, "position_3d": {"x":x,"y":y,"z":z},
        "orientation": {"x":qx/norm,"y":qy/norm,"z":qz/norm,"w":qw/norm},
    });
    // Optional laptop virtual-joystick deflection for the headset steering
    // line. Bounded scalars only; anything else is silently dropped.
    if let Some(steering) = input.get("steering") {
        let (sx, sy, aspect) = (f(steering, "x"), f(steering, "y"), f(steering, "aspect"));
        if let (Some(sx), Some(sy), Some(aspect)) = (sx, sy, aspect) {
            if sx.abs() <= 1.0 && sy.abs() <= 1.0 && (0.2..=5.0).contains(&aspect) {
                pose["steering"] = serde_json::json!({"x":sx,"y":sy,"aspect":aspect});
            }
        }
    }
    // Optional laptop camera body rates (rad/s) so the headset can keep
    // rotating smoothly between relayed poses. Bounded scalars only.
    if let Some(rates) = input.get("rates") {
        let bounded = |key: &str| f(rates, key).filter(|n| n.abs() <= 10.0);
        if let (Some(yaw), Some(pitch), Some(roll)) =
            (bounded("yaw"), bounded("pitch"), bounded("roll")) {
            pose["rates"] = serde_json::json!({"yaw":yaw,"pitch":pitch,"roll":roll});
        }
    }
    // Optional laptop-clock sample time (ms) for headset jitter removal.
    if let Some(t) = f(input, "t").filter(|t| *t >= 0.0) {
        pose["t"] = serde_json::json!(t);
    }
    Some(pose)
}

fn picked_array(input: &Value, max: usize, allowed: &[&str]) -> Value {
    Value::Array(input.as_array().map(|items| items.iter().take(max)
        .map(|item| pick_scalars(item, allowed)).collect()).unwrap_or_default())
}

fn sanitize_world(raw: &Value) -> Result<Value, String> {
    let tick = raw.get("tick").and_then(Value::as_u64)
        .ok_or("Missing authoritative tick.")?;
    let map_id = raw.get("map_id").and_then(Value::as_str)
        .filter(|id| !id.is_empty() && id.len() <= 96)
        .ok_or("Invalid map identity.")?;
    let entities = raw.get("entities").and_then(Value::as_array)
        .filter(|rows| rows.len() <= MAX_RELAY_ENTITIES)
        .ok_or("Invalid or oversized entity list.")?;
    let scalars = [
        "id","kind","npc_type_id","ship_class","display_name","status",
        "angle","throttle","flight_mode","target_id","hull","max_hull",
        "shields","max_shields","attack_range",
    ];
    let vectors = ["position","position_3d","destination","destination_3d",
                   "orientation","attitude","velocity","angular_velocity"];
    let mut clean_entities = Vec::with_capacity(entities.len());
    for entity in entities {
        let mut clean = pick_scalars(entity, &scalars);
        if entity.get("id").is_none() || entity.get("kind").is_none() {
            return Err("Relay entity missing id or kind.".into());
        }
        for field in vectors {
            if let Some(value) = entity.get(field) {
                if let Some(out) = clean.as_object_mut() {
                    out.insert(field.into(), picked_vector(value));
                }
            }
        }
        clean_entities.push(clean);
    }
    let mut clean = Map::new();
    clean.insert("map_id".into(), Value::String(map_id.into()));
    clean.insert("tick".into(), Value::Number(tick.into()));
    // Borrow while still owned locally; inserting the array moves it.
    if let Some(pose) = raw.get("visual_pose")
        .and_then(|pose| sanitized_visual_pose(pose, &clean_entities)) {
        clean.insert("visual_pose".into(), pose);
    }
    clean.insert("entities".into(), Value::Array(clean_entities));
    if let Some(value) = raw.get("tick_ms") {
        if value.is_number() {clean.insert("tick_ms".into(), value.clone());}
    }
    if let Some(value) = raw.get("boundaries") {
        clean.insert("boundaries".into(),
            pick_scalars(value, &["width","height","radius"]));
    }
    if let Some(value) = raw.get("volume") {
        clean.insert("volume".into(),
            pick_scalars(value, &["altitude_min","altitude_max"]));
    }
    if let Some(base) = raw.get("orbital_base") {
        let mut visual = pick_scalars(base, &[
            "id","body_id","refinery_id","model","berth_count",
        ]);
        if let Some(position) = base.get("position_3d") {
            visual.as_object_mut().unwrap().insert(
                "position_3d".into(), picked_vector(position));
        }
        clean.insert("orbital_base".into(), visual);
    }
    if let Some(ids) = raw.get("docked_pilots").and_then(Value::as_array) {
        let limited = ids.iter().take(64).filter(|id| id.is_string() || id.is_number())
            .cloned().collect();
        clean.insert("docked_pilots".into(), Value::Array(limited));
    }
    if let Some(attendants) = raw.get("station_attendants") {
        clean.insert("station_attendants".into(), picked_array(attendants, 64, &[
            "id","name","display_name","room_id","x","y","z","role","station_id",
        ]));
    }
    if let Some(avatars) = raw.get("station_avatars").and_then(Value::as_array) {
        let limited = avatars.iter().take(64).map(|avatar| {
            let mut item = pick_scalars(avatar, &[
                "player_id","heading","room_id","x","y","z",
            ]);
            if let Some(position) = avatar.get("position") {
                item.as_object_mut().unwrap().insert(
                    "position".into(), picked_vector(position));
            }
            item
        }).collect();
        clean.insert("station_avatars".into(), Value::Array(limited));
    }
    let map = Value::Object(clean);
    if serde_json::to_vec(&map).map_err(|_| "Cannot encode world.")?.len() > MAX_WORLD_BYTES {
        return Err("Relay world exceeds 256 KiB.".into());
    }
    Ok(map)
}

// Tokens are generated as fixed-length hex strings. Compare their contents
// without data-dependent early exit; lengths are not secret.
fn tokens_match(expected: &str, candidate: &str) -> bool {
    bool::from(expected.as_bytes().ct_eq(candidate.as_bytes()))
}

async fn authorized_session(shared: &Shared, candidate: Option<&str>) -> bool {
    if !shared.verified.load(Ordering::Acquire) {return false}
    let expected = shared.session.lock().await;
    expected.as_deref().is_some_and(|secret| candidate.is_some_and(|value|
        tokens_match(secret, value)))
}

async fn serve(listener: TcpListener, tls: TlsAcceptor, shared: Arc<Shared>, address: SocketAddr) {
    let clients = Arc::new(Semaphore::new(8));
    loop {
        let Ok((socket, peer)) = listener.accept().await else {break};
        if !matches!(peer.ip(), IpAddr::V4(ip) if private_lan(ip) || ip.is_loopback()) {
            continue;
        }
        let Ok(permit) = Arc::clone(&clients).try_acquire_owned() else {continue};
        let tls = tls.clone();
        let shared = Arc::clone(&shared);
        tauri::async_runtime::spawn(async move {
            let _permit = permit;
            let _ = timeout(REQUEST_TIMEOUT, serve_one(socket, tls, shared, address)).await;
        });
    }
}

async fn serve_one(socket: TcpStream, acceptor: TlsAcceptor,
                   shared: Arc<Shared>, address: SocketAddr) -> std::io::Result<()> {
    let mut stream = acceptor.accept(socket).await?;
    let mut data = Vec::with_capacity(1024);
    let mut buffer = [0u8; 1024];
    while !data.windows(4).any(|w| w == b"\r\n\r\n") {
        let size = stream.read(&mut buffer).await?;
        if size == 0 {return Ok(())}
        data.extend_from_slice(&buffer[..size]);
        if data.len() > MAX_HEADERS {
            return respond(&mut stream, 431, "text/plain", "Request too large.").await
        }
    }
    let request = match std::str::from_utf8(&data) {
        Ok(s) => s,
        Err(_) => return respond(&mut stream, 400, "text/plain", "Invalid request.").await,
    };
    let (method, path, bearer) = match parse_request(request, address) {
        Some(x) => x,
        None => return respond(&mut stream, 400, "text/plain", "Invalid request.").await,
    };
    match (method, path) {
        ("GET", "/relay-check") =>
            respond(&mut stream, 200, "text/html; charset=utf-8", PROOF_PAGE).await,
        ("POST", "/relay/prove") => {
            let mut secret = shared.token.lock().await;
            let correct = Instant::now() < shared.expires &&
                secret.as_deref().is_some_and(|expected|
                    bearer.is_some_and(|candidate|
                        tokens_match(expected, candidate)));
            if correct { *secret = None; }
            drop(secret);
            if correct {
                // This newly issued session token stays inside the HTTPS
                // iframe and is never passed to the parent/QR/Phoenix.
                match random_token() {
                    Ok(session) => {
                        *shared.session.lock().await = Some(session.clone());
                        shared.verified.store(true, Ordering::Release);
                        let result = format!(
                            r#"{{"ok":true,"stream_token":"{session}"}}"#,
                        );
                        respond(&mut stream, 200, "application/json", &result).await
                    }
                    Err(_) => respond(&mut stream, 503, "text/plain", "Unavailable.").await,
                }
            } else {
                respond(&mut stream, 401, "application/json", r#"{"ok":false}"#).await
            }
        }
        ("GET", requested) if requested.starts_with("/relay/state?since=") => {
            let since = requested.strip_prefix("/relay/state?since=")
                .filter(|s| !s.is_empty() && s.len() <= 19 &&
                    s.bytes().all(|c| c.is_ascii_digit()))
                .and_then(|s| s.parse::<u64>().ok());
            if since.is_none() || Instant::now() >= shared.session_expires ||
                !authorized_session(&shared, bearer).await {
                return respond(&mut stream, 401, "text/plain", "Unauthorized.").await;
            }
            let since = since.unwrap_or(0);
            let started = Instant::now();
            loop {
                // Register the waiter BEFORE inspecting the latest frame.
                // Tokio Notify::enable prevents a wake-up from being lost if
                // the desktop publishes between our snapshot check and wait.
                let notified = shared.updated.notified();
                tokio::pin!(notified);
                notified.as_mut().enable();

                // Single current-state buffer; slow phones never build queues.
                let response = {
                    let frame = shared.latest.lock().await;
                    frame.as_ref().filter(|f| f.seq > since)
                        .map(|f| f.body.clone())
                };
                if let Some(response) = response {
                    let outcome = respond(&mut stream, 200, "application/json", &response).await;
                    if outcome.is_ok() {
                        shared.frames_served.fetch_add(1, Ordering::Relaxed);
                        shared.bytes_served.fetch_add(response.len() as u64, Ordering::Relaxed);
                    }
                    return outcome;
                }
                let remaining = Duration::from_secs(4).saturating_sub(started.elapsed());
                if remaining.is_zero() {
                    return respond(&mut stream, 204, "text/plain", "").await;
                }
                // No busy-poll interval: send the next published frame as soon
                // as it is available, with the same 4s idle heartbeat limit.
                if tokio::time::timeout(remaining, &mut notified).await.is_err() {
                    return respond(&mut stream, 204, "text/plain", "").await;
                }
            }
        }
        _ => respond(&mut stream, 404, "text/plain", "Not found.").await,
    }
}

fn parse_request<'a>(headers: &'a str, address: SocketAddr)
    -> Option<(&'a str, &'a str, Option<&'a str>)> {
    let mut parts = headers.split("\r\n");
    let mut first = parts.next()?.split_ascii_whitespace();
    let method = first.next()?;
    let path = first.next()?;
    if first.next()? != "HTTP/1.1" || first.next().is_some() {return None}
    let mut host = false;
    let mut bearer = None;
    for line in parts {
        if line.is_empty() {break}
        let (name, value) = line.split_once(':')?;
        let value = value.trim();
        if name.eq_ignore_ascii_case("host") {
            if host || value != address.to_string() {return None}
            host = true;
        } else if name.eq_ignore_ascii_case("authorization") {
            if bearer.is_some() {return None}
            bearer = value.strip_prefix("Bearer ");
        } else if name.eq_ignore_ascii_case("content-length") {
            if value != "0" {return None}
        } else if name.eq_ignore_ascii_case("transfer-encoding") {
            return None;
        }
    }
    host.then_some((method, path, bearer))
}

async fn respond<S: AsyncWrite + Unpin>(
    stream: &mut S, code: u16, content_type: &str, body: &str,
) -> std::io::Result<()> {
    let status = match code {
        200 => "OK", 204 => "No Content", 400 => "Bad Request",
        401 => "Unauthorized", 404 => "Not Found",
        431 => "Request Header Fields Too Large",
        503 => "Service Unavailable", _ => "Error",
    };
    let head = format!(
        "HTTP/1.1 {code} {status}\r\nContent-Type: {content_type}\r\n\
         Content-Length: {}\r\nCache-Control: no-store\r\n\
         Referrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\n\
         Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; \
         style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'\r\n\
         Connection: close\r\n\r\n",
        body.len()
    );
    stream.write_all(head.as_bytes()).await?;
    stream.write_all(body.as_bytes()).await?;
    stream.shutdown().await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_comparison_accepts_only_matching_values() {
        let expected = "0123456789abcdef".repeat(3);
        assert!(tokens_match(&expected, &expected));
        assert!(!tokens_match(&expected, &format!("f{}", &expected[1..])));
        assert!(!tokens_match(&expected, &format!("{}0", &expected[..47])));
        assert!(!tokens_match(&expected, &expected[..47]));
        assert!(!tokens_match(&expected, ""));
        assert!(!tokens_match(&expected, &format!("{expected}0")));
    }
    #[test]
    fn local_tls_selects_ring_without_requiring_a_global_crypto_provider() {
        // Reproduces the previously panicking initial configuration step:
        // the binary enables both rustls crypto backends transitively.
        let config = ServerConfig::builder_with_provider(Arc::new(
            tokio_rustls::rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions();
        assert!(config.is_ok(), "explicit ring TLS provider must be usable");
    }

    #[test]
    fn projection_removes_credentials_cargo_and_unlisted_fields() {
        let original = serde_json::json!({
            "map_id":"sol:free_earth","tick":7,"account_token":"secret",
            "entities":[{"id":3,"kind":"pilot","position_3d":{"x":1,"y":2,"z":3},
                        "cargo":{"parts":12},"credentials":"secret"}]
        });
        let map = sanitize_world(&original).unwrap();
        assert!(map.get("account_token").is_none());
        assert_eq!(map["entities"][0]["position_3d"]["x"], 1);
        assert!(map["entities"][0].get("cargo").is_none());
        assert!(map["entities"][0].get("credentials").is_none());
        let many: Vec<Value> = (0..=MAX_RELAY_ENTITIES)
            .map(|i|serde_json::json!({"id":i,"kind":"npc"})).collect();
        assert!(sanitize_world(&serde_json::json!({
            "map_id":"sol","tick":8,"entities":many
        })).is_err());
    }

    #[test]
    fn local_pose_is_numeric_scoped_and_never_mixes_private_fields() {
        let entities = vec![serde_json::json!({"id":3,"kind":"pilot"})];
        let valid = serde_json::json!({
            "id":3,"position_3d":{"x":1.0,"y":2.0,"z":3.0},
            "orientation":{"x":0.0,"y":0.0,"z":0.0,"w":1.0},
            "secret":"DO_NOT_RELAY"
        });
        let pose = sanitized_visual_pose(&valid, &entities).unwrap();
        assert!(pose.get("secret").is_none());
        assert_eq!(pose["position_3d"]["x"], 1.0);
        assert!(sanitized_visual_pose(&serde_json::json!({"id":4,
            "position_3d":valid["position_3d"],
            "orientation":valid["orientation"]}), &entities).is_none());
        assert!(sanitized_visual_pose(&serde_json::json!({"id":3,
            "position_3d":valid["position_3d"],
            "orientation":{"x":0,"y":0,"z":0,"w":0}}), &entities).is_none());
        // Optional steering line: bounded scalars pass, anything else drops.
        let mut steered = valid.clone();
        steered["steering"] = serde_json::json!({"x":0.5,"y":-0.25,"aspect":1.6,"extra":"no"});
        let pose = sanitized_visual_pose(&steered, &entities).unwrap();
        assert_eq!(pose["steering"], serde_json::json!({"x":0.5,"y":-0.25,"aspect":1.6}));
        for bad in [serde_json::json!({"x":1.5,"y":0,"aspect":1.6}),
                    serde_json::json!({"x":0,"y":0,"aspect":50}),
                    serde_json::json!({"x":"0.5","y":0,"aspect":1.6}),
                    serde_json::json!("left")] {
            let mut input = valid.clone();
            input["steering"] = bad;
            let pose = sanitized_visual_pose(&input, &entities).unwrap();
            assert!(pose.get("steering").is_none());
        }
        // Optional body rates: bounded scalars pass, anything else drops.
        let mut turning = valid.clone();
        turning["rates"] = serde_json::json!({"yaw":1.5,"pitch":-0.5,"roll":0.0,"x":9});
        let pose = sanitized_visual_pose(&turning, &entities).unwrap();
        assert_eq!(pose["rates"], serde_json::json!({"yaw":1.5,"pitch":-0.5,"roll":0.0}));
        turning["rates"] = serde_json::json!({"yaw":50.0,"pitch":0.0,"roll":0.0});
        assert!(sanitized_visual_pose(&turning, &entities).unwrap().get("rates").is_none());
        turning["rates"] = serde_json::json!({"yaw":1.0,"pitch":0.0});
        assert!(sanitized_visual_pose(&turning, &entities).unwrap().get("rates").is_none());
        // Optional sample time: finite, non-negative number only.
        let mut stamped = valid.clone();
        stamped["t"] = serde_json::json!(12345.5);
        assert_eq!(sanitized_visual_pose(&stamped, &entities).unwrap()["t"], 12345.5);
        stamped["t"] = serde_json::json!("soon");
        assert!(sanitized_visual_pose(&stamped, &entities).unwrap().get("t").is_none());
        stamped["t"] = serde_json::json!(-4.0);
        assert!(sanitized_visual_pose(&stamped, &entities).unwrap().get("t").is_none());
    }
    #[test]
    fn listener_accepts_only_explicit_private_addresses() {
        for ip in ["8.8.8.8", "127.0.0.1", "0.0.0.0", "169.254.1.10"] {
            assert!(!private_lan(ip.parse().unwrap()), "{ip}");
        }
        for ip in ["10.1.2.3", "172.31.2.3", "192.168.1.3", "100.100.1.3"] {
            assert!(private_lan(ip.parse().unwrap()), "{ip}");
        }
    }
    #[test]
    fn automatic_bind_matches_the_discovered_headset_origin() {
        assert_eq!(select_bind(Some("https://192.168.1.8:4443"), None).unwrap(),
            "192.168.1.8:4455".parse::<SocketAddr>().unwrap());
        assert!(select_bind(Some("https://192.168.1.8:4443"), Some("192.168.1.8:4455")).is_ok());
        for invalid in [None, Some("http://192.168.1.8:4443"), Some("https://8.8.8.8:4443"),
                        Some("https://127.0.0.1:4443"), Some("https://0.0.0.0:4443"),
                        Some("https://192.168.1.8:4443/path"), Some("https://192.168.1.8:4444")] {
            assert!(select_bind(invalid, None).is_err());
        }
        assert!(select_bind(Some("https://192.168.1.8:4443"), Some("192.168.1.9:4455")).is_err());
        assert!(select_bind(Some("https://192.168.1.8:4443"), Some("0.0.0.0:4455")).is_err());
    }

    #[test]
    fn malformed_http_and_cross_host_requests_fail() {
        let addr = "192.168.1.8:4455".parse().unwrap();
        assert!(parse_request(
            "POST /relay/prove HTTP/1.1\r\nHost: 192.168.1.8:4455\r\nAuthorization: Bearer x\r\nContent-Length: 0\r\n\r\n", addr
        ).is_some());
        assert!(parse_request("GET /relay-check HTTP/1.1\r\nHost: evil.invalid\r\n\r\n", addr).is_none());
        assert!(parse_request("POST /relay/prove HTTP/1.1\r\nHost: 192.168.1.8:4455\r\nTransfer-Encoding: chunked\r\n\r\n", addr).is_none());
    }
    #[test]
    fn invitations_use_192_bits_of_os_randomness() {
        let first = random_token().unwrap();
        let second = random_token().unwrap();
        assert_eq!(first.len(), 48);
        assert_ne!(first, second);
        assert!(first.bytes().all(|b| b.is_ascii_hexdigit()));
    }
}
