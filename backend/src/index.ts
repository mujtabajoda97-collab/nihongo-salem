import { loadConfig } from './config.ts';
import type { Config } from './config.ts';
import { loadPrompts } from './prompts.ts';
import { buildApp } from './app.ts';

async function main(): Promise<void> {
  let cfg: Config;
  try {
    cfg = loadConfig();
  } catch (e) {
    console.error(e instanceof Error ? e.message : e);
    process.exit(1);
  }
  const prompts = loadPrompts(cfg.promptsDir);
  const app = await buildApp({ cfg, prompts });

  const stop = async () => {
    await app.close();
    process.exit(0);
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);

  await app.listen({ port: cfg.port, host: cfg.host });
  if (!cfg.appApiKey) {
    app.log.warn('APP_API_KEY is not set: anyone who knows the URL can spend your API credits');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
