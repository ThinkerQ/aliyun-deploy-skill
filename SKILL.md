---
name: xinya-aliyun-deploy
description: 在阿里云 ECS 上部署与运维 xinya_ry（Ruoyi 教育系统）的 Docker 化全栈。每当用户提到：xinya、xinya_ry、新雅、若依教育系统、阿里云 ECS（${ECS_HOST}）、ACR 镜像（registry.cn-hangzhou.aliyuncs.com/xinya/*）、Ruoyi 后端/前端的发版/部署/回滚、c-xinya-app/c-xinya-mysql/c-xinya-redis/c-xinya-web/c-xinya-portal 容器、/home/ruoyi/uploadPath、xinya_hours 数据库、docker-compose.cloud.yml、或 ECS 上的 80/443 端口 HTTP 服务（会员端 /member、平台端 /platform、官网主站 /），**即使只是询问"现在 ECS 状态如何"、"我想发版"、"怎么回滚"、"/prod-api 502 了怎么办"、"portal 容器怎么升级"、"官网怎么改"，也应使用本 skill**。凭据与实际主机信息保存在 skill 根目录的私有 `.env`，示例见 `.env.example`；兼容已有项目 docker/.env.acr 与 .env.ecs。
---

# xinya-aliyun-deploy

本 skill 封装了在阿里云 ECS（`${ECS_HOST}`，Alibaba Cloud Linux 3）上部署与运维 xinya_ry 教育系统的全栈流程。
五个容器（c-xinya-mysql / c-xinya-redis / c-xinya-app / c-xinya-web / c-xinya-portal）已经正常运行。`c-xinya-web` 是会员端 + 平台端的 SPA（路由 `/member/*` 和 `/platform/*`），`c-xinya-portal` 是独立的官网主站（根路径 `/`），外层 nginx 1.24.0 在 443 端口做路径分流。若你需要：

- 发布后端 / 前端 / 官网主站新版本（构建 + 推 ACR + 让 ECS 拉取新镜像）
- 查看服务状态、日志、进入容器调试
- 立即备份数据库 / 看最近 14 天的备份
- 回滚到上一个版本
- 把端口冲突、502 错误、80 端口被旧 nginx 占着等坑排查掉
- 改外层 nginx 路径分流（新增路径 / 修复 portal 资源 404）

请按下面的能力列表选择路径，并先读取 `references/architecture.md` 了解当前 ECS 上的服务布局（含外层 nginx 路径分流规则），再用 `scripts/load-env.sh` 加载凭据。

## 凭据要求（每次会话第一步）

统一配置保存在 skill 根目录的私有 `.env`；新安装时复制 `.env.example` 并填写。
`.env` 使用 Bash 赋值语法，特殊字符必须正确引用；只加载可信配置。
已有项目 `docker/.env.acr` 和 `docker/.env.ecs` 仍兼容读取，统一 `.env` 中的配置优先。
数据库凭证、主机、域名和账号信息也从此处读取，不在脚本或文档中保存实际值。

`.gitignore` 已排除实际配置、私钥和备份；提交 GitHub 时只提交 `.env.example`。
禁止输出 `.env`、打印凭证变量或打开 shell 跟踪。后台账号变量仅记录初始化信息，
修改变量不会修改已部署的数据库密码、后台口令或项目初始化 SQL。
部署前须确认项目 compose 与初始化 SQL 使用相同凭证。

## 能力列表（十项）

每个能力对应一个工作流。下文给出**意图→命令**的映射，可直接复制执行。

### 1. status — 综合状态报告

```bash
bash scripts/status.sh
# 输出：容器状态 / 资源占用 / 磁盘 / 备份脚本状态 / systemd 状态 / 最近 ERROR
```
阅读输出后决定下一步（要不要发布/有没有报错）。

### 2. publish — 发版（最常用）

**什么时候用：** 改完后端 `ruoyi-admin/` 代码并已通过本地构建测试；要让 ECS 上跑新版本。

```bash
VERSION=v1.0.1 bash scripts/release.sh
```
脚本会：本地构建 + 推 ACR + 改 ECS `.env` 的 `IMAGE_TAG` + 拉取 + 重启 + 健康检查。任何一步失败立刻 exit 不继续。**会自动把上一个版本写到 `scripts/.rollback`**，便于回滚。

只发前端不动后端？脚本默认只构建 `app`；如果要构建 web，临时改脚本里 `-f` 参数或调用 `scripts/build-and-push-web.sh`：

```bash
VERSION=v1.0.1 bash scripts/build-and-push-web.sh
# 然后 ECS 端：
bash scripts/ecs.sh "cd /opt/xinya/docker && docker compose --env-file /opt/xinya/.env pull xinya-web && docker compose --env-file /opt/xinya/.env up -d xinya-web"
```

> ⚠️ 上面的 `build-and-push-web.sh` 在旧版 skill 中存在；本版 skill 的 web 构建命令已合并到 `release.sh`，不传 `SKIP_WEB=1` 即同时构建并发布 web。

### 2b. publish-portal — 单独发官网主站（portal）

**什么时候用：** 改了 `ruoyi-ui/public/portal/`（index.html / styles.css / main.js / assets/）后，要让官网主站看到新版本。

```bash
# 1) 本地构建 + 推 ACR（默认打两个 tag：vX.Y.Z + latest）
VERSION=v1.0.1 bash scripts/build-and-push-portal.sh

# 2) ECS 端升级 portal 容器（自动改 compose 文件的 portal tag + pull + 重建）
PORTAL_TAG=v1.0.1 bash scripts/upgrade-portal.sh
```

**portal 与 app/web 的镜像 tag 是独立的**——portal tag 不写进 `/opt/xinya/.env` 的 `IMAGE_TAG`（IMAGE_TAG 只控制 app/web）；portal tag 写在 `docker-compose.yml` 里 xinya-portal 服务的 image 字段。所以回滚 portal 时直接 `sed -i 's|portal:v.*|portal:vX.Y.Z|' /opt/xinya/docker/docker-compose.yml` 即可，不动 .env。

> 完整流程与排错见 `references/architecture.md §6 外层 nginx 路径分流` 与 `references/troubleshooting.md §16`。

### 3. rollback — 回滚

```bash
# 自动用 scripts/.rollback 里的上一个版本
bash scripts/rollback.sh

# 或手动指定版本
VERSION=v1.0.0 bash scripts/rollback.sh
```
回滚只换 `.env` 的 `IMAGE_TAG` 并重启后端，不会动 MySQL/Redis 数据，所以零数据风险。

### 4. logs — 看日志

```bash
# 默认看后端最近 100 行
bash scripts/logs.sh

# 指定服务与行数
SERVICE=xinya-web TAIL=300 bash scripts/logs.sh
SERVICE=xinya-mysql bash scripts/logs.sh
```
会先输出最近 ERROR 行（如有），避免浪费时间翻历史。

### 5. exec — 进入容器调试

```bash
# 进 MySQL CLI
bash scripts/exec.sh mysql

# 进 app 容器 shell
bash scripts/exec.sh app
```
`exec.sh` 接受 `mysql | app | web | redis | portal` 之一。portal 是独立容器，可直接进 shell 看 `/usr/share/nginx/html/portal/` 资源结构。

### 6. backup-now — 立即备份

```bash
bash scripts/backup-now.sh
```
强制跑一次 `backup.sh`，输出 `ls -lh /opt/xinya/backup/`，方便立刻拿 .sql.gz。

### 7. deploy-new — 全新部署或重置环境（慎用）

**什么时候用：** 第一台 ECS、ECS 重建后、或者想完全从头来过。

```bash
bash scripts/deploy-new.sh
```
脚本会：创建 `/opt/xinya/{docker,scripts,backup,sql/01-schema,sql/02-init-data,uploadPath}` + SCP 上传 `docker-compose.cloud.yml`、`scripts/backup.sh`、`systemd/xinya.service`、两个 SQL 初始化文件 → `.env` + `docker login ACR` → `docker compose pull && up -d` → 配置 systemd + cron。

如果预装的 nginx 占着 80 端口，脚本会先 `systemctl stop nginx && systemctl disable nginx`（**默认关闭，部署前会问**）。

### 8. reset-data — 重置数据（危险）

```bash
bash scripts/reset-data.sh
```
**会删掉 MySQL/Redis 数据卷**（`down -v`），然后用 dump 文件重新初始化。会给二次确认提示。运行前应当先 `bash scripts/backup-now.sh` 备份一次。

---

## 排错快捷表（先读 `references/troubleshooting.md`）

| 现象 | 第一反应 |
|---|---|
| 浏览器 `502 Bad Gateway` | `bash scripts/logs.sh && bash scripts/status.sh` |
| 容器 `Restarting (1)` | `bash scripts/logs.sh SERVICE=xinya-web`（八成是 nginx upstream 解析失败） |
| `Bind for 0.0.0.0:80: address already in use` | `bash scripts/diagnose.sh` —— 几乎肯定是旧 nginx 没停 |
| MySQL 启动后 `Table doesn't exist` | dump 文件未挂到 `/docker-entrypoint-initdb.d/` 直接子目录（**必须直接 .sql 文件，不能子目录**） |
| 拉 ACR 401 | 用户名用阿里云主账号**邮箱**而非 11 位账号 ID，参考 `references/troubleshooting.md §1` |
| SSH Permission denied | `.env.ecs` 里的密码不对，或换 `ECS_SSH_KEY` 用私钥方式 |

完整排错清单见 `references/troubleshooting.md`。

---

## 服务拓扑速记

完整版在 `references/architecture.md`。核心五点：

1. **Service 名 = DNS 名**（容器内互解析用）：`xinya-mysql` / `xinya-redis` / `xinya-app` / `xinya-web` / `xinya-portal`
2. **Container 名 = 主机进程名**（在 `docker ps` 里看到）：`c-xinya-mysql` / `c-xinya-redis` / `c-xinya-app` / `c-xinya-web` / `c-xinya-portal` —— 加 `c-` 前缀避免与本地部署冲突
3. **nginx upstream** 写死 `xinya-app`（Service 名），**不是 `c-xinya-app`**——这是 docker-compose 里服务名的设计，要求每次维护 compose 文件都保持这个区分
4. **MySQL 与 Redis 端口不暴露到主机**（防公网扫描）；需要远程调试用 `ssh -L 13306:localhost:3306 root@<ECS>` 端口转发
5. **外层 nginx 路径分流**：443 server 块按路径把请求转给 web（`/member/`、`/platform/`、`/prod-api/`、静态资源、SPA fallback）或 portal（`/`、`/styles.css`、`/main.js`、`/assets/`）。详细 location 优先级见 `references/architecture.md §6`。

## 文件位置速记

| 在哪 | 干什么 |
|---|---|
| `/opt/xinya/docker/docker-compose.yml` | 云端编排主文件（service 名 xinya-*） |
| `/opt/xinya/.env` | `ACR_REGISTRY` / `ACR_NAMESPACE` / `IMAGE_TAG` / `MYSQL_ROOT_PASSWORD` |
| `/opt/xinya/scripts/backup.sh` | 每日 03:00 cron 跑的 mysqldump |
| `/opt/xinya/sql/01-schema/01-xinya_hours_schema.sql` | CREATE TABLE |
| `/opt/xinya/sql/02-init-data/01-xinya_hours_data.sql` | INSERT 数据 |
| `/opt/xinya/uploadPath/` | 容器内 /home/ruoyi/uploadPath 的 bind mount |
| `/opt/xinya/backup/` | 14 天滚动保留的 .sql.gz |
| `/etc/systemd/system/xinya.service` | 开机自启的 compose 包装 |
| `/etc/cron.d/xinya-backup` | 定时任务配置 |

## ACR 镜像清单

```
registry.cn-hangzhou.aliyuncs.com/xinya/mysql:8.4
registry.cn-hangzhou.aliyuncs.com/xinya/redis:7.2-alpine
registry.cn-hangzhou.aliyuncs.com/xinya/app:v1.0.19      （后端，由 .env IMAGE_TAG 控制）
registry.cn-hangzhou.aliyuncs.com/xinya/web:v1.0.21      （前端，由 .env IMAGE_TAG 控制）
registry.cn-hangzhou.aliyuncs.com/xinya/portal:v1.0.1    （官网主站，独立 tag，不受 IMAGE_TAG 控制）
```

每次发版都打两个 tag：`<new-version>` 和 `latest`。MySQL/Redis 在第一次 init 后不再发版。**portal 单独走自己的 tag 体系**——发布时用 `bash scripts/build-and-push-portal.sh` + `bash scripts/upgrade-portal.sh`，与 `release.sh` 完全独立。
