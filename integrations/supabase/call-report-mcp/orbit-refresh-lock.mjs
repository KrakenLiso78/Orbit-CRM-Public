import { createHash } from "node:crypto";
import { mkdir, rmdir, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

export function defaultRefreshLockPath({ service, account }) {
  const identity = createHash("sha256").update(`${service}\u0000${account}`).digest("hex").slice(0, 20);
  return join(tmpdir(), `orbit-owner-refresh-${identity}.lock`);
}

export function createFileLock({
  lockPath,
  timeoutMs = 30_000,
  staleMs = 300_000,
  pollMs = 50,
  now = () => Date.now(),
  wait = delay,
}) {
  if (!lockPath) throw new Error("A refresh lock path is required.");

  return async function withFileLock(operation) {
    const deadline = now() + timeoutMs;
    while (true) {
      try {
        await mkdir(lockPath, { mode: 0o700 });
        break;
      } catch (error) {
        if (error?.code !== "EEXIST") throw error;
        try {
          const lockStat = await stat(lockPath);
          if (now() - lockStat.mtimeMs > staleMs) {
            await rmdir(lockPath);
            continue;
          }
        } catch (inspectionError) {
          if (inspectionError?.code === "ENOENT") continue;
          throw inspectionError;
        }
        if (now() >= deadline) {
          throw new Error("Timed out waiting for the owner-session refresh lock.");
        }
        await wait(pollMs);
      }
    }

    try {
      return await operation();
    } finally {
      try {
        await rmdir(lockPath);
      } catch (error) {
        if (error?.code !== "ENOENT") throw error;
      }
    }
  };
}
