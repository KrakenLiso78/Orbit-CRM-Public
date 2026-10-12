#!/usr/bin/env node
/** Store a renewable owner session in the macOS Keychain, never in the repo. */
import { execFileSync } from "node:child_process";
import readline from "node:readline/promises";
import { readStoredPublishableKey } from "./orbit-auth-key.mjs";

const supabaseUrl = process.env.ORBIT_SUPABASE_URL;
const service = process.env.ORBIT_CALL_REPORT_KEYCHAIN_SERVICE ?? "Orbit CRM Public Local Session";
const account = process.env.USER ?? process.env.LOGNAME;
if (!supabaseUrl?.startsWith("https://")) throw new Error("ORBIT_SUPABASE_URL must be configured.");

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const storedPublishableKey = readStoredPublishableKey({ execFileSync, service, account });
const publishableKey = storedPublishableKey ?? (await rl.question("Supabase publishable key: ")).trim();
const email = (await rl.question("Orbit owner email: ")).trim();
rl.close();
rl.output.write("Orbit owner password: ");
let password = await new Promise((resolve, reject) => {
  let value = "";
  process.stdin.setRawMode?.(true);
  process.stdin.resume();
  const receive = (chunk) => {
    for (const character of chunk.toString()) {
      if (character === "\u0003") {
        cleanup();
        reject(new Error("Authentication cancelled."));
        return;
      }
      if (character === "\r" || character === "\n") {
        cleanup();
        resolve(value);
        return;
      }
      if (character === "\u007f") value = value.slice(0, -1);
      else value += character;
    }
  };
  const cleanup = () => {
    process.stdin.off("data", receive);
    process.stdin.setRawMode?.(false);
    process.stdin.pause();
  };
  process.stdin.on("data", receive);
});
rl.output.write("\n");

const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { apikey: publishableKey, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password }),
});
password = "";
if (!response.ok) throw new Error("Supabase did not authenticate this owner. The Keychain was not changed.");
const session = await response.json();
if (typeof session.refresh_token !== "string") throw new Error("Supabase did not return a renewable session. The Keychain was not changed.");
const secret = JSON.stringify({ publishable_key: publishableKey, refresh_token: session.refresh_token });
execFileSync("/usr/bin/security", ["add-generic-password", "-U", "-s", service, "-a", account, "-w", secret], { stdio: "ignore" });
console.log("Orbit Call Report MCP owner session saved in macOS Keychain.");
