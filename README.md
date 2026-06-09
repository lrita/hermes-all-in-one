# hermes-all-in-one

容器内有3个端口服务：

- hermes-webui: 8787
- hermes-dashboard: 9119
- hermes-api-server: 8642

## 构建镜像

使用项目根目录下的 `Dockerfile` 构建镜像：

```bash
docker build -t hermes-all-in-one:latest -f Dockerfile .
```

## 运行容器

```bash
docker run -d --name hermes-all-in-one \
    -p 8787:8787 \
    -p 9119:9119 \
    -p 8642:8642 \
    hermes-all-in-one:latest
```

## 配置 HermesAgent 向导

首次使用前，完成 模型、消息平台的交互式配置：

```bash
docker run -it --rm \
    -v hermes-data:/opt/data \
    hermes-all-in-one:latest \
    setup
```