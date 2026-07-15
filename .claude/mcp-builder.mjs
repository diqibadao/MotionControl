#!/usr/bin/env node

// Minimal MCP server for MotionControl builds.
// Zero npm dependencies — speaks MCP over stdio via raw JSON-RPC.

import { spawn } from "child_process";
import fs from "fs";

const PROJECT = "/Users/diqibadao/Desktop/vibe项目/MotionControl";

// ── helpers ────────────────────────────────────────────────────────────

function send(obj) {
  const msg = JSON.stringify(obj) + "\n";
  fs.writeSync(1, msg); // fd 1 = stdout, synchronous, no buffering
}

function log(msg) {
  process.stderr.write(`[mc-builder] ${msg}\n`);
}

// ── tool definitions ───────────────────────────────────────────────────

const TOOLS = [
  {
    name: "swift_build",
    description: "Run 'swift build --disable-sandbox' in MotionControl project",
    inputSchema: {
      type: "object",
      properties: {
        extraArgs: { type: "string", description: "Extra args to swift build" },
      },
    },
  },
  {
    name: "swift_test",
    description: "Run 'swift test --disable-sandbox' in MotionControl project",
    inputSchema: {
      type: "object",
      properties: {
        extraArgs: { type: "string", description: "Extra args to swift test" },
      },
    },
  },
];

// ── execute command ────────────────────────────────────────────────────

function runTool(cmd, args, extraArgs) {
  return new Promise((resolve) => {
    const allArgs = [...args];
    if (extraArgs) allArgs.push(...extraArgs.trim().split(/\s+/));
    log(`running: ${cmd} ${allArgs.join(" ")}`);

    const proc = spawn(cmd, allArgs, {
      cwd: PROJECT,
      shell: false,
      env: { ...process.env, SWIFTPM_DISABLE_SANDBOX: "1" },
    });

    let stdout = "",
      stderr = "";
    proc.stdout.on("data", (d) => (stdout += d.toString()));
    proc.stderr.on("data", (d) => (stderr += d.toString()));

    proc.on("close", (code) => {
      const output = [stdout, stderr].filter(Boolean).join("\n");
      resolve({
        content: [
          {
            type: "text",
            text: output || `(exit code ${code}, no output)`,
          },
        ],
        isError: code !== 0,
      });
    });

    proc.on("error", (err) => {
      resolve({
        content: [{ type: "text", text: `Failed to spawn: ${err.message}` }],
        isError: true,
      });
    });
  });
}

// ── MCP protocol ───────────────────────────────────────────────────────

let initialized = false;
let requestId = null;
let buf = "";

process.stdin.on("data", (chunk) => {
  buf += chunk.toString();
  const lines = buf.split("\n");
  buf = lines.pop() || "";

  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      handleMessage(msg);
    } catch (e) {
      log(`parse error: ${e.message}`);
    }
  }
});

async function handleMessage(msg) {
  const { method, id, params } = msg;

  // notifications (no id)
  if (!id) {
    if (method === "notifications/initialized") {
      initialized = true;
      log("initialized");
    }
    return;
  }

  requestId = id;

  if (method === "initialize") {
    send({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2025-11-25",
        capabilities: { tools: {} },
        serverInfo: { name: "mc-builder", version: "1.0.0" },
      },
    });
    return;
  }

  if (!initialized && method !== "initialize") {
    send({ jsonrpc: "2.0", id, error: { code: -32000, message: "Not initialized" } });
    return;
  }

  if (method === "tools/list") {
    send({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
    return;
  }

  if (method === "tools/call") {
    const { name, arguments: args } = params;
    try {
      let result;
      if (name === "swift_build") {
        result = await runTool("swift", ["build", "--disable-sandbox"], args?.extraArgs);
      } else if (name === "swift_test") {
        result = await runTool("swift", ["test", "--disable-sandbox"], args?.extraArgs);
      } else {
        result = { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
      }
      send({ jsonrpc: "2.0", id, result });
    } catch (e) {
      send({ jsonrpc: "2.0", id, error: { code: -32603, message: e.message } });
    }
    return;
  }

  // ping
  if (method === "ping") {
    send({ jsonrpc: "2.0", id, result: {} });
    return;
  }

  log(`unhandled method: ${method}`);
}

log("server started");
