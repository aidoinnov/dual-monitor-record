#!/usr/bin/env node
import { createInterface } from "node:readline";

const baseURL = process.env.DUALREC_URL || "http://127.0.0.1:17842";
const routes = {
  start_recording: ["POST", "/v1/recording/start"],
  stop_recording: ["POST", "/v1/recording/stop"],
  toggle_recording: ["POST", "/v1/recording/toggle"],
  get_status: ["GET", "/v1/status"],
  open_latest: ["POST", "/v1/latest/open"],
  reveal_latest: ["POST", "/v1/latest/reveal"],
  convert_latest_for_windows: ["POST", "/v1/latest/convert-windows"],
};

const tools = Object.keys(routes).map((name) => ({
  name,
  description: name.replaceAll("_", " "),
  inputSchema: { type: "object", properties: {}, additionalProperties: false },
}));

async function callTool(name) {
  const route = routes[name];
  if (!route) throw new Error(`Unknown tool: ${name}`);
  const response = await fetch(`${baseURL}${route[1]}`, { method: route[0] });
  const text = await response.text();
  if (!response.ok) throw new Error(text);
  return { content: [{ type: "text", text }] };
}

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

const input = createInterface({ input: process.stdin, terminal: false });
input.on("line", async (line) => {
  let request;
  try { request = JSON.parse(line); } catch { return; }
  if (!request.id) return;
  try {
    let result;
    if (request.method === "initialize") {
      result = {
        protocolVersion: request.params?.protocolVersion || "2025-03-26",
        capabilities: { tools: {} },
        serverInfo: { name: "dual-monitor-recorder", version: "1.0.0" },
      };
    } else if (request.method === "tools/list") {
      result = { tools };
    } else if (request.method === "tools/call") {
      result = await callTool(request.params?.name);
    } else {
      throw new Error(`Method not found: ${request.method}`);
    }
    send({ jsonrpc: "2.0", id: request.id, result });
  } catch (error) {
    send({ jsonrpc: "2.0", id: request.id, error: { code: -32000, message: error.message } });
  }
});
