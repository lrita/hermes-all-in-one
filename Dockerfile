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
# WebUI 相关环境变量
# ------------------------------------------------------------------------------
ENV HERMES_WEBUI_HOST=0.0.0.0 \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_AGENT_DIR=/opt/hermes \
    HERMES_WEBUI_DIR=/opt/hermes-webui \
    HERMES_WEBUI_DEFAULT_WORKSPACE=/opt/data/workspace \
    HERMES_WEBUI_STATE_DIR=/opt/data/webui

# 切换为 root 用户以安装依赖
USER root

# ------------------------------------------------------------------------------
# 安装 WebUI 运行所需的系统依赖
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

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
COPY docker/cont-init.d/03-rtk-init /etc/cont-init.d/03-rtk-init

# ------------------------------------------------------------------------------
# 克隆 WebUI 并安装依赖
# ------------------------------------------------------------------------------
RUN git clone --depth=1 https://github.com/nesquena/hermes-webui.git "$HERMES_WEBUI_DIR" \
    && uv pip install --no-cache-dir -r "$HERMES_WEBUI_DIR/requirements.txt"
