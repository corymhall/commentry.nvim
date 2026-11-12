// Optional offline smoke using an installed Pi host, real native IPC and the
// CLI's isolated legacy inbox. A controlled input handler answers without a
// model/provider call. No user's inbox, auth or session files are touched.
import { spawn, execFileSync } from "node:child_process";
import { mkdtemp, writeFile, chmod, rm, realpath } from "node:fs/promises";
import { join, resolve } from "node:path";
import { socketPath } from "../integrations/pi/receiver.ts";
import { request } from "node:http";
import assert from "node:assert/strict";

const root = await realpath(await mkdtemp("/tmp/commentry-pi-smoke-"));
const binary = resolve("bin/commentry");
const directory = join(root, "data");
const env = {
  ...process.env,
  PI_CODING_AGENT_DIR: join(root, "pi"),
  PI_OFFLINE: "1",
  COMMENTRY_PI_RUNTIME_DIR: join(root, "sockets"),
  COMMENTRY_INBOX_DIR: directory,
  REX_SESSION: "smoke-session",
  REX_BLOCK: "smoke-pane",
};
const contextCLI = join(root, "context-cli");
await writeFile(
  contextCLI,
  `#!/usr/bin/env node\nif(process.argv.includes('context'))console.log(JSON.stringify({ok:true,result:{configured:true,project:${JSON.stringify(root)},directory:${JSON.stringify(directory)}}}));else process.exit(1);\n`,
);
await chmod(contextCLI, 0o700);
await writeFile(
  join(root, "rex"),
  `#!/usr/bin/env node\nconst a={id:process.env.SMOKE_TARGET,session:'smoke-session',block:'smoke-pane',harness:'pi',cwd:${JSON.stringify(root)},state:'idle',name:'Smoke Pi'};const action=process.argv[4];console.log(JSON.stringify(action==='agent_list'?{agents:[a]}:a));\n`,
);
await chmod(join(root, "rex"), 0o700);
const helper = join(root, "answer.ts");
await writeFile(
  helper,
  `import {execFileSync} from 'node:child_process';
export default function(pi){pi.on('input',(event,ctx)=>{
 if(event.source!=='extension'||!event.text.startsWith('COMMENTRY_THREAD_V1'))return;
 const config=JSON.parse(event.text.slice(event.text.lastIndexOf('\\n{')+1));
 const reply={...config.reply_request,body:'Native Pi smoke answer'};
 const saved=JSON.parse(execFileSync(${JSON.stringify(binary)},['--directory',${JSON.stringify(directory)},'rpc'],{input:JSON.stringify(reply),encoding:'utf8'}));
 if(!saved.ok)throw Error(saved.error);
 ctx.ui.notify('commentry-smoke-finished','info');return {action:'handled'};
});}
`,
);
let child;
try {
  child = spawn(
    "pi",
    [
      "--offline",
      "--mode",
      "rpc",
      "--no-session",
      "--no-extensions",
      "--no-mcp",
      "--no-skills",
      "--no-context-files",
      "--no-prompt-templates",
      "-e",
      resolve("integrations/pi/index.ts"),
      "-e",
      helper,
    ],
    {
      cwd: root,
      env: { ...env, COMMENTRY_EXECUTABLE: contextCLI },
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  let output = "",
    stderr = "";
  const records = [];
  const waiters = [];
  child.stdout.on("data", (chunk) => {
    output += chunk;
    let end;
    while ((end = output.indexOf("\n")) >= 0) {
      const line = output.slice(0, end);
      output = output.slice(end + 1);
      if (!line.trim()) continue;
      const record = JSON.parse(line);
      records.push(record);
      for (const wake of [...waiters]) wake();
    }
  });
  child.stderr.on("data", (chunk) => (stderr += chunk));
  function waitFor(predicate) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        cleanup();
        reject(
          Error("Pi smoke timed out: " + stderr + JSON.stringify(records)),
        );
      }, 15000);
      const check = () => {
        const found = records.find(predicate);
        if (found) {
          cleanup();
          resolve(found);
        }
      };
      const cleanup = () => {
        clearTimeout(timer);
        const i = waiters.indexOf(check);
        if (i >= 0) waiters.splice(i, 1);
      };
      waiters.push(check);
      check();
    });
  }
  const rpc = async (type) => {
    const id = type + Math.random();
    child.stdin.write(JSON.stringify({ id, type }) + "\n");
    const reply = await waitFor((r) => r.type === "response" && r.id === id);
    assert.equal(reply.success, true, JSON.stringify(reply));
    return reply.data;
  };
  const commands = await rpc("get_commands");
  assert.ok(
    JSON.stringify(commands).includes("commentry"),
    "extension command was not registered",
  );
  const target = `smoke-session/smoke-pane/${child.pid}`;
  const path = socketPath(target, env.COMMENTRY_PI_RUNTIME_DIR);
  const status = () =>
    new Promise((resolve, reject) => {
      const req = request({ socketPath: path, path: "/status" }, (res) => {
        let text = "";
        res.on("data", (c) => (text += c));
        res.on("end", () => resolve(JSON.parse(text)));
      });
      req.on("error", reject);
      req.end();
    });
  const before = await status();
  const cli = (args, input) =>
    JSON.parse(
      execFileSync(binary, ["--directory", directory, ...args], {
        cwd: root,
        env: {
          ...env,
          PATH: root + ":" + process.env.PATH,
          SMOKE_TARGET: target,
        },
        encoding: "utf8",
        input: input === undefined ? undefined : JSON.stringify(input),
      }),
    );
  const created = cli([
    "create",
    "--project",
    root,
    "--body",
    "Native transport smoke question",
  ]);
  assert.equal(created.ok, true);
  cli(["queue", created.result, "--defer-delivery"]);
  const attached = cli(["agent", "--project", root, "attach", target]);
  assert.equal(attached.ok, true, JSON.stringify(attached));
  assert.equal(
    attached.result.delivery_error,
    undefined,
    JSON.stringify(attached),
  );
  assert.equal(attached.result.sent, 1, JSON.stringify(attached));
  await waitFor(
    (r) =>
      r.type === "extension_ui_request" &&
      r.message === "commentry-smoke-finished",
  );
  const thread = cli(["read", created.result]).result;
  assert.equal(thread.messages.at(-1).body, "Native Pi smoke answer");
  assert.equal(thread.queue[0].status, "complete");
  assert.equal(thread.resolved, false);
  await rpc("new_session");
  const after = await status();
  assert.notEqual(
    before.session,
    after.session,
    "session switch retained the old native identity",
  );
  child.stdin.end();
  const exit = await new Promise((resolve) => child.once("exit", resolve));
  assert.equal(exit, 0, stderr);
  console.log(
    "PASS: installed Pi loaded extension, native delivery returned an atomic inbox answer, session switch replaced identity, shutdown completed.",
  );
} finally {
  if (child?.exitCode === null) {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
  }
  await rm(root, { recursive: true, force: true });
}
