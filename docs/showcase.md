# Public recruiter showcase

[Open the showcase](https://vinayreddi7206.github.io/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/)

This website lets visitors inspect the project's delivery pipeline, monitoring evidence and cloud architecture without running the local stack. It is a static presentation hosted on GitHub Pages, available for public repositories on GitHub Free. It does not provision AWS or Azure resources and does not expose the laptop, Kubernetes API, Grafana credentials, or cloud accounts. See [GitHub Pages availability](https://docs.github.com/en/pages/getting-started-with-github-pages).

## What is interactive

The pipeline stages expand to explain each check and link to source files or verification evidence. The public health report can be opened as JSON. Navigation and disclosure controls work without JavaScript, external fonts, analytics, or a backend connection.

The monitoring numbers are a recorded local snapshot from 10 September 2026, labeled with its timestamp. The snapshot matches the health report attached to the verified local demo release. CI links point to completed runs; they are evidence for those revisions, not a live status indicator. Cloud deployment remains pending.

## Source and publishing

`dist/index.html`, `dist/styles.css`, `dist/favicon.svg`, and `dist/health-check.json` are the complete public assets. No generated build or package installation is required.

GitHub Pages publishes from the root of `codex/showcase-pages`. That branch contains only the static website, extracted from the committed `dist` directory. After checking local asset references, anchors and snapshot values, commit the intended source changes on `main`, then publish them from PowerShell:

```powershell
$showcaseRevision = git subtree split --prefix=dist HEAD
if ($LASTEXITCODE -ne 0) { throw 'Showcase extraction failed.' }
git push origin ($showcaseRevision + ':refs/heads/codex/showcase-pages')
if ($LASTEXITCODE -ne 0) { throw 'Showcase publication push failed.' }
```

Do not force-push over an unexpected branch change. GitHub rebuilds the site after the publication branch changes. Check the Pages build result and unauthenticated HTTPS access before reporting a new version as live. This branch contains no application workflow or cloud deployment configuration.

The public repository's `main` branch remains the source for the full DevOps project. Pushing to `main` runs application CI; publishing the website is the separate branch update above. The website uses no custom domain purchase, external API, analytics, or paid cloud resource.

An initial Sites publication was attempted before GitHub Pages was configured, but its HTTPS destination was not ready during launch verification. `.openai/hosting.json` retains that registered Site for future troubleshooting; the GitHub Pages address above is the recruiter-facing link. No additional Site should be created to retry that publication.

## Scope of the live link

The website is public and hosted independently of the laptop. The Node.js API, live Grafana dashboard and complete Kubernetes system are still local. Hosting this showcase does not complete the original live AKS/EKS acceptance criteria.
