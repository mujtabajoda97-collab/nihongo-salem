#!/usr/bin/env node
/**
 * Draws the app artwork as flat vector illustrations and writes it as .webp:
 *   assets/images/scenes/epNN_bg.webp          40 story backgrounds
 *   assets/images/characters/<name>.webp       33 story characters + 4 call personas
 *
 * No AI service needed. Needs only:  npm i sharp   then   node tool/make_art.mjs
 * Replace any file with real artwork later: the app only looks at the file names.
 */
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let sharp;
try {
  sharp = require('sharp');
} catch {
  sharp = require(process.env.SHARP_PATH ?? '/home/claude/.npm-global/lib/node_modules/sharp');
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outScenes = join(root, 'assets/images/scenes');
const outChars = join(root, 'assets/images/characters');
mkdirSync(outScenes, { recursive: true });
mkdirSync(outChars, { recursive: true });

// ------------------------------------------------------------------ helpers
const W = 1080;
const H = 1620;
const r = (x, y, w, h, fill, rx = 0, extra = '') =>
  typeof rx === 'string'
    ? `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}" ${rx}/>`
    : `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${fill}" ${extra}/>`;
const c = (x, y, rad, fill, extra = '') => `<circle cx="${x}" cy="${y}" r="${rad}" fill="${fill}" ${extra}/>`;
const e = (x, y, rx, ry, fill, extra = '') => `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="${fill}" ${extra}/>`;
const p = (d, fill, extra = '') => `<path d="${d}" fill="${fill}" ${extra}/>`;
const poly = (pts, fill, extra = '') => `<polygon points="${pts}" fill="${fill}" ${extra}/>`;
const line = (x1, y1, x2, y2, stroke, w = 6, extra = '') =>
  `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${stroke}" stroke-width="${w}" stroke-linecap="round" ${extra}/>`;

let gid = 0;
const grad = (stops, vertical = true) => {
  const id = `g${gid++}`;
  const s = stops.map(([o, col]) => `<stop offset="${o}" stop-color="${col}"/>`).join('');
  return {
    id,
    def: `<linearGradient id="${id}" x1="0" y1="0" x2="${vertical ? 0 : 1}" y2="${vertical ? 1 : 0}">${s}</linearGradient>`,
    ref: `url(#${id})`,
  };
};

const svg = (w, h, defs, body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><defs>${defs}</defs>${body}</svg>`;

function windows(x, y, cols, rows, cw, ch, gap, on, off, seed = 1) {
  let out = '';
  let s = seed;
  for (let i = 0; i < cols; i++) {
    for (let j = 0; j < rows; j++) {
      s = (s * 9301 + 49297) % 233280;
      out += r(x + i * (cw + gap), y + j * (ch + gap), cw, ch, s / 233280 > 0.45 ? on : off, 4);
    }
  }
  return out;
}

const cloud = (x, y, k = 1, col = '#ffffff', op = 0.9) =>
  `<g opacity="${op}">${e(x, y, 90 * k, 34 * k, col)}${e(x - 60 * k, y + 10 * k, 60 * k, 26 * k, col)}${e(x + 70 * k, y + 12 * k, 66 * k, 28 * k, col)}</g>`;

const sakura = (x, y, k = 1) =>
  `<g>${line(x, y + 220 * k, x, y + 40 * k, '#6b4a3a', 18 * k)}${c(x, y, 120 * k, '#ffc2d4')}${c(x - 80 * k, y + 40 * k, 80 * k, '#ffb0c8')}${c(x + 80 * k, y + 36 * k, 84 * k, '#ffd1df')}</g>`;

const tree = (x, y, k = 1, col = '#4caf7a') =>
  `<g>${r(x - 12 * k, y, 24 * k, 110 * k, '#7a5a42')}${c(x, y - 20 * k, 76 * k, col)}${c(x - 46 * k, y + 14 * k, 52 * k, col)}${c(x + 46 * k, y + 16 * k, 54 * k, col)}</g>`;

const lantern = (x, y, k = 1, col = '#e8412f') =>
  `<g>${line(x, y - 60 * k, x, y, '#333', 6)}${e(x, y + 50 * k, 44 * k, 56 * k, col)}${r(x - 22 * k, y - 6 * k, 44 * k, 12 * k, '#222', 3)}${r(x - 22 * k, y + 100 * k, 44 * k, 12 * k, '#222', 3)}${line(x - 24 * k, y + 50 * k, x + 24 * k, y + 50 * k, '#ffd9a0', 4)}</g>`;

const awning = (x, y, w, h, a, b, n = 8) => {
  let out = '';
  const sw = w / n;
  for (let i = 0; i < n; i++) out += r(x + i * sw, y, sw + 1, h, i % 2 ? a : b);
  out += p(`M${x} ${y + h} ${Array.from({ length: n }, (_, i) => `Q${x + sw * (i + 0.5)} ${y + h + 26} ${x + sw * (i + 1)} ${y + h}`).join(' ')} Z`, '#00000022');
  return out;
};

function ground(y, col, stripe) {
  let out = r(0, y, W, H - y, col);
  if (stripe) for (let i = 0; i < 8; i++) out += r(60 + i * 140, y + 70, 70, 14, stripe, 7);
  return out;
}

const yen = (x, y, k = 1, col = '#f6c445') =>
  `<g>${c(x, y, 60 * k, col)}${c(x, y, 46 * k, 'none', 'stroke="#ffffff88" stroke-width="5"')}<path d="M${x - 24 * k} ${y - 30 * k} L${x} ${y + 4 * k} L${x + 24 * k} ${y - 30 * k} M${x} ${y + 4 * k} V${y + 34 * k} M${x - 20 * k} ${y + 6 * k} H${x + 20 * k} M${x - 20 * k} ${y + 20 * k} H${x + 20 * k}" stroke="#8a5a00" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>`;

// ------------------------------------------------------------------- scenes
/** Each builder returns { defs, body }. `pal` varies the colours between episodes that share a place. */
const S = {};

S.airport = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(820, 380, 110, '#fff3c4', 'opacity="0.9"') + cloud(240, 300, 1.4) + cloud(780, 560, 1) +
      // plane
      `<g transform="translate(560 460) rotate(-12)">${e(0, 0, 230, 40, '#ffffff')}${poly('-40,-6 120,-150 170,-150 60,-6', '#e9eef5')}${poly('-40,6 120,150 170,150 60,6', '#dfe6ef')}${poly('-210,-4 -250,-70 -200,-70 -150,-4', '#d62828')}${r(60, -14, 120, 14, '#5b8def', 6)}</g>` +
      // terminal
      r(0, 980, W, 360, '#cfd8e3') + poly('0,980 1080,860 1080,980', '#e6edf5') + windows(40, 1010, 9, 3, 90, 80, 22, '#9fd3ff', '#7fb6e6') +
      ground(1340, '#6c7a89', '#ffffffaa'),
  };
};

S.station = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let gates = '';
  for (let i = 0; i < 4; i++) {
    const x = 90 + i * 250;
    gates += r(x, 980, 90, 300, '#9aa7b5', 14) + r(x + 14, 1010, 62, 40, '#22c55e', 8) + r(x + 20, 1070, 50, 26, '#334155', 6);
  }
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(0, 0, W, 820, '#e7edf3') + r(0, 760, W, 70, '#2f6bd8') +
      // hanging signs
      r(140, 180, 800, 150, '#ffffff', 22) + r(170, 210, 330, 90, '#2f6bd8', 14) + c(640, 255, 30, '#22c55e') + c(740, 255, 30, '#f59e0b') + c(840, 255, 30, '#ef4444') +
      windows(60, 420, 6, 2, 150, 110, 30, '#cfe3ff', '#bcd6f7') +
      gates + ground(1280, '#8996a5') + yen(930, 700, 0.8, '#7fc9ff'),
  };
};

S.train = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let wins = '';
  for (let i = 0; i < 4; i++) wins += r(110 + i * 220, 760, 170, 170, '#dff3ff', 26);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(220, 260, 90, '#fff3c4', 'opacity="0.85"') + cloud(780, 300, 1.2) +
      // city far
      windows(0, 900, 12, 1, 70, 200, 20, pal.c, pal.c) +
      r(0, 1180, W, 440, '#5a6573') + r(0, 1190, W, 12, '#cfd6de') + r(0, 1420, W, 12, '#cfd6de') +
      // train
      r(-40, 700, W + 80, 380, '#f5f7fa', 40) + r(-40, 940, W + 80, 60, pal.d, 0) + r(-40, 1000, W + 80, 70, '#aab4c0') + wins +
      c(160, 1090, 44, '#2b2f36') + c(420, 1090, 44, '#2b2f36') + c(700, 1090, 44, '#2b2f36') + c(940, 1090, 44, '#2b2f36') +
      line(0, 520, W, 520, '#333', 4) + line(0, 560, W, 560, '#333', 4),
  };
};

S.home = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let balconies = '';
  for (let j = 0; j < 4; j++) balconies += r(250, 400 + j * 200, 580, 14, '#9aa7b5') + windows(290, 330 + j * 200, 3, 1, 140, 100, 40, '#ffe9a8', '#6d8198', j + 3);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(900, 200, 80, '#fff3c4', 'opacity="0.9"') + cloud(180, 220, 1.1) +
      r(220, 300, 640, 960, pal.c, 20) + balconies + r(440, 1060, 200, 200, '#7a4b2a', 14) + c(610, 1170, 10, '#f6c445') +
      tree(120, 1090, 1.2) + tree(980, 1100, 1.1, '#3d9e6a') + ground(1260, '#8fcf9e') + r(0, 1260, W, 40, '#6fb184'),
  };
};

S.konbini = (pal) => {
  const sky = grad([[0, '#1a2145'], [1, '#3b3f7a']]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(160, 180, 60, '#fff3c4') + [[300, 120], [520, 200], [760, 90], [900, 260], [80, 420]].map(([x, y]) => c(x, y, 5, '#fff')).join('') +
      r(60, 520, 960, 700, '#f4f4f6', 24) + r(60, 520, 960, 120, '#ffffff') + r(60, 560, 960, 24, '#1e9e5a') + r(60, 590, 960, 24, '#f58a1f') + r(60, 620, 960, 24, '#e53935') +
      r(130, 690, 820, 420, '#bfe9ff', 18) + r(130, 690, 820, 420, '#ffe9a855', 18) +
      // shelves
      [0, 1, 2].map((i) => r(160, 760 + i * 110, 760, 10, '#7c8794') + [0, 1, 2, 3, 4, 5, 6].map((k) => r(176 + k * 108, 700 + i * 110 + 20, 70, 70, ['#ef5350', '#42a5f5', '#ffca28', '#66bb6a', '#ab47bc', '#ff7043', '#26c6da'][(k + i) % 7], 10)).join('')).join('') +
      awning(40, 640, 1000, 50, '#ffffff', '#1e9e5a', 12) + ground(1220, '#4a5568', '#ffffff55'),
  };
};

S.phone = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + cloud(200, 260, 1.2) + cloud(840, 360, 0.9) +
      r(110, 560, 860, 660, '#ffffff', 28) + r(110, 560, 860, 130, pal.c, 28) + r(110, 640, 860, 50, pal.c) +
      // phone sign
      r(450, 590, 70, 110, '#ffffff', 14) + r(462, 604, 46, 70, pal.c, 6) + c(485, 690, 5, pal.c) +
      // sim card
      p('M700 600 h110 l36 36 v70 h-146 z', '#f6c445') + r(722, 646, 70, 44, '#d49a00', 6) +
      r(170, 760, 740, 340, '#e8f1fb', 18) + [0, 1, 2, 3, 4].map((i) => r(210 + i * 140, 800, 100, 190, '#1f2a37', 14) + r(220 + i * 140, 812, 80, 150, pal.d, 8)).join('') + ground(1220, '#6c7a89', '#ffffff66'),
  };
};

S.shop = (pal) => {
  const sky = grad([[0, '#fff1d6'], [1, '#ffd9a8']]);
  let shelves = '';
  for (let j = 0; j < 4; j++) {
    shelves += r(100, 620 + j * 150, 880, 12, '#8a6a4a');
    for (let k = 0; k < 8; k++) shelves += r(116 + k * 108, 548 + j * 150, 80, 72, pal.list[(k + j) % pal.list.length], 12);
  }
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(60, 380, 960, 880, '#fffaf0', 24) + r(60, 380, 960, 110, pal.c, 24) + c(540, 436, 70, '#ffffff') + yen(540, 436, 0.9, pal.d) + shelves + ground(1260, '#cdb48c', '#ffffff55'),
  };
};

S.bank = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let cols = '';
  for (let i = 0; i < 6; i++) cols += r(170 + i * 140, 600, 70, 520, '#f2efe6', 10);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + cloud(220, 240, 1.2) + cloud(820, 330, 1) +
      poly('100,600 540,360 980,600', '#d9d4c4') + r(100, 600, 880, 40, '#c7c1ae') + c(540, 520, 56, '#f6c445') + yen(540, 520, 0.7, '#fff3c4') +
      cols + r(100, 1120, 880, 50, '#c7c1ae') + r(60, 1170, 960, 60, '#b5af9b') + ground(1230, '#7b8794') + r(470, 880, 140, 240, '#6b4a2a', 10),
  };
};

S.street = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let bins = '';
  const colors = ['#2f6bd8', '#ef5350', '#22c55e', '#f59e0b'];
  for (let i = 0; i < 4; i++) bins += r(150 + i * 200, 1000, 130, 190, colors[i], 14) + r(140 + i * 200, 985, 150, 30, '#ffffff55', 8);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(860, 220, 70, pal.sun ?? '#fff3c4', 'opacity="0.9"') + cloud(200, 280, 1.1) +
      windows(0, 520, 5, 1, 190, 430, 30, pal.c, pal.c, 5) + windows(20, 560, 5, 3, 120, 70, 70, '#ffffff66', '#00000022', 2) +
      (pal.bins ? bins : '') + tree(960, 1030, 1) + ground(1190, '#6b7482', '#ffffff99'),
  };
};

S.crossing = (pal) => {
  const sky = grad([[0, '#ff9966'], [1, '#6a4c93']]);
  const signs = [['#ff3d71', 80, 330, 220, 120], ['#00c2ff', 330, 270, 200, 150], ['#ffd166', 570, 340, 230, 110], ['#7cfc9a', 820, 300, 190, 150]];
  let bil = '';
  for (const [col, x, y, w, h] of signs) bil += r(x, y, w, h, col, 14) + r(x + 14, y + 14, w - 28, h - 28, '#ffffff44', 8);
  let stripes = '';
  for (let i = 0; i < 9; i++) stripes += poly(`${60 + i * 120},1250 ${110 + i * 120},1250 ${90 + i * 130},1560 ${20 + i * 130},1560`, '#ffffffdd');
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(540, 700, 150, '#ffd9a8', 'opacity="0.5"') +
      r(0, 450, 360, 800, '#3b2f5c') + r(720, 400, 360, 850, '#322552') + r(300, 560, 480, 690, '#4a3a75') +
      windows(20, 500, 3, 6, 80, 60, 30, '#ffe9a8', '#5b4b86', 9) + windows(740, 450, 3, 7, 80, 60, 30, '#ffe9a8', '#5b4b86', 4) + windows(330, 610, 4, 6, 80, 60, 30, '#ffe9a8', '#5b4b86', 7) +
      bil + r(0, 1200, W, 420, '#2d2a3a') + stripes,
  };
};

S.ramen = (pal) => {
  const sky = grad([[0, '#2a1a12'], [1, '#5a2f1c']]);
  let noren = '';
  for (let i = 0; i < 5; i++) noren += r(140 + i * 160, 560, 140, 260, i % 2 ? '#d62828' : '#b01e1e', 10) + r(150 + i * 160, 600, 120, 8, '#ffffff66');
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(80, 360, 920, 860, '#6b4226', 24) + r(80, 360, 920, 110, '#2b1a10', 24) + lantern(190, 480, 0.8) + lantern(890, 480, 0.8) + r(250, 395, 580, 60, '#f6c445', 12) +
      r(140, 540, 800, 20, '#3e2a1a') + noren +
      // bowl
      e(540, 1010, 230, 70, '#fff', 'opacity="0.1"') + p('M330 940 h420 q-10 170 -210 190 q-200 -20 -210 -190z', '#f4efe6') + e(540, 940, 210, 44, '#f6a54a') + e(540, 936, 160, 28, '#ffd98a') + [0, 1, 2].map((i) => c(470 + i * 70, 926, 22, '#ffffff')).join('') +
      [0, 1, 2].map((i) => `<path d="M${470 + i * 70} 880 q-30 -50 0 -100 q30 -50 0 -100" stroke="#ffffff88" stroke-width="10" fill="none" stroke-linecap="round"/>`).join('') +
      r(60, 1150, 960, 70, '#3b2415') + ground(1220, '#2a1d14'),
  };
};

S.post = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + cloud(220, 260, 1.2) + cloud(850, 380, 1) +
      r(140, 520, 800, 700, '#fdfbf7', 22) + r(140, 520, 800, 110, '#e60012', 22) +
      // post mark
      c(540, 575, 66, '#ffffff') + p('M505 548 h70 M510 566 h60 M540 548 v62 M514 582 h52 v28 h-52z', 'none', 'stroke="#e60012" stroke-width="8" stroke-linejoin="round" stroke-linecap="round"') +
      windows(190, 700, 3, 1, 190, 240, 30, '#cfe8ff', '#cfe8ff') + r(790, 1010, 110, 210, '#e60012', 16) + r(810, 1040, 70, 14, '#7a000a', 6) + ground(1220, '#8896a6', '#ffffff77'),
  };
};

S.cafe = (pal) => {
  const sky = grad([[0, '#ffe8d0'], [1, '#ffd0b0']]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(100, 440, 880, 780, '#fffaf2', 24) + awning(80, 440, 920, 110, '#8a5a3c', '#f2d4b5', 10) +
      // cup sign
      c(540, 360, 70, '#8a5a3c') + p('M500 340 h80 q0 50 -40 52 q-40 -2 -40 -52z', '#fffaf2') + p('M580 348 q26 0 26 18 q0 18 -26 18', 'none', 'stroke="#fffaf2" stroke-width="8"') +
      windows(150, 620, 2, 1, 330, 340, 40, '#fff0c9', '#fff0c9') + r(540, 640, 6, 300, '#8a5a3c55') +
      // tables
      [0, 1].map((i) => e(240 + i * 500, 1120, 90, 24, '#8a5a3c') + r(236 + i * 500, 1130, 8, 80, '#6b4226') + c(240 + i * 500, 1090, 22, '#ffffff')).join('') + ground(1220, '#cbb89c'),
  };
};

S.library = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let books = '';
  const bc = ['#e57373', '#64b5f6', '#ffd54f', '#81c784', '#ba68c8', '#ff8a65', '#4db6ac', '#a1887f'];
  for (let j = 0; j < 4; j++) {
    books += r(110, 560 + j * 160, 860, 14, '#6b4226');
    let x = 124;
    let k = 0;
    while (x < 940) {
      const w = 34 + ((k * 7) % 5) * 8;
      const h = 90 + ((k * 13) % 4) * 14;
      books += r(x, 560 + j * 160 - h, w, h, bc[(k + j) % bc.length], 4);
      x += w + 6;
      k++;
    }
  }
  return { defs: sky.def, body: r(0, 0, W, H, sky.ref) + r(80, 330, 920, 880, '#8a6a4a', 14) + r(100, 350, 880, 840, '#f2e4cc', 8) + books + ground(1210, '#b08a5e') + c(900, 250, 70, '#fff3c4', 'opacity="0.0"'), };
};

S.classroom = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(0, 0, W, 1180, '#f6f1e7') + r(110, 300, 860, 500, '#2f5d50', 14) + r(110, 300, 860, 500, 'none', 'stroke="#8a6a4a" stroke-width="22"') +
      // board scribbles (kana-like shapes)
      p('M240 460 q60 -60 120 0 t120 0 M240 560 h260 M600 440 v230 M700 520 q60 -50 120 0', 'none', 'stroke="#ffffffcc" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"') +
      c(860, 700, 28, '#ffffff') + r(120, 800, 840, 26, '#8a6a4a') +
      windows(0, 880, 4, 1, 220, 120, 40, '#00000000', '#00000000') +
      [0, 1, 2].map((i) => r(130 + i * 300, 1000, 230, 24, '#b9885a', 6) + r(150 + i * 300, 1024, 12, 150, '#7a5a3a') + r(330 + i * 300, 1024, 12, 150, '#7a5a3a')).join('') + ground(1180, '#d9c19a'),
  };
};

S.rain = (pal) => {
  const sky = grad([[0, '#6b7a8f'], [1, '#aab6c5']]);
  let drops = '';
  for (let i = 0; i < 60; i++) drops += line((i * 97) % W, (i * 211) % 1100, ((i * 97) % W) - 18, ((i * 211) % 1100) + 60, '#ffffffaa', 5);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + cloud(220, 200, 1.6, '#8e9bad', 1) + cloud(760, 250, 1.8, '#7f8ea2', 1) + cloud(500, 120, 1.4, '#9aa6b6', 1) + drops +
      windows(0, 620, 5, 1, 190, 480, 30, '#7f8ea2', '#7f8ea2') +
      // umbrella
      `<g transform="translate(540 1000)">${p('M-300 0 q300 -330 600 0 q-75 -50 -150 0 q-75 -50 -150 0 q-75 -50 -150 0 q-75 -50 -150 0z', pal.c)}${line(0, 0, 0, 230, '#4a4a55', 12)}${p('M0 230 q0 50 -50 40', 'none', 'stroke="#4a4a55" stroke-width="12" stroke-linecap="round"')}</g>` +
      ground(1380, '#5d6a7c') + e(300, 1440, 140, 18, '#ffffff33') + e(780, 1500, 180, 20, '#ffffff33'),
  };
};

S.pharmacy = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + cloud(200, 260, 1.1) + cloud(860, 340, 0.9) +
      r(120, 520, 840, 700, '#ffffff', 22) + r(120, 520, 840, 110, pal.c, 22) + c(540, 575, 66, '#ffffff') + r(528, 535, 24, 80, pal.c, 6) + r(500, 563, 80, 24, pal.c, 6) +
      windows(170, 700, 3, 1, 230, 260, 40, '#e6f7ee', '#e6f7ee') + [0, 1, 2].map((i) => r(200 + i * 270, 760, 170, 150, '#ffffff', 10) + r(220 + i * 270, 790, 60, 90, pal.d, 8) + c(330 + i * 270, 850, 30, '#ffca28')).join('') +
      ground(1220, '#9aa7b5', '#ffffff77'),
  };
};

S.supermarket = (pal) => S.shop({ ...pal, list: ['#ef5350', '#66bb6a', '#ffca28', '#42a5f5', '#ff9800', '#ab47bc'] });

S.japanhouse = (pal) => {
  const sky = grad([[0, '#fde7c8'], [1, '#fbd3a0']]);
  let shoji = '';
  for (let i = 0; i < 3; i++) shoji += r(150 + i * 270, 560, 250, 520, '#fffdf6', 6) + r(150 + i * 270, 560, 250, 520, 'none', 'stroke="#8a6a4a" stroke-width="10"') + [1, 2, 3].map((k) => line(150 + i * 270, 560 + k * 130, 400 + i * 270, 560 + k * 130, '#8a6a4a', 6)).join('') + line(275 + i * 270, 560, 275 + i * 270, 1080, '#8a6a4a', 6);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + poly('40,520 540,330 1040,520', '#5a4636') + r(110, 520, 860, 580, '#d9b98c', 10) + shoji + r(110, 1080, 860, 50, '#8a6a4a') +
      // shoes at genkan
      e(300, 1180, 60, 20, '#3d4a5a') + e(420, 1190, 56, 18, '#8a3b3b') + ground(1130, '#a8c98a') + r(0, 1130, W, 20, '#7ea65f') + tree(980, 1060, 0.9, '#3d9e6a'),
  };
};

S.temple = (pal) => {
  const sky = grad([[0, '#ffb199'], [1, '#ffe0b5']]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(820, 300, 100, '#fff3c4', 'opacity="0.9"') +
      // gate
      poly('130,560 540,400 950,560 900,610 180,610', '#3b3b46') + r(190, 610, 700, 40, '#e8412f') + r(220, 650, 90, 560, '#e8412f') + r(770, 650, 90, 560, '#e8412f') + r(310, 650, 460, 40, '#c4321f') +
      lantern(540, 700, 1.7, '#e8412f') + sakura(130, 880, 1.1) + sakura(960, 900, 1) +
      r(0, 1210, W, 410, '#c9b79c') + [0, 1, 2, 3].map((i) => r(300 + i * 12, 1260 + i * 80, 480 - i * 24, 38, '#b5a285')).join(''),
  };
};

S.taxi = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(200, 240, 70, '#fff3c4', 'opacity="0.9"') + windows(0, 640, 5, 1, 190, 470, 30, pal.c, pal.c, 8) + windows(20, 700, 5, 3, 120, 70, 70, '#ffffff55', '#00000022', 4) +
      ground(1110, '#59616e', '#ffffffaa') +
      // taxi
      `<g transform="translate(120 840)">${r(0, 150, 840, 170, '#ffc400', 60)}${p('M170 150 q60 -150 250 -150 h200 q120 0 180 150z', '#ffc400')}${p('M220 140 q40 -100 170 -100 h40 v100z M470 40 h130 q80 0 120 100 h-250z', '#bfe9ff')}${r(330, -40, 180, 56, '#ffffff', 12)}${r(350, -26, 140, 28, '#2f6bd8', 6)}${c(210, 330, 70, '#22272e')}${c(210, 330, 30, '#aab4c0')}${c(650, 330, 70, '#22272e')}${c(650, 330, 30, '#aab4c0')}</g>`,
  };
};

S.koban = (pal) => {
  const sky = grad([[0, '#1a2a52'], [1, '#42588f']]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(170, 200, 56, '#fff3c4') + [[400, 140], [620, 230], [860, 120], [980, 300]].map(([x, y]) => c(x, y, 5, '#fff')).join('') +
      r(210, 600, 660, 620, '#e9edf3', 18) + poly('180,600 540,420 900,600', '#2f4fa3') + c(540, 540, 40, '#ffd166', 'opacity="1"') + c(540, 540, 70, '#ffd16655') + r(260, 700, 560, 140, '#ffffff', 10) +
      r(300, 880, 200, 340, '#334e9a', 10) + r(560, 880, 220, 240, '#bfe9ff', 10) + ground(1220, '#4a5568', '#ffffff55'),
  };
};

S.board = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let notes = '';
  const cols = ['#ffe082', '#ffab91', '#a5d6a7', '#90caf9', '#ce93d8', '#fff59d'];
  for (let i = 0; i < 6; i++) notes += r(170 + (i % 3) * 270, 480 + Math.floor(i / 3) * 330, 230, 280, cols[i], 8) + [1, 2, 3, 4].map((k) => line(190 + (i % 3) * 270, 480 + Math.floor(i / 3) * 330 + 40 + k * 44, 380 + (i % 3) * 270, 480 + Math.floor(i / 3) * 330 + 40 + k * 44, '#00000033', 6)).join('') + c(285 + (i % 3) * 270, 494 + Math.floor(i / 3) * 330, 10, '#e53935');
  return { defs: sky.def, body: r(0, 0, W, H, sky.ref) + r(120, 400, 840, 760, '#c89a6a', 20) + r(150, 430, 780, 700, '#e8cfa6', 10) + notes + yen(920, 380, 0.8) + ground(1230, '#9a7b57') };
};

S.phonecall = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + [0, 1, 2].map((i) => `<path d="M${640 + i * 70} ${640 - i * 70} q${130 + i * 40} ${130 + i * 40} 0 ${260 + i * 140}" stroke="#ffffffaa" stroke-width="16" fill="none" stroke-linecap="round"/>`).join('') +
      r(230, 420, 380, 760, '#1f2a37', 56) + r(256, 470, 328, 640, '#e8f1fb', 30) + c(420, 570, 70, pal.c) + r(340, 660, 160, 22, '#9aa7b5', 11) + r(300, 720, 240, 18, '#c7d3e0', 9) + r(300, 770, 200, 18, '#c7d3e0', 9) +
      c(420, 1020, 56, '#22c55e') + p('M398 1000 q10 30 40 40 l14 -14 -22 -14 -10 8 q-14 -6 -20 -20 l8 -10 -14 -22z', '#fff') + ground(1300, '#00000022'),
  };
};

S.office = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(0, 0, W, 1100, '#eef2f7') + r(90, 260, 900, 480, '#bfe3ff', 16) + r(90, 260, 900, 480, 'none', 'stroke="#ffffff" stroke-width="20"') + line(540, 260, 540, 740, '#ffffff', 14) +
      windows(150, 400, 6, 1, 120, 300, 20, '#9ccbf0', '#9ccbf0') + c(820, 380, 60, '#fff3c4', 'opacity="0.9"') +
      // desk
      r(120, 900, 840, 36, '#8a6a4a', 8) + r(160, 936, 26, 190, '#6b4e34') + r(894, 936, 26, 190, '#6b4e34') + r(380, 780, 300, 120, '#1f2a37', 14) + r(396, 794, 268, 88, pal.c, 8) + r(500, 900, 60, 14, '#1f2a37') +
      r(750, 840, 60, 60, '#ffffff', 8) + ground(1100, '#cdd6e0'),
  };
};

S.fuji = (pal) => {
  const sky = grad([[0, '#8ec5ff'], [1, '#e6f4ff']]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(860, 260, 80, '#fff3c4') + cloud(220, 280, 1.4) + cloud(780, 460, 1) +
      poly('-40,1100 540,420 1120,1100', '#5b7aa8') + poly('540,420 420,620 500,590 560,660 620,590 700,620', '#ffffff') +
      poly('-40,1100 300,780 700,1100', '#6f8fbd') + r(0, 1090, W, 530, '#3d8fd6') + e(540, 1260, 360, 60, '#ffffff22') + e(540, 1240, 200, 20, '#ffffff33') +
      sakura(150, 880, 1.2) + sakura(940, 910, 1) + r(0, 1380, W, 240, '#7ec98f'),
  };
};

S.ryokan = (pal) => {
  const sky = grad([[0, '#2a1d3e'], [1, '#5b3a63']]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(860, 220, 66, '#fff3c4') + [[200, 160], [500, 120], [720, 300]].map(([x, y]) => c(x, y, 5, '#fff')).join('') +
      poly('60,560 540,380 1020,560', '#4a3a2a') + r(130, 560, 820, 560, '#7a5a3a', 8) + windows(160, 600, 3, 1, 240, 360, 30, '#ffd98a', '#ffd98a') +
      [0, 1, 2].map((i) => line(160 + i * 270 + 120, 600, 160 + i * 270 + 120, 960, '#7a5a3a', 8)).join('') + lantern(190, 1010, 0.9, '#ff7043') + lantern(890, 1010, 0.9, '#ff7043') +
      r(130, 1120, 820, 40, '#3b2a1c') + ground(1160, '#2e5d4a') + e(540, 1300, 220, 40, '#ffffff22'),
  };
};

S.gifts = (pal) => {
  const sky = grad([[0, '#fff1e0'], [1, '#ffd6c0']]);
  const boxes = [[160, 880, 260, 260, '#ef5350', '#ffd54f'], [470, 800, 300, 340, '#42a5f5', '#ffffff'], [800, 940, 190, 200, '#66bb6a', '#fff59d'], [330, 640, 200, 200, '#ab47bc', '#ffd54f']];
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(80, 400, 920, 840, '#fffaf2', 24) + r(80, 400, 920, 100, '#e8412f', 24) + lantern(160, 520, 0.7) + lantern(920, 520, 0.7) +
      boxes.map(([x, y, w, h, a, b]) => r(x, y, w, h, a, 16) + r(x + w / 2 - 14, y, 28, h, b) + r(x, y + h / 2 - 14, w, 28, b) + c(x + w / 2, y - 4, 26, b)).join('') + ground(1240, '#d9c19a'),
  };
};

S.party = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  let flags = '';
  for (let i = 0; i < 12; i++) flags += poly(`${i * 90},${240 + Math.sin(i) * 30} ${i * 90 + 70},${240 + Math.sin(i) * 30} ${i * 90 + 35},${320 + Math.sin(i) * 30}`, ['#ef5350', '#ffd54f', '#42a5f5', '#66bb6a'][i % 4]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + path0() + line(0, 230, W, 280, '#ffffff99', 6) + flags +
      // balloons
      [[160, 520, '#ef5350'], [300, 440, '#ffd54f'], [820, 460, '#42a5f5'], [940, 540, '#ab47bc']].map(([x, y, col]) => e(x, y, 60, 76, col) + line(x, y + 76, x, y + 300, '#ffffff99', 4)).join('') +
      // table
      r(120, 980, 840, 30, '#8a6a4a', 8) + r(160, 1010, 26, 200, '#6b4e34') + r(894, 1010, 26, 200, '#6b4e34') +
      [0, 1, 2, 3].map((i) => e(240 + i * 190, 970, 70, 16, '#ffffff') + c(240 + i * 190, 940, 34, ['#ff8a65', '#81c784', '#ffd54f', '#f48fb1'][i])).join('') + ground(1200, '#d6b68b'),
  };
  function path0() {
    return '';
  }
};

S.morning = (pal) => {
  const sky = grad([[0, '#ffd6a5'], [1, '#fff1d6']]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + r(160, 280, 760, 760, '#ffffff', 20) + r(180, 300, 720, 720, '#bfe3ff', 10) + c(540, 760, 140, '#ffb347') + [0, 1, 2, 3, 4, 5, 6, 7].map((i) => line(540 + Math.cos(i * 0.785) * 170, 760 + Math.sin(i * 0.785) * 170, 540 + Math.cos(i * 0.785) * 230, 760 + Math.sin(i * 0.785) * 230, '#ffb347', 14)).join('') +
      line(540, 300, 540, 1020, '#ffffff', 14) + line(180, 660, 900, 660, '#ffffff', 14) +
      // alarm clock
      c(540, 1180, 120, '#ef5350') + c(540, 1180, 92, '#ffffff') + line(540, 1180, 540, 1120, '#333', 10) + line(540, 1180, 590, 1200, '#333', 10) + c(440, 1070, 36, '#ef5350') + c(640, 1070, 36, '#ef5350') + ground(1330, '#d9c19a'),
  };
};

S.friends = (pal) => {
  const sky = grad([[0, pal.a], [1, pal.b]]);
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(860, 240, 76, pal.sun ?? '#fff3c4') + cloud(220, 280, 1.2) +
      // clock tower
      r(440, 420, 200, 640, '#e8e2d4', 12) + poly('420,420 540,300 660,420', '#8a5a3c') + c(540, 560, 80, '#ffffff') + c(540, 560, 80, 'none', 'stroke="#8a5a3c" stroke-width="12"') + line(540, 560, 540, 510, '#333', 8) + line(540, 560, 580, 580, '#333', 8) +
      sakura(150, 840, 1.2) + sakura(930, 870, 1.1) +
      // bench
      r(240, 1110, 600, 26, '#8a5a3c', 8) + r(260, 1060, 560, 20, '#a56e48', 8) + r(280, 1136, 20, 80, '#6b4226') + r(780, 1136, 20, 80, '#6b4226') + ground(1230, '#8fcf9e') + r(0, 1230, W, 20, '#6fb184'),
  };
};

S.skyline = (pal) => {
  const sky = grad([[0, '#ff9a8b'], [0.55, '#ffd6a5'], [1, '#ffeacc']]);
  let b = '';
  for (let i = 0; i < 9; i++) {
    const h = 260 + ((i * 97) % 5) * 90;
    b += r(i * 125 - 20, 1160 - h, 110, h, ['#6a4c93', '#5a3f82', '#7d5ba6'][i % 3]) + windows(i * 125 - 8, 1180 - h, 3, Math.floor(h / 70) - 1, 22, 28, 12, '#ffe9a8', '#00000000', i + 2);
  }
  return {
    defs: sky.def,
    body:
      r(0, 0, W, H, sky.ref) + c(540, 760, 220, '#fff3c4', 'opacity="0.7"') + c(540, 760, 150, '#ffd98a') + b +
      // tokyo tower
      poly('480,1160 540,520 600,1160', '#e8412f') + line(540, 520, 540, 400, '#e8412f', 10) + r(500, 780, 80, 20, '#ffffff', 4) + r(486, 960, 108, 20, '#ffffff', 4) + [0, 1, 2, 3, 4].map((i) => line(505 + i * 8, 1160 - i * 70, 575 - i * 8, 1160 - i * 70, '#ffffff77', 4)).join('') +
      ground(1160, '#3a2a55') + sakura(120, 1000, 1) + sakura(980, 1020, 1),
  };
};

// episode -> [scene type, palette]
const P = (a, b, extra = {}) => ({ a, b, c: '#cfd8e3', d: '#2f6bd8', ...extra });
const EP = {
  1: ['airport', P('#7ec8ff', '#e6f4ff')],
  2: ['station', P('#8ec5ff', '#e6f4ff')],
  3: ['train', P('#ffb199', '#ffe0b5', { c: '#8a7ba8', d: '#2f6bd8' })],
  4: ['home', P('#9bd0ff', '#e8f6ff', { c: '#f1e7d6' })],
  5: ['konbini', P('#1a2145', '#3b3f7a')],
  6: ['phone', P('#a8d8ff', '#eef8ff', { c: '#2f6bd8', d: '#7fc9ff' })],
  7: ['shop', P('#fff1d6', '#ffd9a8', { c: '#e53935', d: '#ffffff', list: ['#e53935', '#ffd54f', '#42a5f5', '#66bb6a', '#ab47bc', '#ff9800'] })],
  8: ['bank', P('#a8d0ff', '#f0f8ff')],
  9: ['street', P('#b8e0ff', '#f3fbff', { c: '#d8dee9', bins: true })],
  10: ['party', P('#ffb199', '#ff7e9d')],
  11: ['morning', P('#ffd6a5', '#fff1d6')],
  12: ['crossing', P('#ff9966', '#6a4c93')],
  13: ['ramen', P('#2a1a12', '#5a2f1c')],
  14: ['post', P('#bfe3ff', '#f4fbff')],
  15: ['shop', P('#ffe3ee', '#ffd0e0', { c: '#e91e63', d: '#ffffff', list: ['#f48fb1', '#90caf9', '#fff59d', '#a5d6a7', '#ce93d8', '#ffab91'] })],
  16: ['friends', P('#a8dcff', '#fff4e6')],
  17: ['friends', P('#ff9a8b', '#ffd6a5', { sun: '#ffb347' })],
  18: ['cafe', P('#ffe8d0', '#ffd0b0')],
  19: ['library', P('#e8d9bd', '#f6ecd8')],
  20: ['library', P('#cfe3d4', '#eef7f0')],
  21: ['classroom', P('#bfe3ff', '#f4fbff')],
  22: ['classroom', P('#ffe3b3', '#fff4e0')],
  23: ['rain', P('#6b7a8f', '#aab6c5', { c: '#ffca28' })],
  24: ['pharmacy', P('#c9f0dc', '#f0fff7', { c: '#1faa6b', d: '#a5d6a7' })],
  25: ['pharmacy', P('#d6e9ff', '#f4faff', { c: '#e53935', d: '#ffcdd2' })],
  26: ['supermarket', P('#e2f6e6', '#fff', { c: '#2e9e5b', d: '#ffffff' })],
  27: ['japanhouse', P('#fde7c8', '#fbd3a0')],
  28: ['temple', P('#ffb199', '#ffe0b5')],
  29: ['taxi', P('#8ec5ff', '#e6f4ff', { c: '#b8c4d4' })],
  30: ['koban', P('#1a2a52', '#42588f')],
  31: ['board', P('#d6ecff', '#f4fbff')],
  32: ['phonecall', P('#8ec5ff', '#4a7bd8', { c: '#2f6bd8' })],
  33: ['office', P('#cfe8ff', '#f4fbff', { c: '#2f6bd8' })],
  34: ['office', P('#ffe9c4', '#fff7e6', { c: '#e8412f' })],
  35: ['office', P('#d8e0ee', '#f1f4fa', { c: '#6a4c93' })],
  36: ['fuji', P('#8ec5ff', '#e6f4ff')],
  37: ['ryokan', P('#2a1d3e', '#5b3a63')],
  38: ['gifts', P('#fff1e0', '#ffd6c0')],
  39: ['party', P('#a8dcff', '#c7a8ff')],
  40: ['skyline', P('#ff9a8b', '#ffeacc')],
};

async function writeWebp(svgText, file, w, h, quality) {
  await sharp(Buffer.from(svgText)).resize(w, h).webp({ quality }).toFile(file);
}

// ---------------------------------------------------------------- characters
const SKIN = { light: '#f6d5b8', tan: '#e8b98f', warm: '#d99b6c', brown: '#b87a4b' };
const HAIR = { black: '#23201f', brown: '#5a3a28', dark: '#2f2622', grey: '#9a9aa0', auburn: '#7a3b22', blond: '#d9b45a' };

/** name -> look. acc: glasses|cap|police|taxi|headband|mask|apron|tie|headset|scarf|stethoscope|nametag|hat */
const CH = {
  salem: { bg: ['#ffcf9f', '#ff9a8b'], skin: SKIN.warm, hair: HAIR.dark, style: 'short', outfit: '#2f6bd8', acc: ['beard', 'tee'] },
  yuki: { bg: ['#ffd1e0', '#ffa8c5'], skin: SKIN.light, hair: HAIR.black, style: 'ponytail', outfit: '#ff7aa8', female: true, acc: [] },
  mina: { bg: ['#d9c7ff', '#b49cff'], skin: SKIN.light, hair: HAIR.brown, style: 'bob', outfit: '#7e57c2', female: true, acc: ['glasses'] },
  anna: { bg: ['#c7f0ff', '#8fd8ff'], skin: SKIN.light, hair: HAIR.blond, style: 'long', outfit: '#26a69a', female: true, acc: [] },
  kenta: { bg: ['#c6f1d6', '#8fdcab'], skin: SKIN.tan, hair: HAIR.black, style: 'spiky', outfit: '#43a047', acc: ['tee'] },
  wang: { bg: ['#ffe9a8', '#ffcf66'], skin: SKIN.light, hair: HAIR.black, style: 'short', outfit: '#e53935', acc: ['glasses'] },
  tanaka_sensei: { bg: ['#d6e4ff', '#a9c4ff'], skin: SKIN.light, hair: HAIR.black, style: 'bun', outfit: '#37474f', female: true, acc: ['glasses', 'scarf'] },
  yamada: { bg: ['#ffe3c4', '#ffc58f'], skin: SKIN.light, hair: HAIR.grey, style: 'bun', outfit: '#8d6e63', female: true, acc: ['cardigan'] },
  yuki_mother: { bg: ['#ffe0ec', '#ffb8d2'], skin: SKIN.light, hair: HAIR.brown, style: 'bun', outfit: '#f06292', female: true, acc: ['apron'] },
  senpai_sato: { bg: ['#dcdcf5', '#b4b4e8'], skin: SKIN.tan, hair: HAIR.black, style: 'short', outfit: '#37474f', acc: ['tie', 'nametag'] },
  immigration_officer: { bg: ['#cfe3ff', '#9ec5ff'], skin: SKIN.light, hair: HAIR.black, style: 'short', outfit: '#263a5e', acc: ['cap', 'tie'] },
  announcement: { bg: ['#d6e4ff', '#a3c0ff'], skin: SKIN.light, hair: HAIR.black, style: 'bob', outfit: '#1e4fa3', female: true, acc: ['headset', 'cap'] },
  station_staff: { bg: ['#d6e4ff', '#a3c0ff'], skin: SKIN.tan, hair: HAIR.black, style: 'short', outfit: '#1e4fa3', acc: ['cap', 'tie'] },
  bank_teller: { bg: ['#d8e8d0', '#b4d6a5'], skin: SKIN.light, hair: HAIR.black, style: 'bob', outfit: '#2e7d5b', female: true, acc: ['scarf', 'nametag'] },
  cafe_staff: { bg: ['#f2dcc7', '#e0b995'], skin: SKIN.tan, hair: HAIR.brown, style: 'short', outfit: '#8a5a3c', acc: ['apron'] },
  clinic_receptionist: { bg: ['#d9f3ee', '#aee3d8'], skin: SKIN.light, hair: HAIR.black, style: 'bun', outfit: '#80cbc4', female: true, acc: ['nametag'] },
  clothes_clerk: { bg: ['#ffdce8', '#ffb3cf'], skin: SKIN.light, hair: HAIR.brown, style: 'ponytail', outfit: '#ec407a', female: true, acc: ['nametag'] },
  customer_man: { bg: ['#e3e8ef', '#c4cdd9'], skin: SKIN.tan, hair: HAIR.grey, style: 'short', outfit: '#546e7a', acc: ['glasses'] },
  doctor: { bg: ['#e8f4ff', '#bfe0ff'], skin: SKIN.light, hair: HAIR.black, style: 'short', outfit: '#ffffff', acc: ['glasses', 'stethoscope', 'coat'] },
  konbini_clerk: { bg: ['#d8f2e0', '#a8e0bd'], skin: SKIN.light, hair: HAIR.black, style: 'short', outfit: '#1e9e5a', acc: ['cap', 'nametag'] },
  librarian: { bg: ['#e8dcc7', '#d1bd9a'], skin: SKIN.light, hair: HAIR.grey, style: 'bun', outfit: '#6d4c41', female: true, acc: ['glasses'] },
  omiyage_clerk: { bg: ['#ffe0d1', '#ffb99a'], skin: SKIN.light, hair: HAIR.black, style: 'bun', outfit: '#e8412f', female: true, acc: ['apron'] },
  passerby: { bg: ['#e0e6ee', '#bdc8d6'], skin: SKIN.tan, hair: HAIR.brown, style: 'short', outfit: '#78909c', acc: ['scarf'] },
  pharmacist: { bg: ['#d8f5e5', '#a6e3c2'], skin: SKIN.light, hair: HAIR.black, style: 'short', outfit: '#ffffff', acc: ['coat', 'mask', 'nametag'] },
  phone_shop_staff: { bg: ['#d6e8ff', '#9fcbff'], skin: SKIN.light, hair: HAIR.brown, style: 'ponytail', outfit: '#2f6bd8', female: true, acc: ['headset', 'nametag'] },
  police_officer: { bg: ['#c9d3ee', '#97a8d9'], skin: SKIN.tan, hair: HAIR.black, style: 'short', outfit: '#243b7a', acc: ['police', 'tie'] },
  post_clerk: { bg: ['#ffd6d6', '#ffa8a8'], skin: SKIN.light, hair: HAIR.black, style: 'short', outfit: '#e60012', acc: ['cap', 'nametag'] },
  ramen_staff: { bg: ['#ffe0c7', '#ffb67a'], skin: SKIN.tan, hair: HAIR.black, style: 'bald', outfit: '#2b2b30', acc: ['headband', 'apron'] },
  ryokan_staff: { bg: ['#e6d6f2', '#c8a8e3'], skin: SKIN.light, hair: HAIR.black, style: 'bun', outfit: '#7b4a8a', female: true, acc: ['kimono'] },
  store_manager: { bg: ['#d9d9e8', '#b5b5d0'], skin: SKIN.tan, hair: HAIR.black, style: 'short', outfit: '#3d3d5c', acc: ['tie', 'glasses', 'nametag'] },
  supermarket_staff: { bg: ['#e2f6e6', '#b6e6c0'], skin: SKIN.light, hair: HAIR.brown, style: 'short', outfit: '#43a047', acc: ['apron', 'cap'] },
  taxi_driver: { bg: ['#fff0b3', '#ffd966'], skin: SKIN.tan, hair: HAIR.grey, style: 'short', outfit: '#263238', acc: ['taxi', 'tie'] },
  temple_guide: { bg: ['#ffd9c2', '#ffa985'], skin: SKIN.light, hair: HAIR.black, style: 'bald', outfit: '#8a3b22', acc: ['robe'] },
  persona_polite_sensei: { bg: ['#d6e4ff', '#9fbfff'], skin: SKIN.light, hair: HAIR.black, style: 'bun', outfit: '#37474f', female: true, acc: ['glasses', 'scarf'] },
  persona_casual_friend: { bg: ['#ffe3a8', '#ffb86b'], skin: SKIN.tan, hair: HAIR.brown, style: 'spiky', outfit: '#ff7043', acc: ['tee', 'headphones'] },
  persona_tsundere: { bg: ['#ffc9de', '#ff8fb8'], skin: SKIN.light, hair: HAIR.auburn, style: 'twintail', outfit: '#c2185b', female: true, acc: ['ribbon'] },
  persona_kansai: { bg: ['#ffd1b3', '#ff9a5c'], skin: SKIN.warm, hair: HAIR.black, style: 'spiky', outfit: '#f9a825', acc: ['tee', 'headband2'] },
};

function avatar(name, L) {
  const g = grad([[0, L.bg[0]], [1, L.bg[1]]]);
  const skin = L.skin;
  const hair = L.hair;
  const dark = '#2b2220';
  const has = (k) => L.acc.includes(k);
  const cx = 256;
  let backHair = '';
  let frontHair = '';
  switch (L.style) {
    case 'long':
      backHair = p('M150 230 q-10 190 40 250 h132 q50 -60 40 -250 q-10 -120 -106 -120 q-96 0 -106 120z', hair);
      break;
    case 'bob':
      backHair = p('M156 235 q-8 120 20 160 h160 q28 -40 20 -160 q-6 -118 -100 -118 q-94 0 -100 118z', hair);
      break;
    case 'ponytail':
      backHair = p('M330 150 q90 20 70 150 q-10 60 -50 80 q20 -70 -30 -130z', hair);
      break;
    case 'twintail':
      backHair = p('M160 170 q-90 20 -70 170 q50 -10 70 -60z M352 170 q90 20 70 170 q-50 -10 -70 -60z', hair);
      break;
    case 'bun':
      backHair = c(cx, 108, 44, hair);
      break;
    default:
      break;
  }
  switch (L.style) {
    case 'bald':
      frontHair = '';
      break;
    case 'spiky':
      frontHair = p('M160 220 q-12 -120 96 -126 q108 6 96 126 q-20 -60 -50 -70 l-20 30 -26 -34 -26 34 -20 -30 q-30 10 -50 70z', hair);
      break;
    case 'short':
      frontHair = p('M162 225 q-10 -125 94 -128 q104 3 94 128 q-30 -70 -94 -70 q-64 0 -94 70z', hair);
      break;
    case 'bob':
    case 'long':
      frontHair = p('M160 232 q-8 -135 96 -138 q104 3 96 138 q-20 -90 -96 -86 q-76 -4 -96 86z', hair);
      break;
    default:
      frontHair = p('M160 228 q-8 -130 96 -134 q104 4 96 134 q-24 -78 -96 -76 q-72 -2 -96 76z', hair);
  }
  const body = r(96, 372, 320, 200, L.outfit, 70);
  let outfitExtra = '';
  if (has('tie')) outfitExtra += poly('256,372 238,388 256,470 274,388', '#c62828') + poly('222,372 256,420 290,372', '#ffffff');
  if (has('coat')) outfitExtra += r(96, 372, 320, 200, '#ffffff', 70) + poly('256,372 210,380 256,500 302,380', '#e8eef5') + r(236, 372, 40, 120, '#9ec5ff', 6);
  if (has('apron')) outfitExtra += r(176, 410, 160, 170, '#ffffff', 22) + r(196, 372, 12, 40, '#ffffff') + r(304, 372, 12, 40, '#ffffff');
  if (has('stethoscope')) outfitExtra += `<path d="M206 380 q0 90 50 90 q50 0 50 -90" stroke="#37474f" stroke-width="8" fill="none"/>` + c(256, 474, 14, '#90a4ae');
  if (has('nametag')) outfitExtra += r(300, 420, 54, 28, '#ffffff', 6) + r(308, 430, 38, 6, '#90a4ae', 3);
  if (has('scarf')) outfitExtra += r(196, 360, 120, 34, '#ef5350', 17);
  if (has('kimono')) outfitExtra += poly('220,372 256,470 292,372', '#f3e5f5') + r(206, 440, 100, 30, '#c2185b', 6);
  if (has('robe')) outfitExtra += poly('200,372 256,500 312,372', '#d7b98e');
  if (has('cardigan')) outfitExtra += r(96, 372, 66, 200, '#a1887f', 40) + r(350, 372, 66, 200, '#a1887f', 40);
  const neck = r(228, 320, 56, 70, skin, 20) + p('M228 350 q28 24 56 0 v14 h-56z', '#00000018');
  const head = e(cx, 230, 92, 104, skin) + e(164, 240, 16, 24, skin) + e(348, 240, 16, 24, skin);
  const eyeY = 240;
  const eyes =
    e(214, eyeY, 12, 16, dark) + e(298, eyeY, 12, 16, dark) + c(218, eyeY - 6, 4, '#fff') + c(302, eyeY - 6, 4, '#fff') +
    line(196, eyeY - 30, 230, eyeY - 34, hair === HAIR.grey ? '#777' : hair, 7) + line(282, eyeY - 34, 316, eyeY - 30, hair === HAIR.grey ? '#777' : hair, 7);
  const mouth = has('mask')
    ? p('M180 270 q76 80 152 0 v60 q-76 40 -152 0z', '#ffffff') + line(180, 272, 150, 262, '#ffffff', 5) + line(332, 272, 362, 262, '#ffffff', 5)
    : p('M228 290 q28 26 56 0', 'none', `stroke="${dark}" stroke-width="7" stroke-linecap="round"`);
  const cheeks = L.female ? c(190, 276, 15, '#ff8fa3', 'opacity="0.35"') + c(322, 276, 15, '#ff8fa3', 'opacity="0.35"') : '';
  let extras = '';
  if (has('glasses')) extras += `<g fill="none" stroke="#37474f" stroke-width="6">${c(214, eyeY, 28, 'none', 'stroke="#37474f" stroke-width="6"')}${c(298, eyeY, 28, 'none', 'stroke="#37474f" stroke-width="6"')}${line(242, eyeY, 270, eyeY, '#37474f', 6)}</g>`;
  if (has('beard')) extras += p('M170 270 q10 90 86 96 q76 -6 86 -96 q-30 40 -86 40 q-56 0 -86 -40z', hair) + p('M236 292 q20 14 40 0', 'none', 'stroke="#ffffff" stroke-width="6" stroke-linecap="round"');
  if (has('cap')) extras += p('M156 188 q4 -96 100 -98 q96 2 100 98 q-100 -26 -200 0z', L.outfit === '#e60012' ? '#e60012' : L.outfit) + r(176, 170, 160, 22, '#ffffff33', 11) + p('M170 190 q86 -26 172 0 q-10 20 -86 20 q-76 0 -86 -20z', '#00000033') + c(256, 128, 14, '#ffd54f');
  if (has('police')) extras += p('M150 192 q6 -100 106 -104 q100 4 106 104 q-106 -24 -212 0z', '#243b7a') + r(150, 186, 212, 22, '#1a2a52', 11) + c(256, 138, 20, '#ffd54f');
  if (has('taxi')) extras += p('M156 192 q6 -90 100 -94 q94 4 100 94 q-100 -22 -200 0z', '#263238') + r(156, 186, 200, 18, '#ffc400', 9);
  if (has('headband')) extras += r(160, 160, 192, 28, '#ffffff', 14) + c(256, 174, 10, '#e53935');
  if (has('headband2')) extras += r(160, 162, 192, 24, '#e53935', 12);
  if (has('headset')) extras += `<path d="M160 230 q0 -110 96 -112 q96 2 96 112" stroke="#37474f" stroke-width="10" fill="none"/>` + r(146, 220, 26, 50, '#37474f', 12) + r(340, 220, 26, 50, '#37474f', 12) + `<path d="M356 262 q0 40 -60 46" stroke="#37474f" stroke-width="7" fill="none"/>` + c(292, 310, 9, '#e53935');
  if (has('headphones')) extras += `<path d="M162 226 q0 -108 94 -108 q94 0 94 108" stroke="#263238" stroke-width="12" fill="none"/>` + r(146, 216, 28, 54, '#ff7043', 12) + r(338, 216, 28, 54, '#ff7043', 12);
  if (has('ribbon')) extras += poly('330,128 372,100 372,160', '#ff4081') + poly('330,128 288,100 288,160', '#ff4081') + c(330, 128, 12, '#c2185b');
  if (has('tee') && !L.female) extras += '';
  return svg(512, 512, g.def, r(0, 0, 512, 512, g.ref) + c(256, 560, 300, '#ffffff22') + backHair + body + outfitExtra + neck + head + frontHair + eyes + cheeks + mouth + extras);
}

// --------------------------------------------------------------------- run
let n = 0;
for (const [ep, [type, pal]] of Object.entries(EP)) {
  const b = S[type](pal);
  const s = svg(W, H, b.defs, b.body);
  const file = join(outScenes, `ep${String(ep).padStart(2, '0')}_bg.webp`);
  await writeWebp(s, file, 720, 1080, 80);
  n++;
}
for (const [name, look] of Object.entries(CH)) {
  await writeWebp(avatar(name, look), join(outChars, `${name}.webp`), 384, 384, 84);
  n++;
}
if (process.argv.includes('--svg')) {
  // debugging aid: also keep one SVG per type
  for (const [type, fn] of Object.entries(S)) {
    const b = fn(P('#8ec5ff', '#e6f4ff', { list: ['#ef5350', '#66bb6a', '#ffca28'], bins: true }));
    writeFileSync(join('/tmp', `scene_${type}.svg`), svg(W, H, b.defs, b.body));
  }
}
console.log(`Wrote ${n} images`);
