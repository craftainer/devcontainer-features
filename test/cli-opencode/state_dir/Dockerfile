# The state-directory scenario: ~/.config/opencode and
# ~/.local/share/opencode already exist in the base image, owned by root
# with mode 0755, as they would be if an earlier layer had created them. The
# feature must hand both to the remote user with mode 0700. Their parents
# (~/.config, ~/.local, ~/.local/share) belong to the home's owner, as they
# do in a normal home, since opencode creates its other XDG directories
# there at run time. The remote user isn't known here, so both candidate
# homes get them: root's and, on the devcontainers base images, vscode's.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN for home in /root /home/vscode; do \
        if [ -d "$home" ]; then \
            owner="$(stat -c '%u:%g' "$home")" \
            && install -d -o root -g root -m 0755 "$home/.config/opencode" "$home/.local/share/opencode" \
            && chown "$owner" "$home/.config" "$home/.local" "$home/.local/share"; \
        fi; \
    done
