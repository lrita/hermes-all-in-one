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
RUN chmod 0755 /etc/cont-init.d/03-rtk-init /etc/cont-init.d/04-firecrawl-setup

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
