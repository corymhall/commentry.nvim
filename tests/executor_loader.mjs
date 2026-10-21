// Node runs the TypeScript tests directly. App imports use NodeNext .js paths,
// which Executor's bundler resolves to .ts during deployment.
import { registerHooks } from "node:module";

const app = new URL("../integrations/executor/", import.meta.url).href;
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (
      context.parentURL?.startsWith(app) &&
      specifier.startsWith("./") &&
      specifier.endsWith(".js")
    ) {
      return nextResolve(specifier.slice(0, -3) + ".ts", context);
    }
    return nextResolve(specifier, context);
  },
});
