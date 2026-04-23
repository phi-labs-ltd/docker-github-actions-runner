#!/usr/bin/env bash
set -euo pipefail

function install_git() {
  ( apt-get install -y --no-install-recommends git \
   || apt-get install -t stable -y --no-install-recommends git )
}

function install_liblttng-ust() {
  if [[ $(apt-cache search -n liblttng-ust0 | awk '{print $1}') == "liblttng-ust0" ]]; then
    apt-get install -y --no-install-recommends liblttng-ust0
  fi

  if [[ $(apt-cache search -n liblttng-ust1 | awk '{print $1}') == "liblttng-ust1" ]]; then
    apt-get install -y --no-install-recommends liblttng-ust1
  fi
}

function install_aws-cli() {
  ( curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip -d /tmp/ \
    && /tmp/aws/install \
    && rm awscliv2.zip \
  ) \
    || pip3 install --no-cache-dir awscli
}

function install_git-lfs() {
  local DPKG_ARCH
  DPKG_ARCH="$(dpkg --print-architecture)"
  GIT_LFS_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/git-lfs/git-lfs/releases/latest \
      | jq -r '.tag_name' | sed 's/^v//g')

  curl -s "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${DPKG_ARCH}-v${GIT_LFS_VERSION}.tar.gz" -L -o /tmp/lfs.tar.gz
  tar -xzf /tmp/lfs.tar.gz -C /tmp
  "/tmp/git-lfs-${GIT_LFS_VERSION}/install.sh"
  rm -rf /tmp/lfs.tar.gz "/tmp/git-lfs-${GIT_LFS_VERSION}"
}

function install_docker-cli() {
  apt-get install -y docker-ce-cli --no-install-recommends --allow-unauthenticated
}

function install_docker() {
  apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin containerd.io docker-compose-plugin --no-install-recommends --allow-unauthenticated

  echo -e '#!/bin/sh\ndocker compose --compatibility "$@"' > /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  sed -i 's/ulimit -Hn/# ulimit -Hn/g' /etc/init.d/docker
}

function install_container-tools() {
  ( apt-get install -y --no-install-recommends podman buildah skopeo || : )
}

function install_github-cli() {
  export PIP_BREAK_SYSTEM_PACKAGES=1
  local DPKG_ARCH GH_CLI_VERSION GH_CLI_DOWNLOAD_URL

  DPKG_ARCH="$(dpkg --print-architecture)"

  GH_CLI_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/cli/cli/releases/latest \
      | jq -r '.tag_name' | sed 's/^v//g')

  GH_CLI_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/cli/cli/releases/latest \
      | jq ".assets[] | select(.name == \"gh_${GH_CLI_VERSION}_linux_${DPKG_ARCH}.deb\")" \
      | jq -r '.browser_download_url')

  curl -sSLo /tmp/ghcli.deb "${GH_CLI_DOWNLOAD_URL}"
  apt-get -y install /tmp/ghcli.deb
  rm /tmp/ghcli.deb
}

function install_yq() {
  local DPKG_ARCH YQ_DOWNLOAD_URL

  DPKG_ARCH="$(dpkg --print-architecture)"

  YQ_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/mikefarah/yq/releases/latest \
      | jq ".assets[] | select(.name == \"yq_linux_${DPKG_ARCH}.tar.gz\")" \
      | jq -r '.browser_download_url')

  curl -s "${YQ_DOWNLOAD_URL}" -L -o /tmp/yq.tar.gz
  tar -xzf /tmp/yq.tar.gz -C /tmp
  mv "/tmp/yq_linux_${DPKG_ARCH}" /usr/local/bin/yq
}

function install_powershell() {
  local DPKG_ARCH PWSH_VERSION PWSH_DOWNLOAD_URL

  DPKG_ARCH="$(dpkg --print-architecture)"

  PWSH_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
      | jq -r '.tag_name' \
      | sed 's/^v//g')

  PWSH_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
      | jq -r ".assets[] | select(.name == \"powershell-${PWSH_VERSION}-linux-${DPKG_ARCH//amd64/x64}.tar.gz\") | .browser_download_url")

  curl -L -o /tmp/powershell.tar.gz "$PWSH_DOWNLOAD_URL"
  mkdir -p /opt/powershell
  tar zxf /tmp/powershell.tar.gz -C /opt/powershell
  chmod +x /opt/powershell/pwsh
  ln -s /opt/powershell/pwsh /usr/bin/pwsh
}

function install_ansible() {
  export PIP_BREAK_SYSTEM_PACKAGES=1
  pip3 install --no-cache-dir ansible
}

function install_go() {
  local DPKG_ARCH GO_VERSION GO_DOWNLOAD_URL
  DPKG_ARCH="$(dpkg --print-architecture)"

  GO_VERSION=$(curl -sSL https://go.dev/VERSION?m=text | head -n 1 | sed 's/^go//')

  GO_DOWNLOAD_URL="https://go.dev/dl/go${GO_VERSION}.linux-${DPKG_ARCH}.tar.gz"

  curl -sSL "${GO_DOWNLOAD_URL}" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm /tmp/go.tar.gz

  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
}

function install_rust() {
  export RUSTUP_HOME=/usr/local/rustup
  export CARGO_HOME=/usr/local/cargo

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile default --default-toolchain stable

  "${CARGO_HOME}/bin/rustup" toolchain install nightly --profile minimal --component rustfmt --component clippy

  "${CARGO_HOME}/bin/rustup" show
  "${CARGO_HOME}/bin/cargo" --version
  "${CARGO_HOME}/bin/rustc" --version
  "${CARGO_HOME}/bin/rustfmt" --version
  "${CARGO_HOME}/bin/cargo-clippy" --version
  "${CARGO_HOME}/bin/cargo" +nightly --version
  "${CARGO_HOME}/bin/rustc" +nightly --version

  # chmod -R a+w "$RUSTUP_HOME" "$CARGO_HOME"

  local bin
  for bin in cargo rustc rustup rustdoc rustfmt cargo-fmt cargo-clippy clippy-driver; do
    if [[ -x "${CARGO_HOME}/bin/${bin}" ]]; then
      ln -sf "${CARGO_HOME}/bin/${bin}" "/usr/local/bin/${bin}"
    fi
  done
}

function install_cargo-nextest() {
  local DPKG_ARCH NEXTEST_URL
  DPKG_ARCH="$(dpkg --print-architecture)"
  case "${DPKG_ARCH}" in
    amd64) NEXTEST_URL="https://get.nexte.st/latest/linux" ;;
    arm64) NEXTEST_URL="https://get.nexte.st/latest/linux-arm" ;;
    *) echo "Unsupported arch for cargo-nextest: ${DPKG_ARCH}"; exit 1 ;;
  esac

  curl -LsSf "${NEXTEST_URL}" | tar -xzf - -C /usr/local/cargo/bin cargo-nextest
  chmod +x /usr/local/cargo/bin/cargo-nextest
  ln -sf /usr/local/cargo/bin/cargo-nextest /usr/local/bin/cargo-nextest
  cargo-nextest --version
}

function install_cargo-machete() {
  local DPKG_ARCH TARGET MACHETE_VERSION MACHETE_URL
  DPKG_ARCH="$(dpkg --print-architecture)"
  case "${DPKG_ARCH}" in
    amd64) TARGET="x86_64-unknown-linux-musl" ;;
    arm64) TARGET="aarch64-unknown-linux-musl" ;;
    *) echo "Unsupported arch for cargo-machete: ${DPKG_ARCH}"; exit 1 ;;
  esac

  MACHETE_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/bnjbvr/cargo-machete/releases/latest \
      | jq -r '.tag_name' | sed 's/^v//g')

  MACHETE_URL="https://github.com/bnjbvr/cargo-machete/releases/download/v${MACHETE_VERSION}/cargo-machete-v${MACHETE_VERSION}-${TARGET}.tar.gz"

  curl -sSL "${MACHETE_URL}" -o /tmp/machete.tar.gz
  tar -xzf /tmp/machete.tar.gz -C /tmp
  mv "/tmp/cargo-machete-v${MACHETE_VERSION}-${TARGET}/cargo-machete" /usr/local/cargo/bin/cargo-machete
  chmod +x /usr/local/cargo/bin/cargo-machete
  ln -sf /usr/local/cargo/bin/cargo-machete /usr/local/bin/cargo-machete
  rm -rf /tmp/machete.tar.gz "/tmp/cargo-machete-v${MACHETE_VERSION}-${TARGET}"
  cargo-machete --version
}

function install_quint() {
  npm install -g @informalsystems/quint
  quint --version
}

function install_check-jsonschema() {
  export PIP_BREAK_SYSTEM_PACKAGES=1
  pip3 install --no-cache-dir check-jsonschema
  check-jsonschema --version
}

function install_tools() {
  local function_name
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

  script_packages | while read -r package; do
    function_name="install_${package}"
    if declare -f "${function_name}" > /dev/null; then
      "${function_name}"
    else
      echo "No install script found for package: ${package}"
      exit 1
    fi
  done
}
