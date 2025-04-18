const fs = require("fs")
const path = require("path")

module.exports = {
  postComment,
  parseNervesBuildCommand,
  handleNervesBuildResult,
}

async function parseNervesBuildCommand({ github, context, core }) {
  const target = await parseBuildTarget({ github, context, core })
  const prData = await getPrData({ github, context })
  const version = await generateCustomVersion(prData, core)

  core.setOutput("target", target)
  core.setOutput("version", version)

  await postComment({
    github,
    context,
    body: `
      🛠️ Starting preview build for version: **${version}** for target **${
      formatTarget(target)
    }**
    This may take up to 15 minutes. You can check the progress on the [Github Actions page](https://github.com/evercam/ex_nvr/actions) 
    `,
  })
}

async function handleNervesBuildResult({ github, context, version, target, result }) {
  let body = ""
  if (result === "success") {
    body = `
      ✅ Build succeeded!
      Version: **${version}** for target: **${formatTarget(target)}** can be found on [NervesHub](https://manage.nervescloud.com/).
    `
  } else {
    body = `
      ❌ Build failed for version: **${version}**, target: **${formatTarget(target)}**
      Check the logs for more information.
    `
  }

  await postComment({ github, context, body })
}

async function parseBuildTarget({ github, context, core }) {
  const comment = context.payload.comment.body
  const target = comment.match(/^\/build\s+([a-z0-9_]+)/)?.[1]
  const validTargets = ["ex_nvr_rpi4", "ex_nvr_rpi5", "giraffe"]

  if (target && !validTargets.includes(target)) {
    await postComment({
      github,
      context,
      body: `
        ❌ Error: Invalid target **${target}** specified.
        Please try again with one of the following targets, or no target at all:
        ${validTargets.map((t) => `- ${t}`).join("\n")}
      `,
    })

    core.setFailed(`Invalid build target: ${target}`)
    process.exit()
    return
  }

  return target
}

async function getPrData({ github, context }) {
  const prUrl = context.payload.issue.pull_request.url
  const pr = await github.request(`GET ${prUrl}`)

  return {
    branch: pr.data.head.ref,
    sha: pr.data.head.sha.substring(0, 6),
  }
}

async function generateCustomVersion({ branch, sha, core }) {
  try {
    const mixExsPath = path.join(
      process.env.GITHUB_WORKSPACE,
      "nerves_fw",
      "mix.exs"
    )
    const mixExsContent = fs.readFileSync(mixExsPath, "utf8")
    const versionRegex = /@version\s+"([^"]+)"/
    const versionMatch = mixExsContent.match(versionRegex)
    const formattedBranch = branch.replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 5)

    return `${versionMatch[1]}-${formattedBranch}-${sha}`
  } catch (error) {
    core.setFailed(`Error reading mix.exs: ${error.message}`)
    process.exit()
  }
}

async function postComment({ github, context, body }) {
  const { owner, repo } = context.repo
  const { number } = context.issue || context.payload.pull_request

  await github.rest.issues.createComment({
    owner,
    repo,
    issue_number: number,
    body: dedent(body),
  })
}

function formatTarget(target = "") {
  return target?.trim()?.length ? target : "all"
}

function dedent (str = "") {
  return str.split('\n').map(l => l.trim()).join('\n')
}
