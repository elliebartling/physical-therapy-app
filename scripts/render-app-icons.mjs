// Renders every app icon set into App/PTApp/Assets.xcassets.
//
// Two designs (Range of motion, The week) in each of the six accents, each with
// light, dark and tinted appearances. "AppIcon" (the primary icon) is Range of
// motion in Signal; the rest are alternate icons named Icon-<style>-<accent>.
// Keep the names in step with AppIconChoice.swift and App/project.yml.
//
// Usage: node scripts/render-app-icons.mjs   (needs Playwright's Chromium)

import { createRequire } from 'node:module';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright is installed globally, which ES module imports don't search.
const { chromium } = createRequire(import.meta.url)('playwright');

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const catalog = path.join(root, 'App/PTApp/Assets.xcassets');

const accents = {
  signal: '#FF5A1F', sky: '#3FA9F5', sun: '#FFC531',
  mint: '#2BD99F', blossom: '#FF7EB6', lilac: '#A98BFF',
};
const styles = ['rangeOfMotion', 'week'];

function palette(appearance, accent) {
  switch (appearance) {
    case 'light': return { bg: '#F3F2EE', ink: '#111111', acc: accent };
    case 'dark': return { bg: '#121211', ink: '#F3F2EE', acc: accent };
    // iOS tints a grayscale icon; luminance carries the design.
    case 'tinted': return { bg: '#000000', ink: '#FFFFFF', acc: '#8C8C8C' };
  }
}

function art(style, p) {
  if (style === 'rangeOfMotion') {
    // A goniometer: two arms hinged at a pivot, the swept angle filled.
    return `
      <path d="M 30 72 L 30 42 A 30 30 0 0 1 51.2 50.8 Z" fill="${p.acc}"/>
      <line x1="30" y1="72" x2="84" y2="72" stroke="${p.ink}" stroke-width="6" stroke-linecap="round"/>
      <line x1="30" y1="72" x2="66" y2="36" stroke="${p.ink}" stroke-width="6" stroke-linecap="round"/>
      <circle cx="30" cy="72" r="7" fill="${p.bg}" stroke="${p.ink}" stroke-width="4"/>`;
  }
  // The week strip: four days done, today in the accent, two to go.
  let bars = '';
  for (let i = 0; i < 7; i++) {
    const x = 14 + i * 10.6;
    if (i < 4) bars += `<rect x="${x}" y="30" width="7.4" height="40" fill="${p.ink}"/>`;
    else if (i === 4) bars += `<rect x="${x}" y="30" width="7.4" height="40" fill="${p.acc}"/>`;
    else bars += `<rect x="${x + 0.75}" y="30.75" width="5.9" height="38.5" fill="none" stroke="${p.ink}" stroke-width="1.5" stroke-opacity="0.45"/>`;
  }
  return bars;
}

const svg = (style, appearance, accent) => {
  const p = palette(appearance, accent);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 100 100">
    <rect width="100" height="100" fill="${p.bg}"/>${art(style, p)}</svg>`;
};

const contents = {
  images: [
    { filename: 'light.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'dark' }], filename: 'dark.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: 'tinted.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
  ],
  info: { author: 'xcode', version: 1 },
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
const names = [];
for (const style of styles) {
  for (const [accentName, accent] of Object.entries(accents)) {
    const set = style === 'rangeOfMotion' && accentName === 'signal' ? 'AppIcon' : `Icon-${style}-${accentName}`;
    const dir = path.join(catalog, `${set}.appiconset`);
    await rm(dir, { recursive: true, force: true });
    await mkdir(dir, { recursive: true });
    for (const appearance of ['light', 'dark', 'tinted']) {
      await page.setContent(`<html><body style="margin:0">${svg(style, appearance, accent)}</body></html>`);
      // Opaque, square PNG: iOS applies the mask and rejects transparency.
      await page.screenshot({ path: path.join(dir, `${appearance}.png`), omitBackground: false,
                              clip: { x: 0, y: 0, width: 1024, height: 1024 } });
    }
    await writeFile(path.join(dir, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n');
    names.push(set);
  }
}
await browser.close();
console.log(names.join('\n'));
