import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { defu } from 'defu';
import tailwindcss from "tailwindcss";
import autoprefixer from "autoprefixer";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const assetsDir = path.join(__dirname, '..')
export const rootDir = path.join(assetsDir, '..');
export const outputDir = path.join(rootDir, 'priv', 'static', 'assets')
export const pluginDir = process.env.PLUGIN_PATHS
export const pluginAssetsDir = pluginDir ? path.resolve(pluginDir, 'assets') : ''
export const pluginAssetsDevDir = pluginDir ? path.resolve(assetsDir, 'plugins') : ''

export async function loadConfigFile(filePath, context = {}) {
  if (!fs.existsSync(filePath)) return {};
  const mod = await import(`file://${filePath}`);
  const resolved = mod.default || mod;

  return typeof resolved === 'function' ? resolved(context) : resolved;
}

export async function resolveConfig(command='build') {
  const baseVite = await loadConfigFile(
    path.join(assetsDir, 'vite.config.js'),
    { command }
  );
  const baseTwind = await loadConfigFile(
    path.join(assetsDir, 'tailwind.config.cjs'),
    { command }
  );

  let pluginVite = {}, pluginTwind = {};
  if (pluginDir && typeof pluginDir === 'string') {
    const assetsDir = path.join(pluginDir, 'assets');
    const maybe = name => path.join(assetsDir, name);

    pluginVite = await loadConfigFile(maybe('vite.config.js'), { command });
    pluginTwind = await loadConfigFile(maybe('tailwind.config.js'), { command });
  }

  const viteConfig = defu(pluginVite, baseVite);
  const tailwindConfig = defu(pluginTwind, baseTwind);

  viteConfig.css ??= {};
  viteConfig.css.postcss ??= {};
  viteConfig.css.postcss.plugins = [
    tailwindcss(tailwindConfig),
    autoprefixer()
  ];

  return viteConfig;
}
