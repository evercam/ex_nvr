const esbuild = require('esbuild')
const vuePlugin = require("esbuild-vue")

const args = process.argv.slice(2)
const watch = args.includes('--watch')
const deploy = args.includes('--deploy')

const loader = {
  // Add loaders for images/fonts/etc, e.g. { '.svg': 'file' }
}

const plugins = [
  vuePlugin()
]

let opts = {
  entryPoints: ['js/app.js'],
  bundle: true,
  target: 'es2017',
  outdir: '../priv/static/assets',
  logLevel: 'info',
  loader,
  plugins
}

if (deploy) {
  opts = {
    ...opts,
    minify: true
  }
}

if (watch) {
    async function watchFunc() {
        let ctx = await esbuild.context({
            ...opts,
            sourcemap: 'inline'
        });
        await ctx.watch();
        console.log('Watching...');
    }
    watchFunc()
} else {
    esbuild.build(opts)
}
