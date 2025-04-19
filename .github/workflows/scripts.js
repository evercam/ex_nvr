const fs = require("fs")
const path = require("path")

module.exports = {
    postComment,
    getPrData,
    handleNervesBuildCommand,
    handleNervesBuildResult,
}

async function handleNervesBuildCommand({github, context, core}) {
    const {target, customVersion} = await parseBuildArguments({github, context, core})
    const {branch, sha} = await getPrData({github, context})
    const version = customVersion || await generateCustomVersion({branch, sha, core})

    core.setOutput("target", target)
    core.setOutput("version", version)
    core.setOutput("git_sha", sha)

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

async function handleNervesBuildResult({github, context, version, target, result}) {
    let body = ""
    if (result === "success") {
        body = `
            ✅ Build succeeded!
            Version: **${version}** for target: **${formatTarget(target)}** can be found on [NervesHub](https://manage.nervescloud.com/org/Evercam/ex_nvr_fw/firmware).
        `
    } else {
        body = `
            ❌ Build failed for version: **${version}**, target: **${formatTarget(target)}**
            Check the logs for more information.
        `
    }

    await postComment({github, context, body})
}

async function parseBuildArguments({github, context, core}) {
    const comment = context.payload.comment.body
    const commandRegex = /\/build(?:\s+(?!version=)([^\s]+))?(?:\s+version=([^\s]+))?/
    const [_, target, customVersion] = commandRegex.exec(comment) || []

    await validateTarget({github, context, core, target})
    await validateVersion({github, context, core, customVersion})

    return {target, customVersion}
}

async function validateTarget({github, context, core, target}) {
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
        return {}
    }

    return true
}

async function validateVersion({github, context, core, customVersion}) {
    const semVerRegex = /^\d+\.\d+\.\d+(?:-[\w\d.-]+)?(?:\+[\w\d.-]+)?$/
    if (customVersion && !semVerRegex.test(customVersion)) {
        await postComment({
            github,
            context,
            body: `
                ❌ Error: Invalid version format **${customVersion}**.
                Versions must follow semantic versioning format: MAJOR.MINOR.PATCH[PRERELEASE][BUILD]
                Examples: 1.0.0, 1.1.1-abcd, 0.22.1-alpha.1, 0.1.1-test-1, 1.42.3-beta.2+build.123
            `,
        })

        core.setFailed(`Invalid version format: ${customVersion}`)
        process.exit()
        return
    }

    return true
}

async function getPrData({github, context}) {
    const prUrl = context.payload.issue.pull_request.url
    const pr = await github.request(`GET ${prUrl}`)


    return {
        branch: pr.data.head.ref,
        sha: pr.data.head.sha,
    }
}

async function generateCustomVersion({branch, sha, core}) {
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
        const formattedSha = sha.slice(0, 5)

        return `${versionMatch[1]}-${formattedBranch}-${formattedSha}`
    } catch (error) {
        core.setFailed(`Error reading mix.exs: ${error.message}`)
        process.exit()
    }
}

async function postComment({github, context, body}) {
    const {owner, repo} = context.repo
    const {number} = context.issue || context.payload.pull_request

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

function dedent(str = "") {
    return str.split('\n').map(l => l.trim()).join('\n')
}
