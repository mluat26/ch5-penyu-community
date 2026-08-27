import { createClient } from "npm:@supabase/supabase-js@2";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 16_384;

type ReadingPayload = {
  sensor_id?: unknown;
  temperature?: unknown;
  timestamp?: unknown;
  position?: unknown;
  depth_cm?: unknown;
  alert?: unknown;
  sensor_status?: unknown;
  battery_voltage?: unknown;
  signal_rssi_dbm?: unknown;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function optionalNumber(value: unknown): number | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function optionalString(value: unknown, maxLength = 100): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  return typeof value === "string" && value.length <= maxLength ? value : undefined;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return json(413, { error: "Payload too large" });
  }

  let payload: ReadingPayload;
  try {
    const body = await request.text();
    if (new TextEncoder().encode(body).byteLength > MAX_BODY_BYTES) {
      return json(413, { error: "Payload too large" });
    }
    payload = JSON.parse(body);
  } catch {
    return json(400, { error: "Invalid JSON payload" });
  }

  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    return json(400, { error: "A JSON object is required" });
  }

  const sensorId = payload.sensor_id;
  const temperature = payload.temperature;
  if (typeof sensorId !== "string" || !UUID_PATTERN.test(sensorId)) {
    return json(400, { error: "A valid sensor_id is required" });
  }
  if (
    typeof temperature !== "number" ||
    !Number.isFinite(temperature) ||
    temperature <= -50 ||
    temperature >= 100
  ) {
    return json(400, { error: "A valid temperature is required" });
  }

  const bearer = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  const deviceSecret = request.headers.get("x-device-secret") ?? bearer;
  if (!deviceSecret || !/^[0-9a-f]{64}$/i.test(deviceSecret)) {
    return json(401, { error: "Invalid device credential" });
  }

  const timestamp = optionalString(payload.timestamp, 64);
  const position = optionalString(payload.position);
  const depth = optionalNumber(payload.depth_cm);
  const alert = optionalString(payload.alert, 20);
  const sensorStatus = optionalString(payload.sensor_status, 20);
  const batteryVoltage = optionalNumber(payload.battery_voltage);
  const signalRssi = optionalNumber(payload.signal_rssi_dbm);

  if (
    (payload.timestamp !== undefined && timestamp === undefined) ||
    (typeof timestamp === "string" && Number.isNaN(Date.parse(timestamp))) ||
    (payload.position !== undefined && position === undefined) ||
    (payload.depth_cm !== undefined && depth === undefined) ||
    (payload.alert !== undefined && alert === undefined) ||
    (alert !== undefined && alert !== null && !["none", "low", "high", "critical"].includes(alert)) ||
    (payload.sensor_status !== undefined && sensorStatus === undefined) ||
    (sensorStatus !== undefined && sensorStatus !== null && !["online", "offline", "faulty"].includes(sensorStatus)) ||
    (payload.battery_voltage !== undefined && batteryVoltage === undefined) ||
    (payload.signal_rssi_dbm !== undefined &&
      signalRssi !== null &&
      (signalRssi === undefined || !Number.isInteger(signalRssi)))
  ) {
    return json(400, { error: "One or more reading fields are invalid" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("ingest-iot is missing its server-side Supabase configuration");
    return json(503, { error: "Ingestion service unavailable" });
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await supabase.rpc("ingest_iot_reading_authenticated", {
    p_sensor_id: sensorId,
    p_device_secret: deviceSecret,
    p_temperature: temperature,
    p_timestamp: timestamp ?? null,
    p_position: position ?? null,
    p_depth_cm: depth ?? null,
    p_alert: alert ?? null,
    p_sensor_status: sensorStatus ?? null,
    p_battery_voltage: batteryVoltage ?? null,
    p_signal_rssi_dbm: signalRssi ?? null,
  });

  if (error) {
    const message = error.message.toLowerCase();
    if (error.code === "28000" || message.includes("invalid device credential")) {
      return json(401, { error: "Invalid device credential" });
    }
    if (message.includes("not currently assigned")) {
      return json(409, { error: "Device is not assigned to an active nest" });
    }

    console.error("ingest-iot database failure", { code: error.code });
    return json(422, { error: "Reading was rejected" });
  }

  const reading = Array.isArray(data) ? data[0] : data;
  if (!reading) {
    console.error("ingest-iot returned no reading");
    return json(500, { error: "Reading was not recorded" });
  }

  return json(201, {
    id: reading.id,
    nest_id: reading.nest_id,
    timestamp: reading.timestamp,
  });
});
