import fs from 'fs';
import {createServer} from 'vite';
import {
    assetsDir,
    pluginAssetsDir,
    pluginAssetsDevDir,
    resolveConfig,
} from './utils.js';

async function main() {
    const config = await resolveConfig('dev');
    transformBuildOptions(config)
    symLinkPluginAssets()

    const server = await createServer({
        ...config,
        configFile: false,
        root: assetsDir,
        logLevel: 'warn',
        server: {
            host: true,
            fs: {
                allow: [
                    assetsDir,
                    pluginAssetsDir
                ],
                strict: false
            }
        }
    });

    await server.listen();
}

function transformBuildOptions(config) {
    if (!pluginAssetsDir) {
        return
    }

    const input = Object.entries(config.build.rollupOptions.input).map(([key, originalPath]) => {
        const newPath = originalPath.replace(pluginAssetsDir, pluginAssetsDevDir)
        return [key, newPath]
    })

    config.build.rollupOptions.input = Object.fromEntries(input)
}

function symLinkPluginAssets() {
    if (!pluginAssetsDir) {
        return
    }

    try {
        fs.symlinkSync(pluginAssetsDir, pluginAssetsDevDir, 'dir')
    } catch (e) {
        if (e.code !== 'EEXIST') {
            throw e
        }
    }
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
