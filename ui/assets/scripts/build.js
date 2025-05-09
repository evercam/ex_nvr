import {assetsDir, resolveConfig} from './utils.js';
import { build as viteBuild } from 'vite';

async function main() {
  const config = await resolveConfig();

  await viteBuild(  {
    configFile: false,
    root: assetsDir,
    ...config
  })

  console.log('✅ Build complete!');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
