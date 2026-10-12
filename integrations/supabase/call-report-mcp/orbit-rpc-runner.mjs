#!/usr/bin/env node
/**
 * Invoke one reviewed Orbit MCP operation from a local JSON payload file.
 * The MCP process obtains the owner refresh token from macOS Keychain; this
 * runner never accepts or prints credentials.
 */
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const [, , toolName, payloadPath] = process.argv;
if (!toolName || !payloadPath) {
  throw new Error("Usage: orbit-rpc-runner.mjs <reviewed-tool-name> <payload.json>");
}
const payload = JSON.parse(await readFile(resolve(payloadPath), "utf8"));
const scriptDir = dirname(fileURLToPath(import.meta.url));
const child = spawn(process.execPath, [resolve(scriptDir, "orbit-call-report-mcp.mjs")], {
  env: process.env,
  stdio: ["pipe", "pipe", "inherit"],
});
let output = "";
child.stdout.setEncoding("utf8");
child.stdout.on("data", (chunk) => { output += chunk; });
child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-03-26" } })}\n`);
child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: toolName, arguments: payload } })}\n`);
child.stdin.end();
const exitCode = await new Promise((resolveExit) => child.on("close", resolveExit));
if (exitCode !== 0) throw new Error(`Orbit MCP exited with code ${exitCode}`);
const responses = output.trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
const response = responses.find((candidate) => candidate.id === 2);
if (!response) throw new Error("Orbit MCP returned no tool response");
if (response.error) throw new Error(response.error.message ?? "Orbit MCP operation failed");
process.stdout.write(`${JSON.stringify(response.result)}\n`);
