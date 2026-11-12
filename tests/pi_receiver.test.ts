import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { request } from "node:http";
import { startReceiver, socketPath } from "../integrations/pi/receiver.ts";

function call(path: string, method: string, url: string, body?: unknown) {
  return new Promise<{ status: number; body: any }>((resolve, reject) => {
    const req = request({ socketPath: path, method, path: url }, (res) => {
      let text = "";
      res.on("data", (chunk) => (text += chunk));
      res.on("end", () =>
        resolve({ status: res.statusCode!, body: JSON.parse(text) }),
      );
    });
    req.on("error", reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}

test("native receiver validates session identity, uses queue/steer and releases its socket", async () => {
  const root = await mkdtemp("/tmp/commentry-pi-test-");
  const identity = {
    target: "rex/pane/123",
    session: "session-one",
    project: "/project",
    directory: "/data",
  };
  const delivered: unknown[] = [];
  const receiver = await startReceiver(
    identity,
    (text, mode) => {
      delivered.push({ text, mode });
    },
    root,
  );
  try {
    assert.equal((await stat(root)).mode & 0o077, 0);
    assert.equal(
      (await call(receiver.path, "GET", "/status")).body.session,
      "session-one",
    );
    const input = {
      ...identity,
      mode: "queue",
      text: "COMMENTRY_BATCH_V1\nA user followup",
    };
    assert.equal(
      (
        await call(receiver.path, "POST", "/deliver", {
          ...input,
          session: "stale",
        })
      ).status,
      409,
    );
    assert.equal(delivered.length, 0);
    assert.equal(
      (await call(receiver.path, "POST", "/deliver", input)).body.submitted,
      true,
    );
    assert.equal(
      (
        await call(receiver.path, "POST", "/deliver", {
          ...input,
          mode: "steer",
        })
      ).body.submitted,
      true,
    );
    assert.deepEqual(delivered, [
      { text: input.text, mode: "queue" },
      { text: input.text, mode: "steer" },
    ]);
    assert.equal(
      (await call(receiver.path, "POST", "/execute", input)).status,
      404,
    );
  } finally {
    await receiver.close();
  }
  await assert.rejects(
    call(socketPath(identity.target, root), "GET", "/status"),
  );
  // Reload/new-session can reuse the same foreground process, never its old session identity.
  const next = await startReceiver(
    { ...identity, session: "session-two" },
    () => {},
    root,
  );
  try {
    assert.equal(
      (await call(next.path, "GET", "/status")).body.session,
      "session-two",
    );
  } finally {
    await next.close();
    await rm(root, { recursive: true, force: true });
  }
});

test("native receiver reports API rejection without claiming submission", async () => {
  const root = await mkdtemp("/tmp/commentry-pi-test-");
  const identity = {
    target: "rex/pane/456",
    session: "session",
    project: "/project",
    directory: "/data",
  };
  const receiver = await startReceiver(
    identity,
    () => {
      throw new Error("Pi is shutting down");
    },
    root,
  );
  try {
    const result = await call(receiver.path, "POST", "/deliver", {
      ...identity,
      text: "request",
      mode: "queue",
    });
    assert.equal(result.status, 409);
    assert.equal(result.body.submitted, undefined);
    assert.match(result.body.error, /shutting down/);
  } finally {
    await receiver.close();
    await rm(root, { recursive: true, force: true });
  }
});
