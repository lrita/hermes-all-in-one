# ------------------------------------------------------------------------------
# hermes-workspace 产物来源镜像
#
# 仅用于向最终镜像拷贝其构建产物 /app（Node.js 应用），运行时依赖的 Node.js
# 由最终镜像自带，无需从此 stage 拷贝 node 运行时。
# ------------------------------------------------------------------------------
FROM ghcr.io/outsourc-e/hermes-workspace:latest AS hermes-workspace

# 构建最终的 All-in-One 镜像
FROM nousresearch/hermes-agent:latest

# ------------------------------------------------------------------------------
# 基础环境变量
# ------------------------------------------------------------------------------
ENV LANG=C.UTF-8 \
    TZ=Asia/Shanghai \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8 \
    PATH="/opt/hermes/.venv/bin:${PATH}"

# ------------------------------------------------------------------------------
# API Server / Dashboard 相关环境变量
#
# - API_SERVER_ENABLED: 开启 hermes-api-server（监听 8642 端口）。
# - HERMES_DASHBOARD: 置 1 开启 hermes-dashboard（监听 9119 端口）。
# - HERMES_DASHBOARD_HOST: hermes-dashboard 监听地址。
# - API_SERVER_KEY: API 访问密钥，不在镜像中预置，运行时通过
#   `docker run -e API_SERVER_KEY=xxx` 传入。
# ------------------------------------------------------------------------------
ENV API_SERVER_ENABLED=true \
    HERMES_DASHBOARD=1 \
    HERMES_DASHBOARD_HOST=127.0.0.1

# ------------------------------------------------------------------------------
# hermes-workspace 安装目录（构建期从 hermes-workspace 镜像拷贝产物到此）。
# 运行时业务环境变量（HERMES_API_URL / HERMES_DASHBOARD_URL / COOKIE_SECURE /
# HERMES_API_TOKEN / HERMES_WORKSPACE_DIR / HOST / PORT）在 s6 服务的 run
# 脚本中设置，因其依赖运行时传入的 API_SERVER_KEY。
# ------------------------------------------------------------------------------
ENV HERMES_WORKSPACE_APP_DIR=/opt/app

# ------------------------------------------------------------------------------
# Firecrawl Proxy 相关环境变量
# ------------------------------------------------------------------------------
ENV FIRECRAWL_PROXY_HOST=127.0.0.1 \
    FIRECRAWL_PROXY_PORT=3000 \
    FIRECRAWL_PROXY_DIR=/opt/firecrawl-proxy

# 切换为 root 用户以安装依赖
USER root

# ------------------------------------------------------------------------------
# 安装系统依赖
# ------------------------------------------------------------------------------
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        vim \
        patch \
        rsync \
        curl \
        wget \
        netbase \
        tzdata \
        ca-certificates \
        gnupg \
        openssh-client \
        git \
        xz-utils \
        tree \
        fd-find \
        jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# ------------------------------------------------------------------------------
# 设置时区
# ------------------------------------------------------------------------------
RUN ln -snf /usr/share/zoneinfo/"$TZ" /etc/localtime \
    && echo "$TZ" > /etc/timezone

# ------------------------------------------------------------------------------
# 将构建期 PATH 写入 /etc/profile.d，使 `bash -l` 也能继承该 PATH
# ------------------------------------------------------------------------------
RUN echo "export PATH=${PATH}:\$PATH" > /etc/profile.d/adding_path.sh \
    && chmod 644 /etc/profile.d/adding_path.sh

# ------------------------------------------------------------------------------
# 拷贝 s6-overlay 服务配置
# ------------------------------------------------------------------------------
COPY docker/s6-rc.d/        /etc/s6-overlay/s6-rc.d/
COPY docker/cont-init.d/03-rtk-init  /etc/cont-init.d/03-rtk-init
COPY docker/cont-init.d/04-firecrawl-setup /etc/cont-init.d/04-firecrawl-setup
COPY docker/cont-init.d/05-workspace-setup /etc/cont-init.d/05-workspace-setup
RUN chmod 0755 /etc/cont-init.d/03-rtk-init /etc/cont-init.d/04-firecrawl-setup /etc/cont-init.d/05-workspace-setup

# ------------------------------------------------------------------------------
# 安装 Firecrawl optional dependency
#
# - hermes-agent 的 pyproject.toml 中 firecrawl = ["firecrawl-py==4.17.0"]
#   是 [project.optional-dependencies] 中的可选依赖，需显式指定 --extra 安装。
# - 安装在 /opt/hermes 的共享 venv 中。
# - 必须在 clone firecrawl-proxy 之前完成，否则 firecrawl-proxy 运行时会因
#   缺少 firecrawl-py 报 ModuleNotFoundError。
# ------------------------------------------------------------------------------
RUN cd /opt/hermes \
    && uv pip install --no-cache-dir ".[firecrawl]"

# ------------------------------------------------------------------------------
# 克隆 Firecrawl Proxy 并安装依赖
#
# - git clone + uv pip install 安装 firecrawl-proxy，产物默认归 root；
#   运行时会切到 hermes 用户，因此构建期把源码树和共享 venv 改回 hermes 所有。
# - firecrawl-proxy 依赖已在 pyproject.toml 中声明，uv pip install -e .
#   会自动解析并安装到共享 venv。
# - 父镜像 stage2-hook 基于 venv owner 兜底执行的 chown -R 不会在
#   /opt/firecrawl-proxy 上触发，需在此显式执行。
# ------------------------------------------------------------------------------
RUN git clone --depth=1 https://github.com/lrita/firecrawl_proxy.git "$FIRECRAWL_PROXY_DIR" \
    && cd "$FIRECRAWL_PROXY_DIR" \
    && uv pip install --no-cache-dir -e . \
    && chown -R hermes:hermes "$FIRECRAWL_PROXY_DIR" /opt/hermes/.venv

# ------------------------------------------------------------------------------
# 拷贝 hermes-workspace 产物
#
# - 从 hermes-workspace 镜像拷贝其构建产物 /app 到 /opt/app（含 dist、
#   node_modules、server-entry.js、skills 等）。
# - 当前 Docker 版本不支持 COPY --chown，故拷贝后单独执行 chown，使运行时
#   以 hermes 用户启动的 hermes-workspace 服务能正常读写。
# - 运行时 Node.js 由基础镜像自带，无需从来源镜像拷贝 node。
# ------------------------------------------------------------------------------
COPY --from=hermes-workspace /app "$HERMES_WORKSPACE_APP_DIR"

RUN chown -R hermes:hermes "$HERMES_WORKSPACE_APP_DIR"

