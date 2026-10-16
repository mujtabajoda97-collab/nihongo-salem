import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export interface Prompts {
  /** ai_tutor_system_prompt.txt (inside the lessons) */
  tutor: string;
  /** free_talk_personas_prompt.txt (live call) */
  freeTalk: string;
}

export function loadPrompts(dir: string): Prompts {
  return {
    tutor: readFileSync(join(dir, 'ai_tutor_system_prompt.txt'), 'utf8'),
    freeTalk: readFileSync(join(dir, 'free_talk_personas_prompt.txt'), 'utf8'),
  };
}

const MAX_VALUE_CHARS = 6000;

/** Variable values come from the app: remove anything that could look like a placeholder. */
export function sanitizeValue(value: string): string {
  return value
    .replace(/\{\{|\}\}/g, '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .slice(0, MAX_VALUE_CHARS);
}

/** Replaces every {{NAME}} with its value. Unknown names are left as they are. */
export function fillTemplate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{\s*([A-Z0-9_]+)\s*\}\}/g, (whole, name: string) => {
    const v = vars[name];
    return v === undefined ? whole : sanitizeValue(v);
  });
}
