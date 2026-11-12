// Private local transport only. No credentials, backend writes, terminal
// keystrokes, or conversation state belong in this receiver.
import { createServer, type IncomingMessage } from "node:http";
import { createHash } from "node:crypto";
import { mkdir, lstat, chmod } from "node:fs/promises";
import { join, dirname } from "node:path";

export type Identity = {
  target: string;
  session: string;
  project: string;
  directory: string;
};
export function socketPath(
  target: string,
  root = process.env.COMMENTRY_PI_RUNTIME_DIR ??
    `/tmp/commentry-pi-${process.getuid!()}`,
) {
  return join(
    root,
    createHash("sha256").update(target).digest("hex").slice(0, 24) + ".sock",
  );
}

async function body(request: IncomingMessage) {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 2 * 1024 * 1024) throw new Error("notification exceeds 2 MiB");
    chunks.push(Buffer.from(chunk));
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

export async function startReceiver(
  identity: Identity,
  submit: (text: string, mode: "queue" | "steer") => void,
  root?: string,
) {
  const path = socketPath(identity.target, root);
  const folder = dirname(path);
  await mkdir(folder, { recursive: true, mode: 0o700 });
  const stat = await lstat(folder);
  if (
    !stat.isDirectory() ||
    stat.uid !== process.getuid!() ||
    (stat.mode & 0o077) !== 0
  ) {
    throw new Error(
      "Pi receiver directory must be private and owned by this user",
    );
  }
  let alive = true;
  const server = createServer(async (request, response) => {
    const reply = (status: number, value: unknown) => {
      response.writeHead(status, { "Content-Type": "application/json" });
      response.end(JSON.stringify(value));
    };
    try {
      if (!alive || request.headers.origin)
        throw new Error("receiver is unavailable");
      if (request.method === "GET" && request.url === "/status")
        return reply(200, identity);
      if (request.method !== "POST" || request.url !== "/deliver")
        return reply(404, { error: "unknown operation" });
      const input = await body(request);
      if (
        !alive ||
        !Object.entries(identity).every(([key, value]) => input[key] === value)
      ) {
        throw new Error(
          "Pi session, target, project or inbox directory changed",
        );
      }
      if (
        typeof input.text !== "string" ||
        !input.text.trim() ||
        !["queue", "steer"].includes(input.mode)
      ) {
        throw new Error("invalid notification");
      }
      // This is acceptance by Pi's API, not evidence of a model fetch or work.
      submit(input.text, input.mode);
      reply(200, { ...identity, mode: input.mode, submitted: true });
    } catch (error) {
      reply(409, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  });
  server.requestTimeout = 5000;
  server.headersTimeout = 5000;
  try {
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(path, () => {
        server.off("error", reject);
        resolve();
      });
    });
    await chmod(path, 0o600);
  } catch (error) {
    server.close();
    throw error;
  }
  return {
    path,
    async close() {
      if (!alive) return;
      alive = false;
      server.closeAllConnections();
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      );
    },
  };
}
