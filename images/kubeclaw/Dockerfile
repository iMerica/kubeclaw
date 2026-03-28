ARG OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:2026.3.23-2@sha256:dda9f4b94761e87864c901cf34ee858daf89fa1deed9dcb671e8845a6b24062e

FROM --platform=$BUILDPLATFORM node:22-alpine AS tools-builder
ARG TARGETARCH
WORKDIR /workspace
RUN apk add --no-cache curl tar xz
COPY images/kubeclaw/packages.json /workspace/packages.json
COPY images/kubeclaw/scripts/install-tools.sh /workspace/install-tools.sh
COPY images/kubeclaw/scripts/install-npm-packages.sh /workspace/install-npm-packages.sh
RUN chmod +x /workspace/install-tools.sh /workspace/install-npm-packages.sh
RUN TARGETARCH=${TARGETARCH} PACKAGES_FILE=/workspace/packages.json OUT_BIN_DIR=/out/opt/kubeclaw/bin /workspace/install-tools.sh
RUN PACKAGES_FILE=/workspace/packages.json OUT_PREFIX=/out/opt/kubeclaw/npm-global OUT_BIN_DIR=/out/opt/kubeclaw/bin /workspace/install-npm-packages.sh

FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS go-builder
WORKDIR /workspace
COPY images/kubeclaw/packages.json /workspace/packages.json
COPY images/kubeclaw/scripts/install-go-packages.sh /workspace/install-go-packages.sh
RUN chmod +x /workspace/install-go-packages.sh
RUN PACKAGES_FILE=/workspace/packages.json OUT_BIN_DIR=/out/opt/kubeclaw/bin /workspace/install-go-packages.sh

FROM --platform=$BUILDPLATFORM oven/bun:1.2-alpine AS qmd-builder
WORKDIR /workspace
COPY images/kubeclaw/packages.json /workspace/packages.json
COPY images/kubeclaw/scripts/install-qmd.sh /workspace/install-qmd.sh
RUN chmod +x /workspace/install-qmd.sh
RUN PACKAGES_FILE=/workspace/packages.json OUT_QMD_DIR=/out/opt/kubeclaw/qmd-bin /workspace/install-qmd.sh

FROM ${OPENCLAW_IMAGE}
USER root

COPY images/kubeclaw/packages.json /opt/kubeclaw/packages.json
COPY images/kubeclaw/scripts/install-linux-packages.sh /opt/kubeclaw/bin/install-linux-packages.sh
COPY images/kubeclaw/scripts/install-skills-sh.sh /opt/kubeclaw/bin/install-skills-sh.sh
RUN chmod +x /opt/kubeclaw/bin/install-linux-packages.sh /opt/kubeclaw/bin/install-skills-sh.sh && /opt/kubeclaw/bin/install-linux-packages.sh && /opt/kubeclaw/bin/install-skills-sh.sh
RUN npm install --prefix /opt/kubeclaw/deps json5@2.2.3 --no-save --no-audit --no-fund

COPY --from=tools-builder /out/opt/kubeclaw/bin /opt/kubeclaw/bin
COPY --from=tools-builder /out/opt/kubeclaw/npm-global /opt/kubeclaw/npm-global
COPY --from=go-builder /out/opt/kubeclaw/bin /opt/kubeclaw/bin
COPY --from=qmd-builder /out/opt/kubeclaw/qmd-bin /opt/kubeclaw/qmd-bin

COPY images/kubeclaw/scripts/bootstrap.sh /opt/kubeclaw/bin/bootstrap.sh
COPY images/kubeclaw/scripts/merge-json5.js /opt/kubeclaw/bin/merge-json5.js
COPY images/kubeclaw/scripts/render-skills-config.js /opt/kubeclaw/bin/render-skills-config.js
COPY charts/kubeclaw/skillstacks /opt/kubeclaw/skillstacks

RUN chmod 0555 /opt/kubeclaw/bin/bootstrap.sh /opt/kubeclaw/bin/merge-json5.js /opt/kubeclaw/bin/render-skills-config.js

ENV PATH="/opt/kubeclaw/qmd-bin:/opt/kubeclaw/bin:${PATH}"

USER 1000
