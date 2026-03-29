FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install essentials
RUN apt-get update && apt-get install -y \
    bash \
    git \
    jq \
    diffutils \
    && rm -rf /var/lib/apt/lists/*

# Create a test user (not root)
RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser

# Copy lfg repo
COPY --chown=testuser:testuser . /home/testuser/lfg/

# Set up a fake git repo so update checks don't fail
RUN cd /home/testuser/lfg && \
    git init && \
    git config user.name "Test" && \
    git config user.email "test@test.com" && \
    git add -A && \
    git commit -m "init"

# Create machine.conf for testing
RUN printf 'DOTS_GIT_NAME="Test User"\nDOTS_GIT_EMAIL="test@example.com"\nDOTS_GIT_CREDENTIAL_HELPER="cache"\n' \
    > /home/testuser/lfg/machine.conf

# Make scripts executable
RUN chmod +x /home/testuser/lfg/lfg \
    /home/testuser/lfg/software/common.sh \
    /home/testuser/lfg/packages/claude/install.sh

ENTRYPOINT ["bash", "/home/testuser/lfg/test/run_tests.sh"]
