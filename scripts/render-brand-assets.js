// Genera los PNG de iconos y splash a partir de Resources/Brand/halsyn-symbol.svg.
//
// Uso:  node scripts/render-brand-assets.js
// Requiere Playwright con Chromium (NODE_PATH debe incluir el módulo `playwright`).
// Es reproducible: ejecutar de nuevo tras cambiar el SVG maestro.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const svg = fs.readFileSync(path.join(root, 'Resources/Brand/halsyn-symbol.svg'), 'utf8');
const iosAssets = path.join(root, 'Apps/HalsyniOS/Resources/Assets.xcassets');
const watchAssets = path.join(root, 'Apps/HalsynWatch/Resources/Assets.xcassets');
const exportsDir = path.join(root, 'Resources/Brand/exports');

// Fondo de icono: verde profundo de marca con un leve degradado.
const iconBackground = `
  <div style="position:absolute;inset:0;background:linear-gradient(160deg,#134540 0%,#0E2D2A 48%,#081B1A 100%)"></div>`;

const symbolImg = `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;

function page({ size, background, symbolHeight, offsetY = 0 }) {
  return `<!doctype html><html><body style="margin:0">
    <div style="position:relative;width:${size}px;height:${size}px;overflow:hidden">
      ${background}
      <img src="${symbolImg}" style="position:absolute;left:50%;top:calc(50% + ${offsetY}px);
           height:${symbolHeight}px;transform:translate(-50%,-50%)"/>
    </div></body></html>`;
}

async function render(browser, html, size, out, transparent = false) {
  const p = await browser.newPage({ viewport: { width: size, height: size } });
  await p.setContent(html);
  await p.waitForTimeout(50);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  await p.screenshot({ path: out, omitBackground: transparent, clip: { x: 0, y: 0, width: size, height: size } });
  await p.close();
  console.log('✓', path.relative(root, out));
}

(async () => {
  const browser = await chromium.launch();
  // Icono iPhone (1024, sin transparencia; iOS aplica la máscara).
  await render(browser, page({ size: 1024, background: iconBackground, symbolHeight: 680, offsetY: 8 }), 1024,
    path.join(iosAssets, 'AppIcon.appiconset/AppIcon-1024.png'));
  // Icono Apple Watch (máscara circular: el símbolo debe caber en el círculo).
  await render(browser, page({ size: 1024, background: iconBackground, symbolHeight: 560, offsetY: 6 }), 1024,
    path.join(watchAssets, 'AppIcon.appiconset/AppIcon-1024.png'));
  // Símbolo transparente para la pantalla de lanzamiento (@1x, @2x, @3x de 120 pt).
  for (const scale of [1, 2, 3]) {
    const size = 120 * scale;
    await render(browser, page({ size, background: '', symbolHeight: size }), size,
      path.join(iosAssets, `LaunchSymbol.imageset/LaunchSymbol@${scale}x.png`), true);
  }
  // Exportaciones de marca.
  await render(browser, page({ size: 1024, background: '', symbolHeight: 1000 }), 1024,
    path.join(exportsDir, 'halsyn-symbol-1024.png'), true);
  await render(browser, page({ size: 1024, background: '<div style="position:absolute;inset:0;background:#FFFFFF"></div>', symbolHeight: 640, offsetY: 8 }), 1024,
    path.join(exportsDir, 'halsyn-icon-alt-white-1024.png'));
  await browser.close();
})();
