#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import { spawn } from "node:child_process";
import { connect as connectSocket } from "node:net";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const here = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(here, "../..");
const bundleID = process.env.VORSSAINT_BUNDLE_ID || "com.vorssaint.utils.dev";
const bridgeDirectory = process.env.VORSSAINT_BRIDGE_DIRECTORY ||
  join(homedir(), "Library", "Application Support", bundleID, "AgentBridge");
const endpointPath = join(bridgeDirectory, "endpoint.json");
const appPath = process.env.VORSSAINT_APP_PATH ||
  join(repositoryRoot, "build", "stage.noindex", "Vorssaint (Developer).app");

function readEndpoint() {
  try {
    const endpoint = JSON.parse(readFileSync(endpointPath, "utf8"));
    if (endpoint.bundleId !== bundleID || !Number.isInteger(endpoint.port) ||
        endpoint.port < 1 || endpoint.port > 65535 ||
        typeof endpoint.token !== "string" || !/^[0-9a-f]{64}$/.test(endpoint.token)) {
      return null;
    }
    return endpoint;
  } catch {
    return null;
  }
}

function endpointIdentity(endpoint) {
  return endpoint ? `${endpoint.pid}:${endpoint.port}:${endpoint.token}` : "";
}

function launchDeveloperApp() {
  if (!existsSync(appPath)) {
    throw new Error(`Vorssaint Developer app was not found at ${appPath}. Build it with ./build.sh --dev.`);
  }
  const child = spawn("/usr/bin/open", ["-a", appPath], {
    detached: true,
    stdio: "ignore",
  });
  child.once("error", error => console.error(`Could not open Vorssaint Developer: ${error.message}`));
  child.unref();
}

function sendBridgeRequest(endpoint, method, params) {
  return new Promise((resolvePromise, rejectPromise) => {
    const socket = connectSocket({ host: "127.0.0.1", port: endpoint.port });
    let received = "";
    let finished = false;
    const finish = (error, value) => {
      if (finished) return;
      finished = true;
      socket.destroy();
      error ? rejectPromise(error) : resolvePromise(value);
    };

    socket.setTimeout(3000, () => finish(new Error("Timed out waiting for Vorssaint.")));
    socket.once("connect", () => {
      socket.write(`${JSON.stringify({ token: endpoint.token, method, params })}\n`);
    });
    socket.on("data", chunk => {
      received += chunk.toString("utf8");
      if (received.length > 1024 * 1024) {
        finish(new Error("Vorssaint returned an oversized response."));
        return;
      }
      const newline = received.indexOf("\n");
      if (newline < 0) return;
      try {
        const response = JSON.parse(received.slice(0, newline));
        if (!response.ok) finish(new Error(response.error || "Vorssaint rejected the request."));
        else finish(null, response.result);
      } catch (error) {
        finish(new Error(`Could not read the Vorssaint response: ${error.message}`));
      }
    });
    socket.once("error", error => finish(error));
    socket.once("end", () => {
      if (!finished) finish(new Error("Vorssaint closed the connection without a response."));
    });
  });
}

const delay = milliseconds => new Promise(resolvePromise => setTimeout(resolvePromise, milliseconds));

async function bridgeCall(method, params = {}) {
  let endpoint = readEndpoint();
  const previousIdentity = endpointIdentity(endpoint);
  let launchRequested = !endpoint;
  if (launchRequested) launchDeveloperApp();

  const deadline = Date.now() + 15000;
  let lastError;
  while (Date.now() < deadline) {
    endpoint = readEndpoint();
    if (endpoint) {
      try {
        return await sendBridgeRequest(endpoint, method, params);
      } catch (error) {
        lastError = error;
        if (endpointIdentity(endpoint) === previousIdentity && previousIdentity && !launchRequested) {
          // A stale endpoint can survive an unclean exit; ask Launch Services
          // to start the app, then wait for its new per-launch token.
          launchDeveloperApp();
          launchRequested = true;
        }
      }
    }
    await delay(250);
  }
  throw new Error(lastError
    ? `Could not reach Vorssaint Developer: ${lastError.message}`
    : "Vorssaint Developer did not publish its local control endpoint within 15 seconds.");
}

function toolResult(value) {
  return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
}

function toolError(error) {
  return { content: [{ type: "text", text: error.message }], isError: true };
}

const server = new McpServer({ name: "vorssaint", version: "0.1.0" });

server.registerTool("vorssaint_status", {
  description: "Read the running Vorssaint Developer version, installed feature count, Keep Awake state, and appearance.",
  inputSchema: z.object({}),
}, async () => {
  try { return toolResult(await bridgeCall("status")); }
  catch (error) { return toolError(error); }
});

server.registerTool("vorssaint_list_features", {
  description: "List Vorssaint features with their installed state, enabled state, group, and permission requirements.",
  inputSchema: z.object({}),
}, async () => {
  try { return toolResult(await bridgeCall("list_features")); }
  catch (error) { return toolError(error); }
});

server.registerTool("vorssaint_set_feature_available", {
  description: "Install or uninstall one Vorssaint feature in the running app. macOS permissions remain under the user's control.",
  inputSchema: z.object({
    feature: z.string().min(1).describe("Stable feature id returned by vorssaint_list_features."),
    available: z.boolean().describe("True to install the feature, false to uninstall it."),
  }),
}, async ({ feature, available }) => {
  try { return toolResult(await bridgeCall("set_feature_available", { feature, available })); }
  catch (error) { return toolError(error); }
});

server.registerTool("vorssaint_set_keep_awake", {
  description: "Set Keep Awake on or off. Omit duration_minutes to use the saved duration; 0 means indefinite, and positive values are minutes up to 1440.",
  inputSchema: z.object({
    active: z.boolean(),
    duration_minutes: z.number().int().min(0).max(1440).optional(),
  }),
}, async ({ active, duration_minutes }) => {
  try {
    return toolResult(await bridgeCall("set_keep_awake", {
      active,
      ...(duration_minutes === undefined ? {} : { durationMinutes: duration_minutes }),
    }));
  } catch (error) { return toolError(error); }
});

server.registerTool("vorssaint_set_appearance", {
  description: "Set macOS appearance to light or dark through Vorssaint's Quick Toggles service.",
  inputSchema: z.object({ appearance: z.enum(["light", "dark"]) }),
}, async ({ appearance }) => {
  try { return toolResult(await bridgeCall("set_appearance", { appearance })); }
  catch (error) { return toolError(error); }
});

const transport = new StdioServerTransport();
await server.connect(transport);
