#!/usr/bin/env node
/**
 * 依 routes.json 逐頁截圖，輸出到 vault/attachments/。
 *
 *   node shoot-web.mjs routes.json
 *   node shoot-web.mjs routes.json --only 03,04   # 只重拍指定的幾張
 *   node shoot-web.mjs routes.json --headed       # 看著它跑，除錯用
 *
 * 需要：npm i -D playwright && npx playwright install chromium
 *
 * 設計取捨：
 * - 登入只做一次，之後靠 storageState 重用。每頁重登會慢十倍，也更容易被
 *   後端的登入頻率限制擋下來。
 * - 帳密一律走環境變數（"env:APP_PASSWORD"）。routes.json 常常會進 repo，
 *   把密碼寫死在裡面遲早外流。
 * - 單頁失敗不中斷整輪。跑 20 頁時因為第 3 頁的選擇器改了就全部重來，
 *   在實際使用上很痛。最後統一列出失敗清單。
 */

import { chromium, devices } from 'playwright';
import { readFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const [, , configPath, ...flags] = process.argv;
if (!configPath) {
  console.error('用法：node shoot-web.mjs <routes.json> [--only 01,02] [--headed]');
  process.exit(1);
}

const only = (() => {
  const i = flags.indexOf('--only');
  return i === -1 ? null : new Set(flags[i + 1].split(','));
})();
const headed = flags.includes('--headed');

const cfg = JSON.parse(await readFile(configPath, 'utf8'));
const baseUrl = cfg.baseUrl?.replace(/\/$/, '');
if (!baseUrl) throw new Error('routes.json 缺 baseUrl');

const outDir = path.resolve(cfg.outDir ?? 'vault/attachments');
await mkdir(outDir, { recursive: true });

const desktop = cfg.viewport ?? { width: 1440, height: 900 };
const mobile = cfg.mobileViewport ?? { width: 390, height: 844 };
const statePath = cfg.auth?.storageStatePath ?? '.playwright-auth.json';

/** "env:FOO" → process.env.FOO；其餘原樣回傳 */
function resolveValue(v) {
  if (typeof v === 'string' && v.startsWith('env:')) {
    const key = v.slice(4);
    const got = process.env[key];
    if (!got) throw new Error(`環境變數 ${key} 沒設定（routes.json 要求 ${v}）`);
    return got;
  }
  return v;
}

/** 一個 step 可以是 fill / click / press / waitFor / wait */
async function runSteps(page, steps = []) {
  for (const step of steps) {
    if (step.fill) await page.fill(step.fill, resolveValue(step.value));
    else if (step.click) await page.click(step.click);
    else if (step.press) await page.press(step.press, step.key);
    else if (step.waitFor) await page.waitForSelector(step.waitFor, { timeout: step.timeout ?? 15000 });
    else if (step.wait) await page.waitForTimeout(step.wait);
    else throw new Error(`不認得的 step：${JSON.stringify(step)}`);
  }
}

const browser = await chromium.launch({ headless: !headed });

// ── 登入（只做一次） ──────────────────────────────────
if (cfg.auth && !existsSync(statePath)) {
  console.log('▶ 登入中…');
  const ctx = await browser.newContext({ viewport: desktop });
  const page = await ctx.newPage();
  await page.goto(baseUrl + (cfg.auth.loginPath ?? '/login'), { waitUntil: 'networkidle' });
  await runSteps(page, cfg.auth.steps);
  await ctx.storageState({ path: statePath });
  await ctx.close();
  console.log(`  已存 ${statePath}（過期的話刪掉它重跑）`);
}

const contextOpts = { viewport: desktop };
if (cfg.auth && existsSync(statePath)) contextOpts.storageState = statePath;
const ctx = await browser.newContext(contextOpts);

const mobileCtx = cfg.shots.some((s) => s.mobile)
  ? await browser.newContext({ ...devices['iPhone 13'], viewport: mobile, ...(contextOpts.storageState ? { storageState: contextOpts.storageState } : {}) })
  : null;

const failed = [];

for (const shot of cfg.shots) {
  const id = shot.name.split('-')[0];
  if (only && !only.has(id) && !only.has(shot.name)) continue;

  for (const variant of shot.mobile === 'only' ? ['mobile'] : shot.mobile ? ['desktop', 'mobile'] : ['desktop']) {
    const context = variant === 'mobile' ? mobileCtx : ctx;
    const suffix = variant === 'mobile' ? '-mobile' : '';
    const file = path.join(outDir, `${shot.name}${suffix}.png`);
    const page = await context.newPage();
    try {
      await page.goto(baseUrl + shot.path, { waitUntil: shot.waitUntil ?? 'networkidle' });
      if (shot.waitFor) await page.waitForSelector(shot.waitFor, { timeout: shot.timeout ?? 15000 });
      if (shot.actions) await runSteps(page, shot.actions);
      if (shot.hide) {
        // 遮掉會讓截圖每次都不一樣的東西（時鐘、隨機頭像），否則 git diff 永遠有變動
        await page.addStyleTag({ content: shot.hide.map((s) => `${s}{visibility:hidden!important}`).join('') });
      }
      await page.screenshot({ path: file, fullPage: shot.fullPage ?? false });
      console.log(`  ✅ ${path.basename(file)}`);
    } catch (e) {
      console.log(`  ❌ ${path.basename(file)}：${e.message.split('\n')[0]}`);
      failed.push({ file: path.basename(file), reason: e.message.split('\n')[0] });
    } finally {
      await page.close();
    }
  }
}

await ctx.close();
if (mobileCtx) await mobileCtx.close();
await browser.close();

console.log(`\n輸出：${outDir}`);
if (failed.length) {
  console.log(`\n${failed.length} 張失敗：`);
  failed.forEach((f) => console.log(`  ${f.file} — ${f.reason}`));
  console.log('\n多半是選擇器改了、需要先建資料、或登入狀態過期（刪掉 ' + statePath + ' 重跑）。');
  process.exit(1);
}
