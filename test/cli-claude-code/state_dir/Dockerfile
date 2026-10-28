# The state-directory scenario: ~/.claude already exists in the base image,
# owned by root with mode 0755, as it would be if an earlier layer had
# created it. The feature must hand it to the remote user with mode 0700.
# The remote user isn't known here, so both candidate homes get one: root's
# and, on the devcontainers base images, vscode's.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN install -d -o root -g root -m 0755 /root/.claude \
    && if [ -d /home/vscode ]; then install -d -o root -g root -m 0755 /home/vscode/.claude; fi
