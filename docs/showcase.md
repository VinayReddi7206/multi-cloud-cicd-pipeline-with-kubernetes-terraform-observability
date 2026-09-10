# Public recruiter showcase

[Open the showcase](https://vinay-multicloud-cicd.chalky-bud-9961.chatgpt.site)

This website lets visitors inspect the project's delivery pipeline, monitoring evidence and cloud architecture without running the local stack. It is a static presentation hosted with Sites. It does not provision AWS or Azure resources and does not expose the laptop, Kubernetes API, Grafana credentials, or cloud accounts.

## What is interactive

The pipeline stages expand to explain each check and link to source files or verification evidence. The public health report can be opened as JSON. Navigation and disclosure controls work without JavaScript, external fonts, analytics, or a backend connection.

The monitoring numbers are a recorded local snapshot from 10 September 2026, labeled with its timestamp. The snapshot matches the health report attached to the verified local demo release. CI links point to completed runs; they are evidence for those revisions, not a live status indicator. Cloud deployment remains pending.

## Source and publishing

`dist/index.html`, `dist/styles.css`, `dist/favicon.svg`, and `dist/health-check.json` are the complete public assets. `.openai/hosting.json` identifies the Sites project and sets `static.directory` to `dist`. No generated build or package installation is required.

Validate local asset references, anchors and snapshot values before publishing. Push the exact validated source revision to the configured Sites source repository using a temporary per-command credential, package only the configured static assets, save the version, and deploy to the existing public audience. Verify deployment success and unauthenticated HTTP access before sharing the URL. Never commit source credentials.

The public GitHub repository remains the source for the full DevOps project. Pushing to GitHub runs the existing application CI; it does not automatically deploy the showcase to Sites. Showcase publication is a separate explicit operation.

## Scope of the live link

The website is public and hosted independently of the laptop. The Node.js API, live Grafana dashboard and complete Kubernetes system are still local. Hosting this showcase does not complete the original live AKS/EKS acceptance criteria.
